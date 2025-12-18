#!/bin/bash

# Test Script for Qwen3-8B Base and ThaiLLM-8B-SFT Models
# This script evaluates both models on all benchmarks
#
# Usage:
#   ./test_base_models.sh                    # Test all models
#   ./test_base_models.sh Qwen-Qwen3-8B      # Test only Qwen3-8B
#   ./test_base_models.sh ThaiLLM-8B-SFT     # Test only ThaiLLM-8B-SFT
#   ./test_base_models.sh Qwen-Qwen3-8B ThaiLLM-8B-SFT  # Test both (explicit)

# Configuration
VLLM_PORT=8801
VLLM_SERVER_URL="http://localhost:${VLLM_PORT}/v1/chat/completions"
BASE_OUTPUT_DIR="outputs"
CONDA_ENV="chinda-eval"
MAX_PARALLEL=12
EVAL_BATCH_SIZE=8
DEFAULT_MAX_SAMPLES=1500

# Hardware Configuration
CUDA_DEVICES="0,1,2,3,4,5,6,7"
TENSOR_PARALLEL_SIZE=8

# Per-benchmark sample limits
declare -A BENCHMARK_LIMITS
BENCHMARK_LIMITS["code_switching"]=500
BENCHMARK_LIMITS["live_code_bench"]=200
BENCHMARK_LIMITS["live_code_bench-th"]=200
BENCHMARK_LIMITS["math_500"]=500
BENCHMARK_LIMITS["math_500-th"]=500
BENCHMARK_LIMITS["ifeval"]=500
BENCHMARK_LIMITS["ifeval-th"]=500

# Model paths mapping (model_key -> model_path)
declare -A MODEL_PATHS
MODEL_PATHS["Qwen-Qwen3-8B"]="/mnt/disk3/Qwen_Qwen3-8B"
MODEL_PATHS["ThaiLLM-8B-SFT"]="/mnt/disk3/ThaiLLM_ThaiLLM-8B-SFT"
MODEL_PATHS["typhoon-s-8b-instruct"]="/home/siamai/kunato_typhoon-s-8b-instruct-research-preview"
MODEL_PATHS["THaLLE-0.2-ThaiLLM-8B"]="/home/siamai/KBTG-Labs_THaLLE-0.2-ThaiLLM-8B-fa-rc1"

# Model docker image mapping (model_key -> docker_image)
# Use pinned version for models that have issues with latest
declare -A MODEL_IMAGES
MODEL_IMAGES["Qwen-Qwen3-8B"]="vllm/vllm-openai:latest"
MODEL_IMAGES["ThaiLLM-8B-SFT"]="vllm/vllm-openai:v0.9.2"
MODEL_IMAGES["typhoon-s-8b-instruct"]="vllm/vllm-openai:v0.12.0"
MODEL_IMAGES["THaLLE-0.2-ThaiLLM-8B"]="vllm/vllm-openai:v0.12.0"
DEFAULT_VLLM_IMAGE="vllm/vllm-openai:latest"

# Available models
ALL_MODELS=(
    # "Qwen-Qwen3-8B"
    # "ThaiLLM-8B-SFT"
    "typhoon-s-8b-instruct"
    "THaLLE-0.2-ThaiLLM-8B"
)

