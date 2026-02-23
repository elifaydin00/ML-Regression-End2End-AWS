# Production inference container
FROM python:3.11-slim

# Set working directory inside container
WORKDIR /app

# Install system dependencies including AWS CLI
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files first (better caching)
COPY pyproject.toml uv.lock* ./

# Install uv (dependency manager)
RUN pip install uv
RUN uv sync --frozen --no-dev

# Copy project files
COPY src/ ./src/
COPY configs/ ./configs/

# Create models directory
RUN mkdir -p models

# Environment variables for S3
ENV S3_BUCKET=house-forecast
ENV AWS_REGION=us-east-1
ENV PYTHONPATH=/app

# Copy model download script
COPY scripts/download_models.sh /app/
RUN chmod +x /app/download_models.sh

# Expose FastAPI default port
EXPOSE 8000

# Download latest models from S3 then start API
CMD ["/bin/bash", "-c", "/app/download_models.sh && uv run uvicorn src.api.main:app --host 0.0.0.0 --port 8000"]

