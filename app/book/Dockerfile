# ============================================================
# book/Dockerfile  —  Flask book service
# Port: 5002  |  Health: GET /books/health
# Server: gunicorn (WSGI — correct for Flask)
# ============================================================

FROM python:3.11-slim

WORKDIR /app

RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --no-create-home appuser

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY book_service.py .
COPY secrets.py .

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 5002

CMD ["gunicorn", "book_service:app", "--bind", "0.0.0.0:5002", "--workers", "2", "--timeout", "60"]
