FROM python:3.11-slim

# Install system deps: curl + unzip for AWS CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws/

# Install uv
RUN pip install uv --no-cache-dir

WORKDIR /app

# Copy dependency files first — Docker layer caching means deps only reinstall
# when pyproject.toml or uv.lock change, not on every code change
COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --frozen

# Copy source and config
COPY src/ ./src/
COPY configs/ ./configs/

# Dirs expected by the pipeline
RUN mkdir -p models data/raw data/processed

COPY train_entrypoint.sh ./train_entrypoint.sh
RUN chmod +x train_entrypoint.sh

ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["./train_entrypoint.sh"]
