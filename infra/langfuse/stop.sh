#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Stopping Langfuse stack..."
docker compose down

echo "Langfuse stack stopped."
