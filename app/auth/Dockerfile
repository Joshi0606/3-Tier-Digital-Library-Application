# ============================================================
# auth/Dockerfile  —  Flask auth service
# Port: 5001  |  Health: GET /auth/health
# Server: gunicorn (WSGI — correct for Flask)
# ============================================================

FROM python:3.11-slim

WORKDIR /app

# Create non-root user
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --no-create-home appuser

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY auth_service.py .
COPY secrets.py .

RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 5001

CMD ["gunicorn", "auth_service:app", "--bind", "0.0.0.0:5001", "--workers", "2", "--timeout", "60"]
