#!/bin/bash

# Stop vLLM Docker container for Qwen3-Next-80B-A3B-Instruct

echo "Stopping vLLM Docker container for Qwen3-Next-80B-A3B-Instruct..."

docker compose -f docker-compose.qwen3-next-80b-instruct.yml down

if [ $? -eq 0 ]; then
    echo "✓ Container stopped successfully"
else
    echo "✗ Failed to stop container"
    echo "You can force stop with: docker compose -f docker-compose.qwen3-next-80b-instruct.yml down --force"
fi