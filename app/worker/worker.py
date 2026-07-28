import json
import logging
import sys
import time

import boto3
import mysql.connector
from botocore.exceptions import ClientError
from secrets import load_config, get_db_password

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

_cfg          = load_config()
REGION        = _cfg["AWS_REGION"]
SQS_QUEUE_URL = _cfg["SQS_QUEUE_URL"]
SNS_TOPIC_ARN = _cfg["SNS_TOPIC_ARN"]

KNOWN_EVENT_TYPES = {"borrow_confirmation", "new_book_added", "bulk_book_import"}

sqs = boto3.client("sqs", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)


# Database

def get_db():
    return mysql.connector.connect(
        host=_cfg["DB_HOST"],
        user=_cfg["DB_USER"],
        password=get_db_password(),
        database=_cfg["DB_NAME"]
    )


# Event handlers

def handle_borrow_confirmation(data: dict):
    user_name   = data.get("user_name",  "User")
    user_email  = data.get("user_email", "")
    book_title  = data.get("book_title", "")
    book_author = data.get("book_author", "")

    message = (
        f"Hello {user_name},\n\n"
        f"You have successfully borrowed:\n"
        f"  Title:  {book_title}\n"
        f"  Author: {book_author}\n\n"
        f"Happy reading!\n"
        f"— Digital Library Team"
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"Borrow Confirmed: {book_title}",
        Message=message
    )
    logging.info(f"Borrow confirmation sent — user: {user_email}, book: {book_title}")


def handle_new_book_added(data: dict):
    book_title  = data.get("book_title",  "")
    book_author = data.get("book_author", "")

    message = (
        f"A new book has been added to the Digital Library!\n\n"
        f"  Title:  {book_title}\n"
        f"  Author: {book_author}\n\n"
        f"Log in to borrow it now."
    )

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"New Book Available: {book_title}",
        Message=message
    )
    logging.info(f"New book notification sent: {book_title}")


def handle_bulk_book_import(data: dict):
    title  = data.get("book_title",  "").strip()
    author = data.get("book_author", "").strip()

    if not title or not author:
        logging.warning(f"Skipping invalid bulk import row: {data}")
        return

    conn   = get_db()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT IGNORE INTO books (title, author) VALUES (%s, %s)",
        (title, author)
    )
    conn.commit()
    cursor.close()
    conn.close()
    logging.info(f"Bulk import — inserted: {title} by {author}")


# Message dispatcher

def process_message(message: dict):
    event_type = message.get("event_type")

    if event_type not in KNOWN_EVENT_TYPES:
        # Unknown event types are raised so SQS retries and eventually routes
        # to DLQ — silent skipping would hide producer-side bugs.
        raise ValueError(f"Unknown event_type: '{event_type}' — routing to DLQ after max retries")

    if event_type == "borrow_confirmation":
        handle_borrow_confirmation(message)
    elif event_type == "new_book_added":
        handle_new_book_added(message)
    elif event_type == "bulk_book_import":
        handle_bulk_book_import(message)


# Main polling loop

def run():
    logging.info(f"Worker started. Polling: {SQS_QUEUE_URL}")

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl               = SQS_QUEUE_URL,
                MaxNumberOfMessages    = 10,
                WaitTimeSeconds        = 20,   # long polling — reduces empty API calls
                VisibilityTimeout      = 60,
                AttributeNames         = ["ApproximateReceiveCount"],
                MessageAttributeNames  = ["All"],
            )

            messages = response.get("Messages", [])

            if not messages:
                continue

            for msg in messages:
                receipt_handle   = msg["ReceiptHandle"]
                receive_count    = int(msg.get("Attributes", {}).get("ApproximateReceiveCount", 0))
                message_id       = msg["MessageId"]

                try:
                    body = json.loads(msg["Body"])
                    logging.info(
                        f"Processing: {body.get('event_type')} — "
                        f"id: {message_id} — attempt: {receive_count}"
                    )

                    process_message(body)

                    sqs.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=receipt_handle)
                    logging.info(f"Deleted: {message_id}")

                except (KeyboardInterrupt, SystemExit):
                    # Never catch shutdown signals in the inner loop — re-raise immediately
                    raise

                except Exception as e:
                    # Message is NOT deleted — SQS will make it visible again after
                    # VisibilityTimeout and retry. After maxReceiveCount failures
                    # it moves to the DLQ and triggers the CloudWatch alarm.
                    logging.error(
                        f"Failed to process {message_id} "
                        f"(attempt {receive_count}): {e}"
                    )

        except (KeyboardInterrupt, SystemExit):
            logging.info("Worker shutting down.")
            sys.exit(0)

        except ClientError as e:
            logging.error(f"SQS receive error: {e}")
            time.sleep(5)

        except Exception as e:
            logging.error(f"Unexpected worker error: {e}")
            time.sleep(5)


if __name__ == "__main__":
    run()
