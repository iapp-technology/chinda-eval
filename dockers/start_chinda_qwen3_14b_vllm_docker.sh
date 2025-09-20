#!/bin/bash

# Start vLLM server using Docker for chinda-qwen3-14b

echo "Starting vLLM server for chinda-qwen3-14b using Docker..."
echo "Model: /home/saiuser/disk6/ms-swift-merged/chinda-qwen3-14b-1-2-20250528-20_00-dpo"
echo "Port: 8801"
echo "GPUs: 0,1,2,3"

# Start the Docker container
docker compose -f dockers/docker-compose.chinda-qwen3-14b.yml up -d

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
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8801/v1/models 2>/dev/null | grep -q "200"; then
        echo ""
        echo "✓ Server is ready!"
        echo ""
        echo "Server is running on http://localhost:8801"
        echo "To view logs: docker compose -f dockers/docker-compose.chinda-qwen3-14b.yml logs -f"
        echo "To stop server: ./stop_chinda_qwen3_14b_vllm_docker.sh"
        exit 0
    fi
    echo -n "."
    sleep 2
done

echo ""
echo "✗ Server failed to start within 120 seconds"
echo "Check logs with: docker compose -f dockers/docker-compose.chinda-qwen3-14b.yml logs"
exit 1