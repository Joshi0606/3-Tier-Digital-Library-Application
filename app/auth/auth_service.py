from flask import Flask, request, jsonify
from flask_cors import CORS
import mysql.connector
from mysql.connector import Error
import hashlib
import logging
import os
from secrets import load_config, get_db_password

app = Flask(__name__)
CORS(app)

logging.basicConfig(level=logging.INFO)

# Load all config from SSM at startup
_cfg = load_config()


# ==========================
# DATABASE CONNECTION
# ==========================
def get_db():
    try:
        connection = mysql.connector.connect(
            host=_cfg["DB_HOST"],
            user=_cfg["DB_USER"],
            password=get_db_password(),
            database=_cfg["DB_NAME"],
            port=int(_cfg.get("DB_PORT", "3306"))
        )
        if connection.is_connected():
            return connection
    except Error as e:
        logging.error(f"Database Connection Error : {e}")
        raise


# ==========================
# PASSWORD HASHING
# ==========================
def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()


# ==========================
# HEALTH CHECK
# ==========================
@app.route("/auth/health", methods=["GET"])
def health():
    try:
        conn = get_db()
        conn.close()

        return jsonify({
            "status": "healthy",
            "database": "connected"
        }), 200

    except Exception as e:

        return jsonify({
            "status": "unhealthy",
            "error": str(e)
        }), 500


# ==========================
# SIGNUP
# ==========================
@app.route("/auth/signup", methods=["POST"])
def signup():

    try:

        data = request.get_json()

        name = data.get("name")
        email = data.get("email")
        password = data.get("password")

        if not name or not email or not password:

            return jsonify({
                "error": "All fields are required"
            }), 400

        conn = get_db()
        cursor = conn.cursor(dictionary=True)

        cursor.execute(
            "SELECT id FROM users WHERE email=%s",
            (email,)
        )

        if cursor.fetchone():

            cursor.close()
            conn.close()

            return jsonify({
                "error": "Email already exists"
            }), 409

        hashed_password = hash_password(password)

        cursor.execute(
            """
            INSERT INTO users
            (name,email,password)

            VALUES(%s,%s,%s)
            """,
            (name, email, hashed_password)
        )

        conn.commit()

        user_id = cursor.lastrowid

        cursor.close()
        conn.close()

        logging.info(f"User Registered : {email}")

        return jsonify({

            "message": "User created successfully",

            "user_id": user_id

        }), 201

    except Exception as e:

        logging.error(e)

        return jsonify({

            "error": str(e)

        }), 500


# ==========================
# LOGIN
# ==========================
@app.route("/auth/signin", methods=["POST"])
def signin():

    try:

        data = request.get_json()

        email = data.get("email")
        password = data.get("password")

        if not email or not password:

            return jsonify({

                "error": "Email and Password required"

            }), 400

        conn = get_db()

        cursor = conn.cursor(dictionary=True)

        cursor.execute(
            """
            SELECT *

            FROM users

            WHERE email=%s
            """,
            (email,)
        )

        user = cursor.fetchone()

        cursor.close()
        conn.close()

        if not user:

            return jsonify({

                "message": "User not found"

            }), 404

        if user["password"] != hash_password(password):

            return jsonify({

                "message": "Invalid password"

            }), 401

        logging.info(f"Login Success : {email}")

        return jsonify({

            "message": "Login successful",

            "user_id": user["id"],

            "name": user["name"],

            "email": user["email"]

        }), 200

    except Exception as e:

        logging.error(e)

        return jsonify({

            "error": str(e)

        }), 500


# ==========================
# RUN APPLICATION
# ==========================
if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5001,
        debug=True
    )