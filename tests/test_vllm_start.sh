#!/bin/bash

# Test script to verify vLLM server can start with a model

MODEL_KEY="gpt-oss-20b"
MODEL_PATH="/mnt/disk3/openai_gpt-oss-20b"
TENSOR_PARALLEL=4
GPU_MEMORY=0.95
MAX_LEN=16384
VLLM_PORT=8801

echo "Testing vLLM server startup for $MODEL_KEY"
echo "Model path: $MODEL_PATH"
echo "Tensor parallel: $TENSOR_PARALLEL"

# Generate device IDs list
device_ids=""
for ((i=0; i<TENSOR_PARALLEL; i++)); do
    if [ -n "$device_ids" ]; then
        device_ids="${device_ids}, '${i}'"
    else
        device_ids="'${i}'"
    fi
done

echo "Device IDs: [$device_ids]"

# Create docker-compose file
cat > /tmp/docker-compose-test-vllm.yml <<EOF
version: '3.8'

services:
  vllm-server-test:
    image: vllm/vllm-openai:latest
    shm_size: 100g
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: [${device_ids}]
              capabilities: [gpu]
    volumes:
      - ${MODEL_PATH}:/models
    ports:
      - "${VLLM_PORT}:8000"
    environment:
      - NCCL_IGNORE_DISABLED_P2P=1
      - VLLM_ATTENTION_BACKEND=TRITON_ATTN_VLLM_V1
      - VLLM_USE_MODELSCOPE=true
    healthcheck:
      test: [ "CMD", "curl", "-f", "http://0.0.0.0:8000/v1/models" ]
      interval: 30s
      timeout: 5s
      retries: 20
    command:
      - --model=/models
      - --tensor-parallel-size=${TENSOR_PARALLEL}
      - --served-model-name=${MODEL_KEY}
      - --trust-remote-code
      - --max-model-len=${MAX_LEN}
      - --dtype=auto
      - --gpu-memory-utilization=${GPU_MEMORY}
      - --max-num-seqs=256
      - --max-num-batched-tokens=32768
      - --enable-chunked-prefill
    restart: unless-stopped
EOF

echo ""
echo "Docker Compose file created at /tmp/docker-compose-test-vllm.yml"
echo ""
echo "Validating Docker Compose file..."
docker compose -f /tmp/docker-compose-test-vllm.yml config > /dev/null 2>&1 && echo "✓ Valid" || echo "✗ Invalid"

echo ""
echo "To start the server, run:"
echo "  docker compose -f /tmp/docker-compose-test-vllm.yml up -d"
echo ""
echo "To stop the server, run:"
echo "  docker compose -f /tmp/docker-compose-test-vllm.yml down"