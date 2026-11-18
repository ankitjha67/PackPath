# PackPath backend — self-host image.
# Build from the repo root context is not required; this Dockerfile is
# self-contained within apps/backend.
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Install dependencies first for better layer caching.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# App source + migrations.
COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

EXPOSE 8000

# Runs migrations, then the API. Override CMD to change the worker setup.
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
