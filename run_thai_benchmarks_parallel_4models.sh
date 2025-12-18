#!/bin/bash

# Parallel 4-Model Benchmark Evaluation Script
# Runs chinda-qwen3-4b, 8b, 14b, and 32b models simultaneously using different ports and GPUs
# Each model uses 2 GPUs (total 8 GPUs)
#
# Port and GPU allocation:
#   - chinda-qwen3-4b:  Port 8804, GPUs 0,1
#   - chinda-qwen3-8b:  Port 8808, GPUs 2,3
#   - chinda-qwen3-14b: Port 8814, GPUs 4,5
#   - chinda-qwen3-32b: Port 8832, GPUs 6,7
#
# Usage:
#   ./run_thai_benchmarks_parallel_4models.sh [OPTIONS]
#
# Options:
#   --benchmarks BENCH1 BENCH2... Specify benchmarks to run (default: all 12 benchmarks)
#   --limit N                      Override default sample limit (default: 1500)

# Configuration
BASE_OUTPUT_DIR="outputs"
CONDA_ENV="chinda-eval"
MAX_PARALLEL_PER_MODEL=12  # Max concurrent benchmarks per model
EVAL_BATCH_SIZE=1
DEFAULT_MAX_SAMPLES=1500

# Model configurations with their ports
declare -A MODEL_PORTS
MODEL_PORTS["chinda-qwen3-4b"]=8804
MODEL_PORTS["chinda-qwen3-8b"]=8808
MODEL_PORTS["chinda-qwen3-14b"]=8814
MODEL_PORTS["chinda-qwen3-32b"]=8832

# Models to run in parallel
MODELS=(
    "chinda-qwen3-4b"
    "chinda-qwen3-8b"
    "chinda-qwen3-14b"
    "chinda-qwen3-32b"
)

# Per-benchmark sample limits
declare -A BENCHMARK_LIMITS
BENCHMARK_LIMITS["code_switching"]=500
BENCHMARK_LIMITS["live_code_bench"]=200
BENCHMARK_LIMITS["live_code_bench-th"]=200
BENCHMARK_LIMITS["math_500"]=500
BENCHMARK_LIMITS["math_500-th"]=500
BENCHMARK_LIMITS["ifeval"]=500
BENCHMARK_LIMITS["ifeval-th"]=500

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored messages with model prefix
print_model_message() {
    local model=$1
    local message=$2
    local color=$3
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$model]${NC} $message"
}

# Function to stop all vLLM servers
stop_all_servers() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] Stopping all vLLM servers...${NC}"

    # Stop each model's container
    for model_key in "${MODELS[@]}"; do
        docker compose -f "/home/saiuser/kobkrit/chinda-eval/dockers/docker-compose.${model_key}.yml" down --remove-orphans 2>/dev/null
    done

    # Kill any processes on the ports
    for port in "${MODEL_PORTS[@]}"; do
        lsof -ti:${port} | xargs -r kill -9 2>/dev/null
    done

    sleep 2
}

# Function to start vLLM server for a specific model
start_model_server() {
    local model_key=$1
    local port=${MODEL_PORTS[$model_key]}

    print_model_message "$model_key" "Starting vLLM server on port $port" "$CYAN"

    local compose_file="/home/saiuser/kobkrit/chinda-eval/dockers/docker-compose.${model_key}.yml"

    if [[ ! -f "$compose_file" ]]; then
        print_model_message "$model_key" "ERROR: Docker compose file not found: $compose_file" "$RED"
        return 1
    fi

    # Start the Docker container
    docker compose -f "$compose_file" up -d --remove-orphans

    if [ $? -ne 0 ]; then
        print_model_message "$model_key" "ERROR: Failed to start Docker container" "$RED"
        return 1
    fi

    # Wait for server to be ready
    print_model_message "$model_key" "Waiting for server to be ready on port $port..." "$BLUE"
    local max_wait=600  # 10 minutes
    local waited=0

    while [ $waited -lt $max_wait ]; do
        if curl -s http://localhost:${port}/v1/models 2>/dev/null | grep -q "$model_key"; then
            print_model_message "$model_key" "✓ Server ready on port $port!" "$GREEN"
            return 0
        fi
        echo -n "."
        sleep 10
        waited=$((waited + 10))
    done

    print_model_message "$model_key" "ERROR: Server failed to start within ${max_wait} seconds" "$RED"
    docker compose -f "$compose_file" logs
    return 1
}

