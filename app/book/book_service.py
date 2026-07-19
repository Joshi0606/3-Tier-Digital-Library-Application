from flask import Flask, request, jsonify
import mysql.connector
import os
import logging
import json
import csv
import io
import boto3
from botocore.exceptions import ClientError
from secrets import load_config, get_db_password

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Load all config from SSM at startup
_cfg = load_config()

logging.info("=" * 50)
logging.info(f"DB_HOST : {_cfg['DB_HOST']}")
logging.info(f"DB_NAME : {_cfg['DB_NAME']}")
logging.info(f"DB_USER : {_cfg['DB_USER']}")
logging.info("=" * 50)


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
@app.route("/books/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200


# ==========================
# GET ALL BOOKS
# ==========================
# Unchanged from original.
@app.route("/books", methods=["GET"])
def get_books():
    try:
        conn   = get_db()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM books ORDER BY id")
        books  = cursor.fetchall()
        cursor.close()
        conn.close()
        logging.info(f"Returned {len(books)} books")
        return jsonify(books), 200
    except Exception as e:
        logging.error(f"get_books error: {str(e)}")
        return jsonify({"error": str(e)}), 500


# ==========================
# GET SINGLE BOOK
# ==========================
# Unchanged from original.
@app.route("/books/<int:book_id>", methods=["GET"])
def get_book(book_id):
    try:
        conn   = get_db()
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT * FROM books WHERE id = %s", (book_id,))
        book   = cursor.fetchone()
        cursor.close()
        conn.close()
        if not book:
            return jsonify({"error": "Book not found"}), 404
        return jsonify(book), 200
    except Exception as e:
        logging.error(f"get_book error: {str(e)}")
        return jsonify({"error": str(e)}), 500


# ==========================
# ADD SINGLE BOOK
# ==========================
# New endpoint. Adds one book and notifies all users via SQS.
@app.route("/books", methods=["POST"])
def add_book():
    try:
        data = request.get_json()
        title  = data.get("title")
        author = data.get("author")

        if not title or not author:
            return jsonify({"error": "title and author are required"}), 400

        conn   = get_db()
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO books (title, author) VALUES (%s, %s)",
            (title, author)
        )
        conn.commit()
        book_id = cursor.lastrowid
        cursor.close(); conn.close()

        # ── Notify users via SQS → worker → SNS ──────────────
        # Worker reads this and publishes to SNS topic which
        # emails all subscribed users about the new book.
        send_to_sqs({
            "event_type":  "new_book_added",
            "book_id":     book_id,
            "book_title":  title,
            "book_author": author
        })

        logging.info(f"Book added: {title} by {author}")
        return jsonify({"message": "Book added", "book_id": book_id}), 201

    except Exception as e:
        logging.error(f"add_book error: {str(e)}")
        return jsonify({"error": str(e)}), 500


# ==========================
# BULK BOOK IMPORT (CSV)
# ==========================
# Accepts a CSV file upload. Each row is queued as a separate
# SQS message. The worker inserts rows into DB one by one —
# this prevents long HTTP timeouts on large files and protects
# the DB from bulk insert spikes.
#
# CSV format (with header row):
#   title,author
#   Clean Code,Robert C. Martin
#   The Phoenix Project,Gene Kim
#
@app.route("/books/import", methods=["POST"])
def import_books():
    try:
        # Expect a file field named 'file' in the form data
        if "file" not in request.files:
            return jsonify({"error": "No file provided. Send CSV as 'file' field"}), 400

        file    = request.files["file"]
        content = file.read().decode("utf-8")
        reader  = csv.DictReader(io.StringIO(content))

        queued  = 0
        skipped = 0

        for row in reader:
            title  = row.get("title",  "").strip()
            author = row.get("author", "").strip()

            if not title or not author:
                skipped += 1
                continue

            # Each book row goes into SQS as a separate message.
            # The worker inserts it into the DB.
            # If the worker crashes mid-import, unprocessed messages
            # stay in the queue and get retried — no data loss.
            send_to_sqs({
                "event_type":  "bulk_book_import",
                "book_title":  title,
                "book_author": author
            })
            queued += 1

        logging.info(f"Bulk import: {queued} queued, {skipped} skipped")
        return jsonify({
            "message":       f"{queued} books queued for import",
            "queued":        queued,
            "skipped_rows":  skipped
        }), 202   # 202 Accepted — processing happens asynchronously

    except Exception as e:
        logging.error(f"import_books error: {str(e)}")
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5002)