# Models to test (from arguments or all)
if [ $# -gt 0 ]; then
    MODEL_ORDER=("$@")
    # Validate provided models
    for model in "${MODEL_ORDER[@]}"; do
        valid=false
        for available in "${ALL_MODELS[@]}"; do
            if [ "$model" = "$available" ]; then
                valid=true
                break
            fi
        done
        if [ "$valid" = false ]; then
            echo "ERROR: Unknown model '$model'"
            echo "Available models: ${ALL_MODELS[*]}"
            exit 1
        fi
    done
else
    MODEL_ORDER=("${ALL_MODELS[@]}")
fi

# Track failed and successful models
declare -a FAILED_MODELS=()
declare -a SUCCESS_MODELS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
print_error() { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"; }
print_warning() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"; }
print_info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"; }
print_model() { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] MODEL:${NC} $1"; }

# Function to stop any running vLLM servers
stop_vllm_server() {
    print_info "Stopping any existing vLLM servers..."
    docker ps --format "{{.Names}}" | grep -E "vllm-server" | while read container_name; do
        docker stop "$container_name" 2>/dev/null
    done
    lsof -ti:${VLLM_PORT} | xargs -r kill -9 2>/dev/null
    sleep 2
}

# Function to generate Docker Compose file for vLLM (same as v4 script)
generate_docker_compose() {
    local model_path="$1"
    local model_name="$2"
    local gpu_ids="$3"  # e.g., "0,1,2,3,4,5,6,7"
    local compose_file="$4"
    local tp_size="$5"
    local docker_image="$6"

    # Convert comma-separated GPU IDs to JSON array format
    local gpu_array=$(echo "$gpu_ids" | sed "s/,/', '/g" | sed "s/^/'/" | sed "s/$/'/")

    cat > "$compose_file" << EOF
version: '3.8'

services:
  vllm-server-${model_name}:
    image: ${docker_image}
    shm_size: 250g
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: [${gpu_array}]
              capabilities: [gpu]
    volumes:
      - ${model_path}:/models
    ports:
      - "${VLLM_PORT}:8000"
    environment:
      - NCCL_IGNORE_DISABLED_P2P=1
      - VLLM_USE_V1=0
    healthcheck:
      test: [ "CMD", "curl", "-f", "http://0.0.0.0:8000/v1/models" ]
      interval: 30s
      timeout: 5s
      retries: 20
    command:
      - --model=/models
      - --tensor-parallel-size=${tp_size}
      - --served-model-name=${model_name}
      - --trust-remote-code
      - --max-model-len=32768
      - --gpu-memory-utilization=0.90
      - --enforce-eager
    restart: unless-stopped
EOF
    print_info "Generated docker-compose file: $compose_file"
}

# Function to start vLLM server for a specific model
start_vllm_server() {
    local model_key=$1
    print_model "Starting vLLM server for $model_key"

    # Get model path from mapping
    local model_path="${MODEL_PATHS[$model_key]}"
    if [[ -z "$model_path" ]]; then
        print_error "Model path not found for: $model_key"
        return 1
    fi

    if [[ ! -d "$model_path" ]]; then
        print_error "Model directory not found: $model_path"
        return 1
    fi

    # Get docker image for this model (use default if not specified)
    local docker_image="${MODEL_IMAGES[$model_key]:-$DEFAULT_VLLM_IMAGE}"
    print_info "Using docker image: $docker_image"

    # Generate docker-compose file dynamically
    local compose_file="/tmp/docker-compose-${model_key}.yml"
    generate_docker_compose "$model_path" "$model_key" "$CUDA_DEVICES" "$compose_file" "$TENSOR_PARALLEL_SIZE" "$docker_image"

    # Stop any existing container first
    docker compose -f "$compose_file" down --remove-orphans 2>/dev/null
    sleep 2

    docker compose -f "$compose_file" up -d --remove-orphans

    if [ $? -ne 0 ]; then
        print_error "Failed to start Docker container for $model_key"
        return 1
    fi

    print_info "Waiting for vLLM server to be ready..."
    local max_wait=600
    local waited=0
    local check_interval=10

    while [ $waited -lt $max_wait ]; do
        # Check if container is still running
        if ! docker compose -f "$compose_file" ps --status running 2>/dev/null | grep -q "vllm-server"; then
            print_error "Container for $model_key crashed or stopped"
            print_info "Container logs:"
            docker compose -f "$compose_file" logs --tail=50
            return 1
        fi

        # Check if server is responding
        if curl -s http://localhost:${VLLM_PORT}/v1/models 2>/dev/null | grep -q "$model_key"; then
            print_message "✓ vLLM server for $model_key is ready!"
            return 0
        fi
        echo -n "."
        sleep $check_interval
        waited=$((waited + check_interval))
    done

    print_error "Server failed to start within ${max_wait} seconds"
    print_info "Container logs:"
    docker compose -f "$compose_file" logs --tail=100
    return 1
}

# Function to stop vLLM server for a specific model
stop_vllm_docker() {
    local model_key=$1
    print_info "Stopping vLLM server for $model_key..."
    local compose_file="/tmp/docker-compose-${model_key}.yml"
    if [[ -f "$compose_file" ]]; then
        docker compose -f "$compose_file" down --remove-orphans
        rm -f "$compose_file"
    fi
}

# List of benchmarks
THAI_BENCHMARKS=(
    "aime24-th"
    "hellaswag-th"
    "ifeval-th"
    "math_500-th"
    "code_switching"
    "live_code_bench-th"
    "openthaieval"
)

ENGLISH_BENCHMARKS=(
    "aime24"
    "hellaswag"
    "ifeval"
    "math_500"
    "live_code_bench"
)

ALL_BENCHMARKS=("${THAI_BENCHMARKS[@]}" "${ENGLISH_BENCHMARKS[@]}")

# Function to run a single benchmark
run_benchmark() {
    local benchmark=$1
    local model_name=$2
    local output_dir="${BASE_OUTPUT_DIR}/${model_name}/${benchmark}"

    # Check if already completed
    if [[ -d "$output_dir" ]] && find "$output_dir" -name "*.json" -type f | grep -q .; then
        print_warning "Benchmark $benchmark already completed for $model_name, skipping..."
        return 0
    fi

    mkdir -p "$output_dir"

    # Get sample limit
    local max_samples=${BENCHMARK_LIMITS[$benchmark]:-$DEFAULT_MAX_SAMPLES}

    print_info "Running $benchmark (max $max_samples samples) for $model_name"

    # Use evalscope for benchmark evaluation
    evalscope eval \
        --model "$model_name" \
        --api-url "$VLLM_SERVER_URL" \
        --api-key EMPTY \
        --eval-type openai_api \
        --datasets "$benchmark" \
        --dataset-hub huggingface \
        --work-dir "$output_dir" \
        --eval-batch-size $EVAL_BATCH_SIZE \
        --generation-config '{"do_sample": false, "temperature": 0.0, "max_new_tokens": 32768}' \
        --timeout 60000 \
        --limit "$max_samples" \
        > "${output_dir}/output.log" 2>&1

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        print_message "✓ Completed $benchmark for $model_name"
    else
        print_error "✗ Failed $benchmark for $model_name (exit code: $exit_code)"
        tail -20 "${output_dir}/output.log"
    fi

    return $exit_code
}

# Function to run all benchmarks for a model in parallel
run_all_benchmarks_parallel() {
    local model_name=$1
    local pids=()
    local benchmark_names=()

    print_model "Running all benchmarks for $model_name in parallel (max $MAX_PARALLEL concurrent)"

    for benchmark in "${ALL_BENCHMARKS[@]}"; do
        # Wait if we've reached max parallel
        while [ ${#pids[@]} -ge $MAX_PARALLEL ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    wait "${pids[$i]}"
                    unset 'pids[$i]'
                    unset 'benchmark_names[$i]'
                fi
            done
            pids=("${pids[@]}")
            benchmark_names=("${benchmark_names[@]}")
            sleep 1
        done

        # Start benchmark in background
        run_benchmark "$benchmark" "$model_name" &
        pids+=($!)
        benchmark_names+=("$benchmark")
    done

    # Wait for all remaining benchmarks
    print_info "Waiting for remaining benchmarks to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    print_message "✓ All benchmarks completed for $model_name"
}

# Main execution
main() {
    print_message "=========================================="
    print_message "Testing Base Models"
    print_message "=========================================="

    # Ensure output directory exists
    mkdir -p "$BASE_OUTPUT_DIR"

    # Activate conda environment
    source /home/siamai/miniconda3/bin/activate ${CONDA_ENV}

    for model_key in "${MODEL_ORDER[@]}"; do
        print_message "=========================================="
        print_model "Processing model: $model_key"
        print_message "=========================================="

        # Stop any existing servers
        stop_vllm_server

        # Start server for this model
        if ! start_vllm_server "$model_key"; then
            print_error "Failed to start server for $model_key, skipping..."
            FAILED_MODELS+=("$model_key")
            continue
        fi

        # Run benchmarks
        run_all_benchmarks_parallel "$model_key"

        # Stop server
        stop_vllm_docker "$model_key"

        SUCCESS_MODELS+=("$model_key")
        print_message "Completed all benchmarks for $model_key"
    done

    print_message "=========================================="
    if [ ${#FAILED_MODELS[@]} -eq 0 ]; then
        print_message "All models evaluated successfully!"
    else
        print_warning "Evaluation completed with some failures"
        print_message "Successful models: ${SUCCESS_MODELS[*]:-none}"
        print_error "Failed models: ${FAILED_MODELS[*]}"
    fi
    print_message "=========================================="

    # Print summary
    print_info "Results saved to: $BASE_OUTPUT_DIR/"
    for model_key in "${SUCCESS_MODELS[@]}"; do
        echo "  - ${model_key}: $BASE_OUTPUT_DIR/${model_key}/"
    done

    # Return non-zero if any models failed
    if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

# Run main function
main "$@"
