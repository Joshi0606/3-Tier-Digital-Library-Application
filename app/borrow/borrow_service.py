from flask import Flask, request, jsonify
import mysql.connector
import os
import logging
import json
import boto3
from botocore.exceptions import ClientError
from secrets import load_config, get_db_password

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Load all config from SSM at startup
_cfg = load_config()


# ==========================
# DATABASE CONNECTION
# ==========================
def get_db():
    return mysql.connector.connect(
        host=_cfg["DB_HOST"],
        user=_cfg["DB_USER"],
        password=get_db_password(),
        database=_cfg["DB_NAME"]
    )


# ==========================
# SQS HELPER
# ==========================
def send_to_sqs(message: dict):
    queue_url = _cfg.get("SQS_QUEUE_URL")
    if not queue_url:
        logging.info("SQS_QUEUE_URL not set — skipping SQS publish (local dev mode)")
        return
    try:
        sqs = boto3.client("sqs", region_name=_cfg["AWS_REGION"])
        sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(message))
        logging.info(f"SQS message sent: {message.get('event_type')}")
    except ClientError as e:
        logging.error(f"SQS publish failed (non-critical): {e}")


# ==========================
# HEALTH CHECK
# ==========================
# ALB target group health check path: /borrow/health
@app.route("/borrow/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


# ==========================
# BORROW A BOOK
# ==========================
# Existing logic is UNCHANGED.
# After saving the record we additionally publish to SQS
# so a worker can send a confirmation email asynchronously.
@app.route("/borrow", methods=["POST"])
def borrow_book():
    try:
        data = request.json
        if not data or "user_id" not in data or "book_id" not in data:
            return jsonify({"error": "user_id and book_id are required"}), 400

        conn   = get_db()
        cursor = conn.cursor(dictionary=True)

        # Check book exists
        cursor.execute("SELECT id, title, author FROM books WHERE id = %s", (data["book_id"],))
        book = cursor.fetchone()
        if not book:
            cursor.close(); conn.close()
            return jsonify({"error": "Book not found"}), 404

        # Check not already borrowed
        cursor.execute(
            "SELECT id FROM borrow_records WHERE user_id = %s AND book_id = %s",
            (data["user_id"], data["book_id"])
        )
        if cursor.fetchone():
            cursor.close(); conn.close()
            return jsonify({"error": "Already borrowed"}), 409

        # ── Insert borrow record (unchanged) ──────────────────
        cursor.execute(
            "INSERT INTO borrow_records (user_id, book_id) VALUES (%s, %s)",
            (data["user_id"], data["book_id"])
        )
        conn.commit()

        # Fetch user email for notification
        cursor.execute("SELECT name, email FROM users WHERE id = %s", (data["user_id"],))
        user = cursor.fetchone()

        cursor.close(); conn.close()

        # ── Publish to SQS for async confirmation email ───────
        # This runs AFTER the DB commit so the response is never delayed.
        # The worker pod reads this message and sends the email.
        send_to_sqs({
            "event_type":  "borrow_confirmation",
            "user_id":     data["user_id"],
            "user_name":   user["name"]  if user else "",
            "user_email":  user["email"] if user else "",
            "book_id":     data["book_id"],
            "book_title":  book["title"],
            "book_author": book["author"]
        })

        return jsonify({"message": "Book borrowed"}), 201

    except Exception as e:
        logging.error(str(e))
        return jsonify({"error": str(e)}), 500


# ==========================
# MY BORROWED BOOKS
# ==========================
# Unchanged from original.
@app.route("/borrow/mybooks/<int:user_id>", methods=["GET"])
def my_books(user_id):
    try:
        conn   = get_db()
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            """
            SELECT b.title, b.author, br.borrow_date
            FROM borrow_records br
            JOIN books b ON br.book_id = b.id
            WHERE br.user_id = %s
            ORDER BY br.borrow_date DESC
            """,
            (user_id,)
        )
        books = cursor.fetchall()
        cursor.close(); conn.close()
        return jsonify(books), 200

    except Exception as e:
        logging.error(str(e))
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5003)
