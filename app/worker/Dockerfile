# ============================================================
# worker/Dockerfile
# Builds the SQS worker service.
# This is NOT a web server — it's a long-running background
# process that polls SQS and processes messages.
# Port: none (no HTTP server)
# ============================================================

FROM python:3.11-slim

WORKDIR /app

# Non-root user
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --no-create-home appuser

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY worker.py .
COPY secrets.py .

RUN chown -R appuser:appgroup /app

USER appuser

# No EXPOSE — worker has no HTTP port
# Python -u = unbuffered output so logs appear in CloudWatch immediately
CMD ["python", "-u", "worker.py"]
