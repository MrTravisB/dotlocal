#!/bin/bash
set -e

cd "$(dirname "$0")"

# Check if .env exists, if not copy from .env.example
if [ ! -f .env ]; then
  echo "Creating .env from .env.example..."
  cp .env.example .env
  
  # Generate secure random values for secrets
  echo "Generating secure secrets..."
  
  # Generate passwords (24 characters base64)
  POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  CLICKHOUSE_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  MINIO_ROOT_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  SALT=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  NEXTAUTH_SECRET=$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  
  # Generate encryption key (64 characters hex)
  ENCRYPTION_KEY=$(openssl rand -hex 32)
  
  # Replace CHANGEME placeholders with generated values (atomic secrets only)
  sed -i.bak "s/POSTGRES_PASSWORD=langfuse-postgres-password  # CHANGEME/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" .env
  sed -i.bak "s/CLICKHOUSE_PASSWORD=langfuse-clickhouse-password  # CHANGEME/CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD}/" .env
  sed -i.bak "s/REDIS_AUTH=langfuse-redis-password  # CHANGEME/REDIS_AUTH=${REDIS_PASSWORD}/" .env
  sed -i.bak "s/MINIO_ROOT_PASSWORD=langfuse-minio-password  # CHANGEME/MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}/" .env
  sed -i.bak "s/SALT=salt-value-change-me-please  # CHANGEME/SALT=${SALT}/" .env
  sed -i.bak "s/ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000  # CHANGEME - Generate with: openssl rand -hex 32/ENCRYPTION_KEY=${ENCRYPTION_KEY}/" .env
  sed -i.bak "s/NEXTAUTH_SECRET=nextauth-secret-change-me  # CHANGEME/NEXTAUTH_SECRET=${NEXTAUTH_SECRET}/" .env
  
  # Remove backup file
  rm .env.bak
  
  echo "Secrets generated successfully."
else
  echo ".env file already exists, using existing configuration."
fi

# Start the stack
echo "Starting Langfuse stack..."
docker compose up -d

echo ""
echo "Langfuse is starting at http://localhost:6543"
echo ""
echo "It may take a minute for all services to be ready."
echo "Check status with: docker compose ps"
echo "View logs with: docker compose logs -f"
