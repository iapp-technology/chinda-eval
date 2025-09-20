#!/bin/bash

# Simple test script for a single Thai benchmark using vLLM API
# Usage: ./test_single_benchmark.sh <benchmark-name>

# Configuration
VLLM_SERVER_URL="http://localhost:8801/v1/chat/completions"
MODEL_NAME="gpt-oss-20b"
BASE_OUTPUT_DIR="test_output_api"
CONDA_ENV="chinda-eval"

# Check if benchmark name is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <benchmark-name>"
    echo "Available benchmarks: aime24-th, hellaswag-th, humaneval-th, ifeval-th, math_500-th"
    exit 1
fi

BENCHMARK=$1
OUTPUT_DIR="${BASE_OUTPUT_DIR}/${MODEL_NAME}/${BENCHMARK}"

echo "Testing benchmark: $BENCHMARK"
echo "vLLM Server: $VLLM_SERVER_URL"
echo "Model: $MODEL_NAME"
echo "Output directory: $OUTPUT_DIR"

# Check if vLLM server is running
echo "Checking vLLM server..."
if curl -s http://localhost:8801/v1/models | grep -q "gpt-oss-20b"; then
    echo "✓ vLLM server is running and model is loaded"
else
    echo "✗ vLLM server is not running or model not loaded!"
    echo "Please start the server first with: ./start_vllm_docker.sh"
    exit 1
fi

# Activate conda environment
source /home/saiuser/miniconda3/etc/profile.d/conda.sh
conda activate $CONDA_ENV

# Create output directory
mkdir -p $OUTPUT_DIR

# Run the benchmark using vLLM API
echo "Running evalscope with vLLM API..."
evalscope eval \
    --model $MODEL_NAME \
    --api-url $VLLM_SERVER_URL \
    --api-key EMPTY \
    --eval-type openai_api \
    --datasets $BENCHMARK \
    --dataset-hub huggingface \
    --work-dir $OUTPUT_DIR \
    --generation-config '{"do_sample": false, "temperature": 0.0, "max_new_tokens": 16384}' \
    --timeout 300 \
    --limit 10

echo "Test completed. Check $OUTPUT_DIR for results."