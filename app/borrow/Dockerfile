# ============================================================
# borrow/Dockerfile  —  Flask borrow service
# Port: 5003  |  Health: GET /borrow/health
# Server: gunicorn (WSGI — correct for Flask)
# ============================================================

FROM python:3.11-slim

WORKDIR /app

RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --no-create-home appuser

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY borrow_service.py .
COPY secrets.py .

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 5003

CMD ["gunicorn", "borrow_service:app", "--bind", "0.0.0.0:5003", "--workers", "2", "--timeout", "60"]
