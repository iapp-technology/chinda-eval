#!/bin/bash

# Start vLLM server using Docker for Qwen3-Next-80B-A3B-Thinking

echo "Starting vLLM server for Qwen3-Next-80B-A3B-Thinking using Docker..."
echo "Model: /mnt/disk3/Qwen_Qwen3-Next-80B-A3B-Thinking"
echo "Port: 8881"
echo "GPUs: 4,5,6,7"

# Start the Docker container
docker compose -f docker-compose.qwen3-next-80b-thinking.yml up -d

# Check if Docker command was successful
if [ $? -ne 0 ]; then
    echo "✗ Failed to start Docker container"
    echo "Make sure Docker is installed and you have permissions to run it"
    exit 1
fi

echo "Container starting..."
echo "Waiting for server to be ready..."

# Wait for server to be ready (check health endpoint)
for i in {1..60}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8881/v1/models 2>/dev/null | grep -q "200"; then
        echo ""
        echo "✓ Server is ready!"
        echo ""
        echo "Server is running on http://localhost:8881"
        echo "To view logs: docker compose -f docker-compose.qwen3-next-80b-thinking.yml logs -f"
        echo "To stop server: ./stop_qwen3_next_80b_thinking_vllm_docker.sh"
        exit 0
    fi
    echo -n "."
    sleep 2
done

echo ""
echo "✗ Server failed to start within 120 seconds"
echo "Check logs with: docker compose -f docker-compose.qwen3-next-80b-thinking.yml logs"
exit 1