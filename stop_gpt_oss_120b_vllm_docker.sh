#!/bin/bash

# Stop vLLM Docker container for GPT-OSS-120B

echo "Stopping vLLM Docker container for GPT-OSS-120B..."

docker compose -f docker-compose.gpt-oss-120b.yml down

if [ $? -eq 0 ]; then
    echo "✓ Container stopped successfully"
else
    echo "✗ Failed to stop container"
    echo "You can force stop with: docker compose -f docker-compose.gpt-oss-120b.yml down --force"
fi