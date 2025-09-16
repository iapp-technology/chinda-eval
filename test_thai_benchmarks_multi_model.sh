#!/bin/bash

# Multi-Model Parallel Benchmarks Evaluation Script
# Automatically manages vLLM servers and evaluates multiple models in sequence

# Configuration
VLLM_PORT=8801
VLLM_SERVER_URL="http://localhost:${VLLM_PORT}/v1/chat/completions"
BASE_OUTPUT_DIR="thai_benchmark_results_api"
CONDA_ENV="chinda-eval"
MAX_PARALLEL=20  # Limit concurrent benchmarks
MAX_SAMPLES=10 # Maximum samples per benchmark (covers all datasets)

# Parse command line arguments
MODEL_ORDER=()
BENCHMARKS_TO_RUN=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --models)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                MODEL_ORDER+=("$1")
                shift
            done
            ;;
        --benchmarks)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
                BENCHMARKS_TO_RUN+=("$1")
                shift
            done
            ;;
        --limit)
            MAX_SAMPLES="$2"
            shift 2
            ;;
        *)
            # Legacy support for single model as first argument
            if [ ${#MODEL_ORDER[@]} -eq 0 ] && [ -z "$1" ] || [[ ! "$1" =~ ^-- ]]; then
                MODEL_ORDER=("$1")
            fi
            shift
            ;;
    esac
done

# Default models if none specified
if [ ${#MODEL_ORDER[@]} -eq 0 ]; then
    MODEL_ORDER=(
        "gpt-oss-20b"
        "gpt-oss-120b"
        "qwen3-next-80b-instruct"
        "qwen3-next-80b-thinking"
    )
fi

# Model configurations
declare -A MODELS
declare -A MODEL_TENSOR_PARALLEL
declare -A MODEL_SERVED_NAMES
declare -A MODEL_GPU_MEMORY
declare -A MODEL_MAX_LEN
declare -A MODEL_DOCKER_IMAGE

# Model 1: GPT-OSS-20B
MODELS["gpt-oss-20b"]="/mnt/disk3/openai_gpt-oss-20b"
MODEL_TENSOR_PARALLEL["gpt-oss-20b"]=8
MODEL_SERVED_NAMES["gpt-oss-20b"]="gpt-oss-20b"
MODEL_GPU_MEMORY["gpt-oss-20b"]=0.95
MODEL_MAX_LEN["gpt-oss-20b"]=8192
MODEL_DOCKER_IMAGE["gpt-oss-20b"]="vllm/vllm-openai:gptoss"

# Model 2: GPT-OSS-120B
MODELS["gpt-oss-120b"]="/mnt/disk3/openai_gpt-oss-120b"
MODEL_TENSOR_PARALLEL["gpt-oss-120b"]=8
MODEL_SERVED_NAMES["gpt-oss-120b"]="gpt-oss-120b"
MODEL_GPU_MEMORY["gpt-oss-120b"]=0.95
MODEL_MAX_LEN["gpt-oss-120b"]=8192
MODEL_DOCKER_IMAGE["gpt-oss-120b"]="vllm/vllm-openai:gptoss"

# Model 3: Qwen3-Next-80B-A3B-Instruct
MODELS["qwen3-next-80b-instruct"]="/mnt/disk3/Qwen_Qwen3-Next-80B-A3B-Instruct"
MODEL_TENSOR_PARALLEL["qwen3-next-80b-instruct"]=8
MODEL_SERVED_NAMES["qwen3-next-80b-instruct"]="qwen3-next-80b-instruct"
MODEL_GPU_MEMORY["qwen3-next-80b-instruct"]=0.95
MODEL_MAX_LEN["qwen3-next-80b-instruct"]=8192
MODEL_DOCKER_IMAGE["qwen3-next-80b-instruct"]="vllm/vllm-openai:nightly"

# Model 4: Qwen3-Next-80B-A3B-Thinking
MODELS["qwen3-next-80b-thinking"]="/mnt/disk3/Qwen_Qwen3-Next-80B-A3B-Thinking"
MODEL_TENSOR_PARALLEL["qwen3-next-80b-thinking"]=8
MODEL_SERVED_NAMES["qwen3-next-80b-thinking"]="qwen3-next-80b-thinking"
MODEL_GPU_MEMORY["qwen3-next-80b-thinking"]=0.95
MODEL_MAX_LEN["qwen3-next-80b-thinking"]=8192
MODEL_DOCKER_IMAGE["qwen3-next-80b-thinking"]="vllm/vllm-openai:nightly"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

print_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

print_model() {
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] MODEL:${NC} $1"
}

# Function to stop any running vLLM servers
stop_vllm_server() {
    print_info "Stopping any existing vLLM servers..."

    # Stop any docker compose services
    for compose_file in /tmp/docker-compose-*.yml; do
        if [[ -f "$compose_file" ]]; then
            docker compose -f "$compose_file" down --remove-orphans 2>/dev/null
            rm -f "$compose_file"
        fi
    done

    # Clean up any stale containers with tmp-vllm-server prefix
    docker ps -a | grep 'tmp-vllm-server' | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null

    # Try Docker first
    docker ps -q --filter "name=vllm" | xargs -r docker stop 2>/dev/null

    # Kill processes on the port
    lsof -ti:${VLLM_PORT} | xargs -r kill -9 2>/dev/null

    # Wait a moment for cleanup
    sleep 2
}

# Function to start vLLM server for a specific model
start_vllm_server() {
    local model_key=$1
    local model_path=${MODELS[$model_key]}
    local tensor_parallel=${MODEL_TENSOR_PARALLEL[$model_key]}
    local served_name=${MODEL_SERVED_NAMES[$model_key]}
    local gpu_memory=${MODEL_GPU_MEMORY[$model_key]}
    local max_len=${MODEL_MAX_LEN[$model_key]}
    local docker_image=${MODEL_DOCKER_IMAGE[$model_key]}

    print_model "Starting vLLM server for $model_key"
    print_info "Model path: $model_path"
    print_info "Docker image: $docker_image"
    print_info "Tensor parallel: $tensor_parallel"
    print_info "Max length: $max_len"
    print_info "GPU memory: $gpu_memory"

    # Generate device IDs list based on tensor_parallel
    device_ids=""
    for ((i=0; i<tensor_parallel; i++)); do
        if [ -n "$device_ids" ]; then
            device_ids="${device_ids}, '${i}'"
        else
            device_ids="'${i}'"
        fi
    done

    # Check if this is a Qwen3-Next model that needs special configuration
    extra_args=""
    extra_env=""
    if [[ "$model_key" == *"qwen3-next"* ]]; then
        # Add MTP (Multi-Token Prediction) for better performance and disable chunked prefill
        extra_args='      - --no-enable-chunked-prefill
      - --tokenizer-mode=auto'
        # Add environment variable to handle thinking blocks
        extra_env='      - VLLM_ALLOW_THINKING=true'
    fi

    # Create temporary docker-compose file for this model
    cat > /tmp/docker-compose-${model_key}.yml <<EOF
version: '3.8'

services:
  vllm-server-${model_key}:
    image: ${docker_image}
    shm_size: 100g
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: [${device_ids}]
              capabilities: [gpu]
    volumes:
      - ${model_path}:/models
    ports:
      - "${VLLM_PORT}:8000"
    environment:
      - NCCL_IGNORE_DISABLED_P2P=1
      - VLLM_ATTENTION_BACKEND=TRITON_ATTN_VLLM_V1
      - VLLM_USE_MODELSCOPE=true
${extra_env}
    healthcheck:
      test: [ "CMD", "curl", "-f", "http://0.0.0.0:8000/v1/models" ]
      interval: 30s
      timeout: 5s
      retries: 20
    command:
      - --model=/models
      - --tensor-parallel-size=${tensor_parallel}
      - --served-model-name=${served_name}
      - --trust-remote-code
      - --max-model-len=${max_len}
      - --dtype=auto
      - --gpu-memory-utilization=${gpu_memory}
      - --max-num-seqs=256
      - --max-num-batched-tokens=32768
      - --enable-chunked-prefill
${extra_args}
    restart: unless-stopped
EOF

    # Start the Docker container with orphan removal
    docker compose -f /tmp/docker-compose-${model_key}.yml up -d --remove-orphans

    if [ $? -ne 0 ]; then
        print_error "Failed to start Docker container for $model_key"
        return 1
    fi

    # Wait for server to be ready
    print_info "Waiting for vLLM server to be ready (this may take several minutes for large models)..."
    local max_wait=300  # Increased to 5 minutes for larger models
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if curl -s http://localhost:${VLLM_PORT}/v1/models 2>/dev/null | grep -q "$served_name"; then
            print_message "✓ vLLM server for $model_key is ready!"
            return 0
        fi
        echo -n "."
        sleep 10  # Check every 10 seconds
        waited=$((waited + 10))
    done

    print_error "Server failed to start within ${max_wait} seconds"
    docker compose -f /tmp/docker-compose-${model_key}.yml logs
    return 1
}

# Function to stop vLLM server for a specific model
stop_vllm_docker() {
    local model_key=$1
    print_info "Stopping vLLM server for $model_key..."
    if [[ -f "/tmp/docker-compose-${model_key}.yml" ]]; then
        docker compose -f /tmp/docker-compose-${model_key}.yml down --remove-orphans
        rm -f /tmp/docker-compose-${model_key}.yml
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

# Combine all benchmarks
ALL_BENCHMARKS=("${THAI_BENCHMARKS[@]}" "${ENGLISH_BENCHMARKS[@]}")

# Use specified benchmarks or default to all
if [ ${#BENCHMARKS_TO_RUN[@]} -eq 0 ]; then
    BENCHMARKS=("${ALL_BENCHMARKS[@]}")
else
    BENCHMARKS=("${BENCHMARKS_TO_RUN[@]}")
fi

# Function to run a single benchmark
run_benchmark() {
    local benchmark=$1
    local model_name=$2
    local bench_output_dir="$BASE_OUTPUT_DIR/${model_name}/${benchmark}"
    mkdir -p "$bench_output_dir"

    local start_time=$(date +%s)

    print_info "[BENCHMARK: $benchmark] Starting for model: $model_name..."

    # Run evalscope command
    evalscope eval \
        --model $model_name \
        --api-url $VLLM_SERVER_URL \
        --api-key EMPTY \
        --eval-type openai_api \
        --datasets $benchmark \
        --dataset-hub huggingface \
        --work-dir "$bench_output_dir" \
        --generation-config '{"do_sample": false, "temperature": 0.0, "max_new_tokens": 16384}' \
        --timeout 300 \
        --limit $MAX_SAMPLES > "$bench_output_dir/output.log" 2>&1

    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 0 ]; then
        print_message "[BENCHMARK: $benchmark] ✓ Completed successfully in ${duration}s"
        echo "SUCCESS" > "$bench_output_dir/status.txt"
        echo "$duration" > "$bench_output_dir/duration.txt"
    else
        print_error "[BENCHMARK: $benchmark] ✗ Failed after ${duration}s"
        echo "FAILED" > "$bench_output_dir/status.txt"
        echo "$duration" > "$bench_output_dir/duration.txt"
        tail -10 "$bench_output_dir/output.log"
    fi
}

# Function to extract score from benchmark results
extract_score() {
    local benchmark=$1
    local model_name=$2
    local bench_dir="$BASE_OUTPUT_DIR/$model_name/$benchmark"

    # Look for the latest report JSON file
    local report_file=""
    if [ -d "$bench_dir" ]; then
        report_file=$(find "$bench_dir" -name "*.json" -path "*/reports/*" 2>/dev/null | head -1)
    fi

    if [ -f "$report_file" ]; then
        case "$benchmark" in
            "code_switching")
                python3 -c "
import json
data = json.load(open('$report_file'))
for metric in data.get('metrics', []):
    if 'language_accuracy' in metric.get('name', ''):
        print(metric.get('score', 'N/A'))
        exit()
print(data.get('score', 'N/A'))
" 2>/dev/null || echo "N/A"
                ;;
            "ifeval-th"|"ifeval")
                python3 -c "
import json
data = json.load(open('$report_file'))
for metric in data.get('metrics', []):
    if 'inst_level_loose' in metric.get('name', ''):
        # Try to get the actual score from subsets if main score is 0
        if metric.get('score', 0) == 0 and metric.get('categories'):
            for cat in metric['categories']:
                if cat.get('subsets'):
                    for subset in cat['subsets']:
                        if subset.get('score', 0) != 0:
                            print(subset['score'])
                            exit()
        print(metric.get('score', 'N/A'))
        exit()
print(data.get('score', 'N/A'))
" 2>/dev/null || echo "N/A"
                ;;
            "live_code_bench"|"live_code_bench-th")
                python3 -c "
import json
data = json.load(open('$report_file'))
for metric in data.get('metrics', []):
    if 'exact_match' in metric.get('name', '') or 'pass@1' in metric.get('name', '') or 'pass' in metric.get('name', ''):
        print(metric.get('score', 'N/A'))
        exit()
print(data.get('score', 'N/A'))
" 2>/dev/null || echo "N/A"
                ;;
            *)
                python3 -c "
import json
data = json.load(open('$report_file'))
for metric in data.get('metrics', []):
    if 'mean_acc' in metric.get('name', '') or 'accuracy' in metric.get('name', ''):
        print(metric.get('score', 'N/A'))
        exit()
print(data.get('score', 'N/A'))
" 2>/dev/null || echo "N/A"
                ;;
        esac
    else
        echo "N/A"
    fi
}

# Function to generate score summary CSV for a model
generate_score_summary() {
    local model_name=$1
    local output_dir="$BASE_OUTPUT_DIR/$model_name"

    print_message "Generating score summary CSV for $model_name..."

    {
        echo "Benchmarks,$model_name"

        score=$(extract_score "aime24" "$model_name")
        echo "AIME24,$score"

        score=$(extract_score "aime24-th" "$model_name")
        echo "AIME24-TH,$score"

        score=$(extract_score "code_switching" "$model_name")
        echo "Language Accuracy (Code Switching),$score"

        score=$(extract_score "live_code_bench" "$model_name")
        echo "LiveCodeBench,$score"

        score=$(extract_score "live_code_bench-th" "$model_name")
        echo "LiveCodeBench-TH,$score"

        score=$(extract_score "math_500" "$model_name")
        echo "MATH500,$score"

        score=$(extract_score "math_500-th" "$model_name")
        echo "MATH500-TH,$score"

        score=$(extract_score "openthaieval" "$model_name")
        echo "OpenThaiEval,$score"

        score=$(extract_score "hellaswag" "$model_name")
        echo "HellaSwag,$score"

        score=$(extract_score "hellaswag-th" "$model_name")
        echo "HellaSwag-TH,$score"

        score=$(extract_score "ifeval" "$model_name")
        echo "IFEval (inst_level_loose_acc),$score"

        score=$(extract_score "ifeval-th" "$model_name")
        echo "IFEval-TH (inst_level_loose_acc),$score"
    } > "$output_dir/score_summary.csv.tmp"

    # Calculate average
    avg=$(python3 -c "
scores = []
with open('$output_dir/score_summary.csv.tmp', 'r') as f:
    lines = f.readlines()[1:]
    for line in lines:
        parts = line.strip().split(',')
        if len(parts) == 2 and parts[1] != 'N/A':
            try:
                scores.append(float(parts[1]))
            except:
                pass
if scores:
    print(sum(scores) / len(scores))
else:
    print('N/A')
" 2>/dev/null || echo "N/A")

    echo "AVERAGE,$avg" >> "$output_dir/score_summary.csv.tmp"
    mv "$output_dir/score_summary.csv.tmp" "$output_dir/score_summary.csv"

    print_message "Score summary saved to $output_dir/score_summary.csv"

    # Display the score summary
    echo ""
    cat "$output_dir/score_summary.csv" | column -t -s ','
}

# Export functions for parallel execution
export -f run_benchmark print_message print_error print_warning print_info
export VLLM_SERVER_URL MAX_SAMPLES BASE_OUTPUT_DIR

# Main execution
print_message "========================================="
print_message "MULTI-MODEL PARALLEL BENCHMARKS EVALUATION"
print_message "========================================="
print_message "Models to evaluate (in order): ${MODEL_ORDER[@]}"
print_message "Benchmarks: ${#BENCHMARKS[@]} total"
print_message "Max parallel jobs: $MAX_PARALLEL"
print_message "Max samples per benchmark: $MAX_SAMPLES"
print_message "========================================="

# Activate conda environment
print_message "Activating conda environment: $CONDA_ENV"
source /home/saiuser/miniconda3/etc/profile.d/conda.sh
conda activate $CONDA_ENV

if [ $? -ne 0 ]; then
    print_error "Failed to activate conda environment $CONDA_ENV"
    exit 1
fi

# Record overall start time
overall_start=$(date +%s)

# Process each model in the defined order
for model_key in "${MODEL_ORDER[@]}"; do
    print_message ""
    print_message "========================================="
    print_model "EVALUATING MODEL: $model_key"
    print_message "========================================="

    # Stop any existing server
    stop_vllm_server

    # Start vLLM server for this model
    if ! start_vllm_server "$model_key"; then
        print_error "Failed to start server for $model_key, skipping..."
        continue
    fi

    # Get the served model name for API calls
    MODEL_NAME=${MODEL_SERVED_NAMES[$model_key]}
    export MODEL_NAME

    # Record model start time
    model_start=$(date +%s)

    # Run benchmarks in parallel for this model
    print_message "Running benchmarks for $model_key..."

    # Array to track PIDs
    declare -a PIDS

    # Launch benchmarks with controlled parallelism
    for benchmark in "${BENCHMARKS[@]}"; do
        # Wait if we've reached max parallel jobs
        while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
            sleep 1
        done

        # Launch benchmark in background
        print_info "Launching $benchmark for $model_key..."
        run_benchmark "$benchmark" "$MODEL_NAME" &
        PIDS+=($!)

        # Small delay to prevent race conditions
        sleep 0.5
    done

    # Wait for all benchmarks to complete
    print_message "Waiting for all benchmarks to complete for $model_key..."
    for pid in "${PIDS[@]}"; do
        wait $pid
    done

    # Clear PIDs array for next model
    unset PIDS

    # Generate score summary for this model
    generate_score_summary "$MODEL_NAME"

    # Record model end time
    model_end=$(date +%s)
    model_duration=$((model_end - model_start))

    print_message "Model $model_key completed in ${model_duration}s"

    # Stop vLLM server for this model
    stop_vllm_docker "$model_key"

    # Wait before starting next model
    sleep 5
done

# Record overall end time
overall_end=$(date +%s)
total_duration=$((overall_end - overall_start))

# Generate final summary report
print_message ""
print_message "========================================="
print_message "MULTI-MODEL EVALUATION COMPLETE"
print_message "========================================="
print_message "Total execution time: ${total_duration}s"
print_message "Models evaluated: ${MODEL_ORDER[@]}"

# Generate combined summary report
{
    echo "Multi-Model Evaluation Report"
    echo "============================="
    echo "Date: $(date)"
    echo "Total Duration: ${total_duration}s"
    echo ""
    echo "Models Evaluated (in order):"
    for model_key in "${MODEL_ORDER[@]}"; do
        echo "  - $model_key (${MODELS[$model_key]})"
    done
    echo ""
    echo "Individual Model Summaries:"
    echo ""
    for model_key in "${MODEL_ORDER[@]}"; do
        model_name=${MODEL_SERVED_NAMES[$model_key]}
        if [ -f "$BASE_OUTPUT_DIR/$model_name/score_summary.csv" ]; then
            echo "=== $model_key ==="
            cat "$BASE_OUTPUT_DIR/$model_name/score_summary.csv"
            echo ""
        fi
    done
} > "$BASE_OUTPUT_DIR/multi_model_evaluation_$(date +%Y%m%d_%H%M%S).txt"

print_message "Full report saved to $BASE_OUTPUT_DIR/multi_model_evaluation_*.txt"
print_message "Individual model results in $BASE_OUTPUT_DIR/{model_name}/"

# Display summary of all models
print_message ""
print_message "Score Summary Across All Models:"
echo ""

# Create a combined CSV with all models
python3 -c "
import os
import csv

base_dir = '$BASE_OUTPUT_DIR'
# Use the ordered model list
model_order = '${MODEL_ORDER[@]}'.split()

# Read all CSV files
all_data = {}
benchmarks_order = []
models_with_data = []

for model_key in model_order:
    model_name = model_key  # Using the key as the model name
    csv_file = os.path.join(base_dir, model_name, 'score_summary.csv')
    if os.path.exists(csv_file):
        models_with_data.append(model_name)
        with open(csv_file, 'r') as f:
            reader = csv.reader(f)
            header = next(reader)
            for row in reader:
                if row[0] not in all_data:
                    all_data[row[0]] = {}
                    benchmarks_order.append(row[0])
                all_data[row[0]][model_name] = row[1]

# Print combined table
if all_data:
    # Header
    print('Benchmarks,' + ','.join(models_with_data))

    # Data rows
    for benchmark in benchmarks_order:
        row = [benchmark]
        for model_name in models_with_data:
            row.append(all_data[benchmark].get(model_name, 'N/A'))
        print(','.join(row))
" 2>/dev/null | column -t -s ','

print_message ""
print_message "Evaluation complete!"