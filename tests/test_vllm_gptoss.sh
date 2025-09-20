#!/bin/bash

# Test script for GPT-OSS-20B vLLM server startup

echo "Testing vLLM server for GPT-OSS-20B"
echo "======================================"

# Stop any existing containers
echo "Stopping existing vLLM containers..."
docker ps -q --filter "name=vllm" | xargs -r docker stop
docker ps -aq --filter "name=vllm" | xargs -r docker rm

# Start using dockers/docker-compose.gptoss20b.yml
echo ""
echo "Starting vLLM server using docker-compose..."
docker compose -f dockers/docker-compose.gptoss20b.yml up -d

if [ $? -ne 0 ]; then
    echo "Failed to start Docker container"
    exit 1
fi

# Wait for server to be ready
echo "Waiting for server to be ready..."
max_wait=180
waited=0

while [ $waited -lt $max_wait ]; do
    if curl -s http://localhost:8801/v1/models 2>/dev/null | grep -q "gpt-oss-20b"; then
        echo ""
        echo "✓ vLLM server is ready!"
        echo ""
        curl -s http://localhost:8801/v1/models | python3 -m json.tool
        echo ""
        echo "Server is running at http://localhost:8801"
        echo "To stop: docker compose -f dockers/docker-compose.gptoss20b.yml down"
        exit 0
    fi
    echo -n "."
    sleep 5
    waited=$((waited + 5))
done

echo ""
echo "✗ Server failed to start within ${max_wait} seconds"
echo "Check logs with: docker compose -f dockers/docker-compose.gptoss20b.yml logs"
exit 1