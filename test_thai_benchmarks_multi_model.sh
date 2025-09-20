#!/bin/bash

# Multi-Model Parallel Benchmarks Evaluation Script
# Automatically manages vLLM servers and evaluates multiple models in sequence
#
# Usage:
#   ./test_thai_benchmarks_multi_model.sh [OPTIONS]
#
# Options:
#   --models MODEL1 MODEL2 ...    Specify models to evaluate (default: all 4 models)
#   --benchmarks BENCH1 BENCH2... Specify benchmarks to run (default: all 12 benchmarks)
#   --limit N                      Override default sample limit (default: 1500)
#
# Benchmark Sample Limits:
#   You can adjust per-benchmark limits in BENCHMARK_LIMITS array below.
#   This is useful for reducing runtime on slow benchmarks like code_switching
#   and live_code_bench which can take 5+ hours with 1500 samples.
#
# Known Issues:
#   - gpt-oss-120b: Has problems with IFEval benchmark when generating JSON/structured
#     output, causing 500 Internal Server Errors. Limited to 10 samples as workaround.

# Configuration
VLLM_PORT=8801
VLLM_SERVER_URL="http://localhost:${VLLM_PORT}/v1/chat/completions"
BASE_OUTPUT_DIR="thai_benchmark_results_api"
CONDA_ENV="chinda-eval"
MAX_PARALLEL=3  # Limit concurrent benchmarks
EVAL_BATCH_SIZE=20 # Limit the number of samples to generate at once
DEFAULT_MAX_SAMPLES=1500 # Default maximum samples per benchmark

# Per-benchmark sample limits (override DEFAULT_MAX_SAMPLES)
# Adjust these values based on your needs and time constraints
declare -A BENCHMARK_LIMITS
BENCHMARK_LIMITS["code_switching"]=500       # Reduced from 1500 to speed up (was taking 5+ hours)
BENCHMARK_LIMITS["live_code_bench"]=200      # Reduced from 1500 to speed up (was taking 5+ hours)
BENCHMARK_LIMITS["live_code_bench-th"]=200   # Reduced for consistency with English version
BENCHMARK_LIMITS["math_500"]=500             # Math problems can be slow
BENCHMARK_LIMITS["math_500-th"]=500          # Math problems can be slow
BENCHMARK_LIMITS["ifeval"]=500               # Set to 500 for proper testing
BENCHMARK_LIMITS["ifeval-th"]=500            # Set to 500 for proper testing
# Add more benchmark-specific limits as needed
# BENCHMARK_LIMITS["aime24"]=1500
# BENCHMARK_LIMITS["aime24-th"]=1500
# BENCHMARK_LIMITS["hellaswag"]=1500
# BENCHMARK_LIMITS["hellaswag-th"]=1500
# BENCHMARK_LIMITS["ifeval"]=1500
# BENCHMARK_LIMITS["ifeval-th"]=1500
# BENCHMARK_LIMITS["openthaieval"]=1500

# Ensure the output directory exists
if [ ! -d "$BASE_OUTPUT_DIR" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating output directory: $BASE_OUTPUT_DIR"
    mkdir -p "$BASE_OUTPUT_DIR"
    if [ $? -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Output directory created successfully"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to create output directory"
        exit 1
    fi
fi

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
            DEFAULT_MAX_SAMPLES="$2"
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
        # "gpt-oss-20b"
        # "gpt-oss-120b"
        # "qwen3-next-80b-instruct"
        # "qwen3-next-80b-thinking"
        "chinda-qwen3-0.6b"
        "chinda-qwen3-1.7b"
        "chinda-qwen3-8b"
        "chinda-qwen3-14b"
        "chinda-qwen3-32b"
    )
fi

# Note: Model configurations are defined in individual docker-compose files:
# - docker-compose.gpt-oss-20b.yml
# - docker-compose.gpt-oss-120b.yml
# - docker-compose.qwen3-next-80b-instruct.yml
# - docker-compose.qwen3-next-80b-thinking.yml
# - docker-compose.chinda-qwen3-0.6b.yml
# - docker-compose.chinda-qwen3-1.7b.yml
# - docker-compose.chinda-qwen3-8b.yml
# - docker-compose.chinda-qwen3-14b.yml
# - docker-compose.chinda-qwen3-32b.yml

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

    # Stop any running vLLM containers by checking what's actually running
    # This avoids accidentally stopping containers from other model runs
    docker ps --format "{{.Names}}" | grep -E "vllm-server|gptoss|qwen3" | while read container_name; do
        docker stop "$container_name" 2>/dev/null
    done

    # Also check for any temp compose files (for backward compatibility)
    for compose_file in /tmp/docker-compose-*.yml; do
        if [[ -f "$compose_file" ]]; then
            docker compose -f "$compose_file" down --remove-orphans 2>/dev/null
            rm -f "$compose_file"
        fi
    done

    # Clean up any stale containers with tmp-vllm-server prefix
    docker ps -a | grep 'tmp-vllm-server' | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null

    # Kill processes on the port
    lsof -ti:${VLLM_PORT} | xargs -r kill -9 2>/dev/null

    # Wait a moment for cleanup
    sleep 2
}

