"""
worker.py — SQS Message Worker

This service runs as a separate pod in EKS alongside the Flask services.
It continuously polls the SQS queue and processes messages based on event_type.

Three event types handled:
  1. borrow_confirmation → sends confirmation email via SNS
  2. new_book_added      → notifies all subscribers via SNS
  3. bulk_book_import    → inserts a single book into RDS

Why a separate worker instead of processing inside Flask?
  - Flask handles HTTP requests — it should respond fast
  - Email sending, DB inserts, and retries happen here, not in the API
  - If the worker crashes, SQS keeps messages safe until it restarts
  - DLQ catches messages that fail 3 times for investigation
"""

import json
import logging
import os
import time

import boto3
import mysql.connector
from botocore.exceptions import ClientError
from secrets import load_config, get_db_password

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# Load all config from SSM at startup — blocks until fetched
_cfg          = load_config()
REGION        = _cfg["AWS_REGION"]
SQS_QUEUE_URL = _cfg["SQS_QUEUE_URL"]
SNS_TOPIC_ARN = _cfg["SNS_TOPIC_ARN"]

sqs = boto3.client("sqs", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)


# ── Database connection ───────────────────────────────────────
def get_db():
    return mysql.connector.connect(
        host=_cfg["DB_HOST"],
        user=_cfg["DB_USER"],
        password=get_db_password(),
        database=_cfg["DB_NAME"]
    )


# ── Event handlers ────────────────────────────────────────────

def handle_borrow_confirmation(data: dict):
    """
    Sends a borrow confirmation email to the user via SNS.
    SNS delivers it to the user's email subscription.
    If the user has no SNS subscription, the message is published
    to the ops topic — extend this to use SES for per-user emails.
    """
    user_name  = data.get("user_name",  "User")
    user_email = data.get("user_email", "")
    book_title = data.get("book_title", "")
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
    logging.info(f"Borrow confirmation sent for user {user_email} — book: {book_title}")


def handle_new_book_added(data: dict):
    """
    Notifies all SNS subscribers that a new book was added.
    Everyone subscribed to the topic receives this email.
    """
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
    """
    Inserts a single book into the RDS database.
    Each CSV row arrives as a separate SQS message so:
      - Large imports don't time out the API
      - Failed rows go to DLQ for investigation
      - DB is never hammered with bulk inserts
    """
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
    cursor.close(); conn.close()
    logging.info(f"Bulk import — inserted: {title} by {author}")


# ── Message dispatcher ────────────────────────────────────────

def process_message(message: dict):
    """
    Routes each SQS message to the correct handler based on event_type.
    Unrecognised event types are logged and skipped (not retried).
    """
    event_type = message.get("event_type")

    if event_type == "borrow_confirmation":
        handle_borrow_confirmation(message)

    elif event_type == "new_book_added":
        handle_new_book_added(message)

    elif event_type == "bulk_book_import":
        handle_bulk_book_import(message)

    else:
        logging.warning(f"Unknown event_type: {event_type} — skipping")


# ── Main polling loop ─────────────────────────────────────────

def run():
    """
    Polls SQS continuously.
    Long polling (WaitTimeSeconds=20) reduces empty API calls and cost.
    Each message is deleted only after successful processing.
    If processing raises an exception, the message is NOT deleted —
    SQS makes it visible again after visibility_timeout and retries it.
    After 3 failures it moves to the Dead Letter Queue (DLQ).
    """
    logging.info(f"Worker started. Polling queue: {SQS_QUEUE_URL}")

    while True:
        try:
            response = sqs.receive_message(
                QueueUrl            = SQS_QUEUE_URL,
                MaxNumberOfMessages = 10,     # process up to 10 at once
                WaitTimeSeconds     = 20,     # long poll — waits 20s for messages
                VisibilityTimeout   = 60      # worker has 60s to process each message
            )

            messages = response.get("Messages", [])

            if not messages:
                logging.debug("No messages — waiting...")
                continue

            for msg in messages:
                receipt_handle = msg["ReceiptHandle"]
                try:
                    body = json.loads(msg["Body"])
                    logging.info(f"Processing: {body.get('event_type')} — id: {msg['MessageId']}")

                    process_message(body)

                    # Delete message only after successful processing
                    sqs.delete_message(
                        QueueUrl      = SQS_QUEUE_URL,
                        ReceiptHandle = receipt_handle
                    )
                    logging.info(f"Message processed and deleted: {msg['MessageId']}")

                except Exception as e:
                    # Don't delete — SQS will retry after visibility timeout
                    logging.error(f"Failed to process message {msg['MessageId']}: {e}")

        except ClientError as e:
            logging.error(f"SQS receive error: {e}")
            time.sleep(5)   # brief pause before retrying on AWS errors

        except Exception as e:
            logging.error(f"Unexpected worker error: {e}")
            time.sleep(5)


if __name__ == "__main__":
    run()
