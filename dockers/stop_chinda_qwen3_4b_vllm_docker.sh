#!/bin/bash

# Stop vLLM Docker container

echo "Stopping vLLM Docker container for chinda-qwen3-4b..."

docker compose -f docker-compose.chinda-qwen3-4b.yml down

if [ $? -eq 0 ]; then
    echo "✓ Container stopped successfully"
else
    echo "✗ Failed to stop container"
    echo "You can force stop with: docker compose -f docker-compose.chinda-qwen3-4b.yml down --force"
fi