# Function to start vLLM server for a specific model
start_vllm_server() {
    local model_key=$1

    print_model "Starting vLLM server for $model_key"

    # Use the existing docker-compose file for this model
    local compose_file="/home/saiuser/kobkrit/chinda-eval/docker-compose.${model_key}.yml"

    if [[ ! -f "$compose_file" ]]; then
        print_error "Docker compose file not found for $model_key: $compose_file"
        print_error "Please ensure docker-compose.${model_key}.yml exists"
        return 1
    fi

    print_info "Using docker-compose file: $compose_file"

    # Start the Docker container using the existing compose file
    docker compose -f "$compose_file" up -d --remove-orphans

    if [ $? -ne 0 ]; then
        print_error "Failed to start Docker container for $model_key"
        return 1
    fi

    # Wait for server to be ready
    print_info "Waiting for vLLM server to be ready (this may take several minutes for large models)..."
    local max_wait=600  # Increased to 10 minutes for larger models
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if curl -s http://localhost:${VLLM_PORT}/v1/models 2>/dev/null | grep -q "$model_key"; then
            print_message "✓ vLLM server for $model_key is ready!"
            return 0
        fi
        echo -n "."
        sleep 10  # Check every 10 seconds
        waited=$((waited + 10))
    done

    print_error "Server failed to start within ${max_wait} seconds"
    docker compose -f "$compose_file" logs
    return 1
}

# Function to stop vLLM server for a specific model
stop_vllm_docker() {
    local model_key=$1
    print_info "Stopping vLLM server for $model_key..."

    # Use the existing docker-compose file for this model
    local compose_file="/home/saiuser/kobkrit/chinda-eval/docker-compose.${model_key}.yml"

    if [[ -f "$compose_file" ]]; then
        docker compose -f "$compose_file" down --remove-orphans
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

    # Get the sample limit for this benchmark
    local sample_limit="${BENCHMARK_LIMITS[$benchmark]:-$DEFAULT_MAX_SAMPLES}"

    print_info "[BENCHMARK: $benchmark] Starting for model: $model_name (limit: $sample_limit samples)..."

    # Run evalscope command
    evalscope eval \
        --model $model_name \
        --api-url $VLLM_SERVER_URL \
        --api-key EMPTY \
        --eval-type openai_api \
        --datasets $benchmark \
        --dataset-hub huggingface \
        --work-dir "$bench_output_dir" \
        --eval-batch-size $EVAL_BATCH_SIZE \
        --generation-config '{"do_sample": false, "temperature": 0.0, "max_new_tokens": 32768}' \
        --timeout 300 \
        --limit $sample_limit > "$bench_output_dir/output.log" 2>&1

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

# Export functions and variables for parallel execution
export -f run_benchmark print_message print_error print_warning print_info
export VLLM_SERVER_URL DEFAULT_MAX_SAMPLES BASE_OUTPUT_DIR EVAL_BATCH_SIZE
export -A BENCHMARK_LIMITS  # Export the associative array

# Main execution
print_message "========================================="
print_message "MULTI-MODEL PARALLEL BENCHMARKS EVALUATION"
print_message "========================================="
print_message "Models to evaluate (in order): ${MODEL_ORDER[@]}"
print_message "Benchmarks: ${#BENCHMARKS[@]} total"
print_message "Max parallel jobs: $MAX_PARALLEL"
print_message "Default max samples: $DEFAULT_MAX_SAMPLES"

# Show benchmark-specific limits if any
if [ ${#BENCHMARK_LIMITS[@]} -gt 0 ]; then
    print_message "Benchmark-specific limits:"
    for bench in "${!BENCHMARK_LIMITS[@]}"; do
        print_info "  - $bench: ${BENCHMARK_LIMITS[$bench]} samples"
    done
fi

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

    # Create output directory for this model
    MODEL_OUTPUT_DIR="$BASE_OUTPUT_DIR/$model_key"
    mkdir -p "$MODEL_OUTPUT_DIR"

    # Set up output log file for this model
    OUTPUT_LOG="$MODEL_OUTPUT_DIR/output.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting evaluation for $model_key" > "$OUTPUT_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Default max samples: $DEFAULT_MAX_SAMPLES" >> "$OUTPUT_LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Benchmarks to run: ${BENCHMARKS[*]}" >> "$OUTPUT_LOG"

    # Log benchmark-specific limits
    for bench in "${BENCHMARKS[@]}"; do
        if [ -n "${BENCHMARK_LIMITS[$bench]}" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')]   - $bench: ${BENCHMARK_LIMITS[$bench]} samples (custom limit)" >> "$OUTPUT_LOG"
        fi
    done

    # Stop any existing server
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping any existing vLLM servers" >> "$OUTPUT_LOG"
    stop_vllm_server

    # Start vLLM server for this model
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting vLLM server for $model_key" >> "$OUTPUT_LOG"
    if ! start_vllm_server "$model_key"; then
        print_error "Failed to start server for $model_key, skipping..."
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start server" >> "$OUTPUT_LOG"
        continue
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] vLLM server started successfully" >> "$OUTPUT_LOG"

    # Use the model key as the model name (matches docker-compose configuration)
    MODEL_NAME=$model_key
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
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching $benchmark" >> "$OUTPUT_LOG"
        {
            run_benchmark "$benchmark" "$MODEL_NAME"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed $benchmark" >> "$OUTPUT_LOG"
        } &
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

    # Log completion
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Evaluation completed for $model_key" >> "$OUTPUT_LOG"

    # Record model end time
    model_end=$(date +%s)
    model_duration=$((model_end - model_start))

    print_message "Model $model_key completed in ${model_duration}s"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Total duration: ${model_duration}s" >> "$OUTPUT_LOG"
    print_info "Output log saved to $OUTPUT_LOG"

    # Stop vLLM server for this model
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping vLLM server for $model_key" >> "$OUTPUT_LOG"
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
        echo "  - $model_key"
    done
    echo ""
    echo "Individual Model Summaries:"
    echo ""
    for model_key in "${MODEL_ORDER[@]}"; do
        if [ -f "$BASE_OUTPUT_DIR/$model_key/score_summary.csv" ]; then
            echo "=== $model_key ==="
            cat "$BASE_OUTPUT_DIR/$model_key/score_summary.csv"
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