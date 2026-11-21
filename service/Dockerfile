FROM python:3.11.9-slim-bookworm AS builder

WORKDIR /app

RUN python -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt


FROM python:3.11.9-slim-bookworm AS runtime

WORKDIR /app

RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --create-home appuser

COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appgroup app.py .
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
ENV APP_NAME="my-app" \
    VERSION="1.0.0"
USER appuser
EXPOSE 8012
CMD ["python", "app.py"]
