#!/bin/bash

# Stop vLLM Docker container

echo "Stopping vLLM Docker container..."

docker compose -f dockers/docker-compose.gpt-oss-20b.yml down

if [ $? -eq 0 ]; then
    echo "✓ Container stopped successfully"
else
    echo "✗ Failed to stop container"
    echo "You can force stop with: docker compose -f dockers/docker-compose.gpt-oss-20b.yml down --force"
fi