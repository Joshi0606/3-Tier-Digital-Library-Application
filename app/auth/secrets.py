"""
secrets.py — AWS SSM + Secrets Manager config loader

Fetches ALL runtime config from SSM Parameter Store and the DB password
from Secrets Manager once at pod startup, caches in memory.

SSM paths (created by Terraform modules/ssm/):
  /digital-library/prod/config/rds_endpoint      → DB_HOST
  /digital-library/prod/config/rds_db_name       → DB_NAME
  /digital-library/prod/config/rds_db_user       → DB_USER
  /digital-library/prod/config/rds_secret_arn    → used to fetch DB password
  /digital-library/prod/config/orders_queue_url  → SQS_QUEUE_URL
  /digital-library/prod/config/sns_topic_arn     → SNS_TOPIC_ARN
  /digital-library/prod/config/assets_bucket     → S3_BUCKET

DB password comes from Secrets Manager (ARN stored in SSM above).

Local dev fallback: if AWS_SSM_PATH is not set, falls back to env vars
so docker-compose works unchanged.
"""

import json
import logging
import os

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

# Module-level cache — loaded once on first call to load_config()
_config: dict | None = None


def load_config() -> dict:
    """
    Returns the full config dict. Fetches from SSM+Secrets Manager on
    first call, returns cached value on every subsequent call.
    """
    global _config
    if _config is not None:
        return _config

    ssm_path = os.getenv("AWS_SSM_PATH")

    # ── Local dev fallback ────────────────────────────────────
    # docker-compose sets env vars directly — no SSM needed
    if not ssm_path:
        logger.info("AWS_SSM_PATH not set — using env vars (local dev mode)")
        _config = {
            "DB_HOST":       os.getenv("DB_HOST", "localhost"),
            "DB_NAME":       os.getenv("DB_NAME", "digital_library"),
            "DB_USER":       os.getenv("DB_USER", "root"),
            "DB_PASSWORD":   os.getenv("DB_PASSWORD", ""),
            "SQS_QUEUE_URL": os.getenv("SQS_QUEUE_URL", ""),
            "SNS_TOPIC_ARN": os.getenv("SNS_TOPIC_ARN", ""),
            "S3_BUCKET":     os.getenv("S3_BUCKET", ""),
            "AWS_REGION":    os.getenv("AWS_REGION", "us-east-1"),
        }
        return _config

    # ── Production: fetch all params from SSM ────────────────
    region = os.getenv("AWS_REGION", "us-east-1")
    ssm    = boto3.client("ssm", region_name=region)

    try:
        logger.info(f"Fetching config from SSM path: {ssm_path}")
        response = ssm.get_parameters_by_path(
            Path=ssm_path,
            Recursive=True,
            WithDecryption=True   # handles SecureString params too
        )
        # Build a flat dict keyed by the last segment of the parameter name
        # e.g. /digital-library/prod/config/rds_endpoint → rds_endpoint
        params = {
            p["Name"].split("/")[-1]: p["Value"]
            for p in response["Parameters"]
        }
        logger.info(f"Loaded {len(params)} parameters from SSM")
    except ClientError as e:
        logger.error(f"Failed to fetch SSM parameters: {e}")
        raise RuntimeError("Cannot start: SSM config unavailable") from e

    # ── Fetch DB password from Secrets Manager ────────────────
    rds_secret_arn = params.get("rds_secret_arn")
    if not rds_secret_arn:
        raise RuntimeError("Cannot start: rds_secret_arn missing from SSM")

    try:
        sm = boto3.client("secretsmanager", region_name=region)
        secret_response = sm.get_secret_value(SecretId=rds_secret_arn)
        rds_secret = json.loads(secret_response["SecretString"])
        db_password = rds_secret["password"]
        logger.info("DB password fetched from Secrets Manager successfully")
    except ClientError as e:
        logger.error(f"Failed to fetch DB password from Secrets Manager: {e}")
        raise RuntimeError("Cannot start: DB password unavailable") from e

    # RDS endpoint includes port (host:3306) — strip the port for mysql connector
    rds_endpoint = params.get("rds_endpoint", "")
    db_host = rds_endpoint.split(":")[0] if ":" in rds_endpoint else rds_endpoint

    _config = {
        "DB_HOST":       db_host,
        "DB_NAME":       params.get("rds_db_name", ""),
        "DB_USER":       params.get("rds_db_user", ""),
        "DB_PASSWORD":   db_password,
        "SQS_QUEUE_URL": params.get("orders_queue_url", ""),
        "SNS_TOPIC_ARN": params.get("sns_topic_arn", ""),
        "S3_BUCKET":     params.get("assets_bucket", ""),
        "AWS_REGION":    region,
    }
    return _config


def get_db_password() -> str:
    return load_config()["DB_PASSWORD"]


def get(key: str, default: str = "") -> str:
    """Convenience getter — load_config() once, read any key."""
    return load_config().get(key, default)
