#!/bin/bash

# Stop vLLM Docker container for Qwen3-Next-80B-A3B-Thinking

echo "Stopping vLLM Docker container for Qwen3-Next-80B-A3B-Thinking..."

docker compose -f docker-compose.qwen3-next-80b-thinking.yml down

if [ $? -eq 0 ]; then
    echo "✓ Container stopped successfully"
else
    echo "✗ Failed to stop container"
    echo "You can force stop with: docker compose -f docker-compose.qwen3-next-80b-thinking.yml down --force"
fi