# Function to run a single benchmark for a model
run_benchmark() {
    local benchmark=$1
    local model_name=$2
    local port=$3
    local bench_output_dir="$BASE_OUTPUT_DIR/${model_name}/${benchmark}"
    mkdir -p "$bench_output_dir"

    local start_time=$(date +%s)
    local sample_limit="${BENCHMARK_LIMITS[$benchmark]:-$DEFAULT_MAX_SAMPLES}"

    print_model_message "$model_name" "Starting benchmark: $benchmark (limit: $sample_limit samples)" "$BLUE"

    # Run evalscope command with model-specific port
    evalscope eval \
        --model $model_name \
        --api-url "http://localhost:${port}/v1/chat/completions" \
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
        print_model_message "$model_name" "✓ Benchmark $benchmark completed in ${duration}s" "$GREEN"
        echo "SUCCESS" > "$bench_output_dir/status.txt"
    else
        print_model_message "$model_name" "✗ Benchmark $benchmark failed after ${duration}s" "$RED"
        echo "FAILED" > "$bench_output_dir/status.txt"
    fi
    echo "$duration" > "$bench_output_dir/duration.txt"
}

# Function to extract score from benchmark results
extract_score() {
    local benchmark=$1
    local model_name=$2
    local bench_dir="$BASE_OUTPUT_DIR/$model_name/$benchmark"

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

# Function to generate score summary for a model
generate_score_summary() {
    local model_name=$1
    local output_dir="$BASE_OUTPUT_DIR/$model_name"

    print_model_message "$model_name" "Generating score summary..." "$CYAN"

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
    } > "$output_dir/score_summary.csv"

    # Calculate average
    avg=$(python3 -c "
scores = []
with open('$output_dir/score_summary.csv', 'r') as f:
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

    echo "AVERAGE,$avg" >> "$output_dir/score_summary.csv"
    print_model_message "$model_name" "Score summary saved to $output_dir/score_summary.csv" "$GREEN"
}

# Function to run all benchmarks for a model
run_model_benchmarks() {
    local model_key=$1
    local port=${MODEL_PORTS[$model_key]}
    local model_output_dir="$BASE_OUTPUT_DIR/$model_key"
    mkdir -p "$model_output_dir"

    local model_log="$model_output_dir/model_run.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting evaluation for $model_key on port $port" > "$model_log"

    # Start server for this model
    if ! start_model_server "$model_key"; then
        print_model_message "$model_key" "Failed to start server, skipping..." "$RED"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to start server" >> "$model_log"
        return 1
    fi

    # Run benchmarks for this model with controlled parallelism
    local pids=()
    for benchmark in "${BENCHMARKS[@]}"; do
        # Wait if we've reached max parallel jobs for this model
        while [ $(jobs -r -p | wc -l) -ge $MAX_PARALLEL_PER_MODEL ]; do
            sleep 1
        done

        # Launch benchmark in background
        {
            run_benchmark "$benchmark" "$model_key" "$port"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Completed $benchmark" >> "$model_log"
        } &
        pids+=($!)

        sleep 0.5
    done

    # Wait for all benchmarks to complete for this model
    print_model_message "$model_key" "Waiting for all benchmarks to complete..." "$BLUE"
    for pid in "${pids[@]}"; do
        wait $pid
    done

    # Generate score summary
    generate_score_summary "$model_key"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Evaluation completed for $model_key" >> "$model_log"
    print_model_message "$model_key" "✓ All benchmarks completed!" "$GREEN"
}

# Parse command line arguments
BENCHMARKS_TO_RUN=()
while [[ $# -gt 0 ]]; do
    case $1 in
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
            shift
            ;;
    esac
done

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

# Use specified benchmarks or default to all
if [ ${#BENCHMARKS_TO_RUN[@]} -eq 0 ]; then
    BENCHMARKS=("${ALL_BENCHMARKS[@]}")
else
    BENCHMARKS=("${BENCHMARKS_TO_RUN[@]}")
fi

# Export functions and variables for parallel execution
export -f run_benchmark print_model_message extract_score generate_score_summary
export BASE_OUTPUT_DIR EVAL_BATCH_SIZE DEFAULT_MAX_SAMPLES
export -A BENCHMARK_LIMITS MODEL_PORTS
export RED GREEN YELLOW BLUE CYAN MAGENTA NC

# Main execution
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}PARALLEL 4-MODEL BENCHMARK EVALUATION${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${CYAN}Models:${NC} ${MODELS[@]}"
echo -e "${CYAN}Ports:${NC}"
for model in "${MODELS[@]}"; do
    echo "  - $model: ${MODEL_PORTS[$model]}"
done
echo -e "${CYAN}Benchmarks:${NC} ${#BENCHMARKS[@]} total"
echo -e "${CYAN}Max parallel benchmarks per model:${NC} $MAX_PARALLEL_PER_MODEL"
echo -e "${CYAN}Default max samples:${NC} $DEFAULT_MAX_SAMPLES"

if [ ${#BENCHMARK_LIMITS[@]} -gt 0 ]; then
    echo -e "${CYAN}Benchmark-specific limits:${NC}"
    for bench in "${!BENCHMARK_LIMITS[@]}"; do
        echo "  - $bench: ${BENCHMARK_LIMITS[$bench]} samples"
    done
fi

echo -e "${GREEN}=========================================${NC}"

# Ensure output directory exists
mkdir -p "$BASE_OUTPUT_DIR"

# Activate conda environment
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] Activating conda environment: $CONDA_ENV${NC}"
source /home/saiuser/miniconda3/etc/profile.d/conda.sh
conda activate $CONDA_ENV

if [ $? -ne 0 ]; then
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to activate conda environment $CONDA_ENV${NC}"
    exit 1
fi

# Record overall start time
overall_start=$(date +%s)

# Stop any existing servers
stop_all_servers

# Start all models in parallel
echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] Starting all 4 models in parallel...${NC}"

declare -a MODEL_PIDS
for model_key in "${MODELS[@]}"; do
    {
        run_model_benchmarks "$model_key"
    } &
    MODEL_PIDS+=($!)
    echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')] Launched $model_key (PID: ${MODEL_PIDS[-1]})${NC}"
done

# Wait for all models to complete
echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for all models to complete...${NC}"
for pid in "${MODEL_PIDS[@]}"; do
    wait $pid
done

# Record overall end time
overall_end=$(date +%s)
total_duration=$((overall_end - overall_start))

# Stop all servers
stop_all_servers

# Generate final summary report
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}PARALLEL EVALUATION COMPLETE${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${CYAN}Total execution time:${NC} ${total_duration}s"
echo -e "${CYAN}Models evaluated:${NC} ${MODELS[@]}"

# Generate combined summary report
{
    echo "Parallel 4-Model Evaluation Report"
    echo "=================================="
    echo "Date: $(date)"
    echo "Total Duration: ${total_duration}s"
    echo ""
    echo "Models Evaluated (in parallel):"
    for model_key in "${MODELS[@]}"; do
        echo "  - $model_key (port ${MODEL_PORTS[$model_key]})"
    done
    echo ""
    echo "Individual Model Summaries:"
    echo ""
    for model_key in "${MODELS[@]}"; do
        if [ -f "$BASE_OUTPUT_DIR/$model_key/score_summary.csv" ]; then
            echo "=== $model_key ==="
            cat "$BASE_OUTPUT_DIR/$model_key/score_summary.csv"
            echo ""
        fi
    done
} > "$BASE_OUTPUT_DIR/parallel_4model_evaluation_$(date +%Y%m%d_%H%M%S).txt"

echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] Full report saved to $BASE_OUTPUT_DIR/parallel_4model_evaluation_*.txt${NC}"
echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] Individual model results in $BASE_OUTPUT_DIR/{model_name}/${NC}"

# Display summary of all models
echo ""
echo -e "${CYAN}Score Summary Across All Models:${NC}"
echo ""

# Create a combined CSV with all models
python3 -c "
import os
import csv

base_dir = '$BASE_OUTPUT_DIR'
models = '${MODELS[@]}'.split()

# Read all CSV files
all_data = {}
benchmarks_order = []
models_with_data = []

for model_name in models:
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

echo ""
echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] Evaluation complete!${NC}"