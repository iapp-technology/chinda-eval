#!/bin/bash

# Parallel Benchmarks Test Script - Thai and English
# Runs multiple benchmarks concurrently using background processes
# Supports both single model and multi-model evaluation modes
#
# Usage:
#   ./test_thai_benchmarks_parallel.sh [model_name] [max_samples]
#   ./test_thai_benchmarks_parallel.sh --multi-model
#
# Examples:
#   ./test_thai_benchmarks_parallel.sh                    # Uses default gpt-oss-20b with 1 sample
#   ./test_thai_benchmarks_parallel.sh gpt-oss-120b 100   # Uses gpt-oss-120b with 100 samples
#   ./test_thai_benchmarks_parallel.sh --multi-model      # Runs multi-model evaluation

# Check if running in multi-model mode
MULTI_MODEL_MODE=false
if [ "$1" == "--multi-model" ]; then
    MULTI_MODEL_MODE=true
    echo "Running in multi-model mode. Use test_thai_benchmarks_multi_model.sh for full multi-model support."
    exec /home/saiuser/kobkrit/chinda-eval/run_thai_benchmarks.sh
    exit $?
fi

# Configuration
VLLM_SERVER_URL="http://localhost:8801/v1/chat/completions"
# Support multiple model names
RAW_MODEL_NAME="${1:-gpt-oss-20b}"
# Map model names to evalscope format
case "$RAW_MODEL_NAME" in
    "Qwen_Qwen3-Next-80B-A3B-Instruct")
        MODEL_NAME="qwen3-next-80b-instruct"
        ;;
    "Qwen_Qwen3-Next-80B-A3B-Thinking")
        MODEL_NAME="qwen3-next-80b-thinking"
        ;;
    *)
        MODEL_NAME="$RAW_MODEL_NAME"
        ;;
esac
BASE_OUTPUT_DIR="outputs"
OUTPUT_DIR="${BASE_OUTPUT_DIR}/${MODEL_NAME}"
CONDA_ENV="chinda-eval"
MAX_PARALLEL=3  # Limit concurrent benchmarks to avoid overwhelming the system
# 1500 cover all datasets
MAX_SAMPLES="${2:-1}" # Maximum number of test samples per benchmark (can specify as second argument)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if vLLM server is running
check_server() {
    print_message "Checking vLLM server..."
    # Get the list of models from the server
    SERVER_RESPONSE=$(curl -s http://localhost:8801/v1/models)
    if [ $? -eq 0 ] && [ -n "$SERVER_RESPONSE" ]; then
        # Check if any model is loaded (don't check for specific model)
        if echo "$SERVER_RESPONSE" | grep -q '"id"'; then
            print_message "✓ vLLM server is running"
            # Try to extract and show the loaded model
            LOADED_MODEL=$(echo "$SERVER_RESPONSE" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data['data'][0]['id'] if 'data' in data and data['data'] else 'unknown')" 2>/dev/null)
            if [ -n "$LOADED_MODEL" ] && [ "$LOADED_MODEL" != "unknown" ]; then
                print_message "  Loaded model: $LOADED_MODEL"
            fi
            return 0
        else
            print_error "vLLM server is running but no model is loaded!"
            print_error "Please start the server with a model first"
            exit 1
        fi
    else
        print_error "vLLM server is not running!"
        print_error "Please start the server first"
        exit 1
    fi
}

# Activate conda environment
print_message "Activating conda environment: $CONDA_ENV"
source /home/saiuser/miniconda3/etc/profile.d/conda.sh
conda activate $CONDA_ENV

if [ $? -ne 0 ]; then
    print_error "Failed to activate conda environment $CONDA_ENV"
    exit 1
fi

# Check server
check_server

# Create output directory
mkdir -p $OUTPUT_DIR

# List of benchmarks to test
# Thai benchmarks (HuggingFace)
THAI_BENCHMARKS=(
    "aime24-th"
    "hellaswag-th"
    "ifeval-th"
    "math_500-th"
    "code_switching"
    "live_code_bench-th"
    "openthaieval"
    # "humaneval-th"
)

# English benchmarks (uses evalscope datasets)
ENGLISH_BENCHMARKS=(
    "aime24"
    "hellaswag"
    "ifeval"
    "math_500"
    "live_code_bench"
    # "humaneval"
)

# Combine all benchmarks
BENCHMARKS=("${THAI_BENCHMARKS[@]}" "${ENGLISH_BENCHMARKS[@]}")

# Function to run a single benchmark
run_benchmark() {
    local benchmark=$1
    local bench_output_dir="$OUTPUT_DIR/${benchmark}"
    mkdir -p "$bench_output_dir"

    local start_time=$(date +%s)

    print_info "[BENCHMARK: $benchmark] Starting..."

    # Run evalscope command
    evalscope eval \
        --model $MODEL_NAME \
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
        # Show last few lines of error
        tail -10 "$bench_output_dir/output.log"
    fi
}

# Export functions for parallel execution
export -f run_benchmark print_message print_error print_warning print_info
export VLLM_SERVER_URL MODEL_NAME OUTPUT_DIR MAX_SAMPLES

# Main execution
print_message "========================================="
print_message "PARALLEL BENCHMARKS EVALUATION (Thai + English)"
print_message "========================================="
print_message "Server: $VLLM_SERVER_URL"
print_message "Model: $RAW_MODEL_NAME -> $MODEL_NAME"
print_message "Max parallel jobs: $MAX_PARALLEL"
print_message "Max samples per benchmark: $MAX_SAMPLES"
print_message "Output: $OUTPUT_DIR"
print_message ""
print_message "vLLM Optimizations:"
print_message "  • Batching: max-num-seqs=256"
print_message "  • Tokens: max-num-batched-tokens=32768"
print_message "  • Prefill: enable-chunked-prefill"
print_message "========================================="

# Record start time
overall_start=$(date +%s)

# Method 1: Using GNU parallel if available
if command -v parallel &> /dev/null; then
    print_message "Using GNU parallel for execution"
    printf '%s\n' "${BENCHMARKS[@]}" | parallel -j $MAX_PARALLEL run_benchmark {}
else
    # Method 2: Using background jobs with job control
    print_message "Using background jobs for parallel execution"

    # Array to track PIDs
    declare -a PIDS

    # Launch benchmarks with controlled parallelism
    for i in "${!BENCHMARKS[@]}"; do
        benchmark="${BENCHMARKS[$i]}"

        # Wait if we've reached max parallel jobs
        while [ $(jobs -r | wc -l) -ge $MAX_PARALLEL ]; do
            sleep 1
        done

        # Launch benchmark in background
        print_info "Launching $benchmark in background..."
        run_benchmark "$benchmark" &
        PIDS+=($!)

        # Small delay to prevent race conditions
        sleep 0.5
    done

    # Wait for all jobs to complete
    print_message "Waiting for all benchmarks to complete..."
    for pid in "${PIDS[@]}"; do
        wait $pid
    done
fi

# Record end time
overall_end=$(date +%s)
total_duration=$((overall_end - overall_start))

# Generate summary
print_message "========================================="
print_message "EXECUTION SUMMARY"
print_message "========================================="
print_message "Total execution time: ${total_duration}s"
print_message "Average time per benchmark: $((total_duration / ${#BENCHMARKS[@]}))s"

# Count results
successful=0
failed=0

for benchmark in "${BENCHMARKS[@]}"; do
    if [ -f "$OUTPUT_DIR/$benchmark/status.txt" ]; then
        status=$(cat "$OUTPUT_DIR/$benchmark/status.txt")
        if [ "$status" = "SUCCESS" ]; then
            ((successful++))
        else
            ((failed++))
        fi
    fi
done

print_message "Results: $successful successful, $failed failed"

# Show individual results
print_message ""
print_message "Detailed Results:"
for benchmark in "${BENCHMARKS[@]}"; do
    if [ -f "$OUTPUT_DIR/$benchmark/status.txt" ]; then
        status=$(cat "$OUTPUT_DIR/$benchmark/status.txt")
        if [ -f "$OUTPUT_DIR/$benchmark/duration.txt" ]; then
            duration=$(cat "$OUTPUT_DIR/$benchmark/duration.txt")
            if [ "$status" = "SUCCESS" ]; then
                echo -e "  ${GREEN}✓${NC} $benchmark (${duration}s)"
            else
                echo -e "  ${RED}✗${NC} $benchmark (${duration}s)"
            fi
        fi
    else
        echo -e "  ${YELLOW}?${NC} $benchmark (not run)"
    fi
done

# Generate report file
{
    echo "Parallel Thai Benchmarks Report"
    echo "==============================="
    echo "Date: $(date)"
    echo "Total Duration: ${total_duration}s"
    echo "Parallelism: $MAX_PARALLEL concurrent jobs"
    echo ""
    echo "Results:"
    for benchmark in "${BENCHMARKS[@]}"; do
        if [ -f "$OUTPUT_DIR/$benchmark/status.txt" ]; then
            status=$(cat "$OUTPUT_DIR/$benchmark/status.txt")
            duration=$(cat "$OUTPUT_DIR/$benchmark/duration.txt" 2>/dev/null || echo "N/A")
            echo "  $benchmark: $status (${duration}s)"
        fi
    done
} > "$OUTPUT_DIR/parallel_summary_$(date +%Y%m%d_%H%M%S).txt"

print_message "Report saved to $OUTPUT_DIR/parallel_summary_*.txt"

# Function to extract score from benchmark results
extract_score() {
    local benchmark=$1
    local bench_dir="$OUTPUT_DIR/$benchmark"

    # Look for the latest report JSON file
    local report_file=""
    if [ -d "$bench_dir" ]; then
        # Find the most recent report JSON
        report_file=$(find "$bench_dir" -name "*.json" -path "*/reports/*" 2>/dev/null | head -1)
    fi

    if [ -f "$report_file" ]; then
        # Try to extract score from JSON report
        # Different benchmarks have different score fields
        case "$benchmark" in
            "code_switching")
                # Look for language_accuracy in metrics
                python3 -c "
import json
data = json.load(open('$report_file'))
# Look for language_accuracy in metrics
for metric in data.get('metrics', []):
    if 'language_accuracy' in metric.get('name', ''):
        print(metric.get('score', 'N/A'))
        exit()
print(data.get('score', 'N/A'))
" 2>/dev/null || echo "N/A"
                ;;
            "ifeval-th"|"ifeval")
                # Look for inst_level_loose in metrics
                python3 -c "
import json
data = json.load(open('$report_file'))
# Look for inst_level_loose in metrics
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
                # Look for pass@1 or exact_match in metrics
                python3 -c "
import json
data = json.load(open('$report_file'))
# Look for pass@1 or exact_match in metrics
for metric in data.get('metrics', []):
    if 'exact_match' in metric.get('name', '') or 'pass@1' in metric.get('name', '') or 'pass' in metric.get('name', ''):
        print(metric.get('score', 'N/A'))
        exit()
print(data.get('score', 'N/A'))
" 2>/dev/null || echo "N/A"
                ;;
            *)
                # Default: look for score or accuracy field
                python3 -c "
import json
data = json.load(open('$report_file'))
# Try to find mean_acc or accuracy in metrics first
for metric in data.get('metrics', []):
    if 'mean_acc' in metric.get('name', '') or 'accuracy' in metric.get('name', ''):
        print(metric.get('score', 'N/A'))
        exit()
# Fallback to top-level score
print(data.get('score', 'N/A'))
" 2>/dev/null || echo "N/A"
                ;;
        esac
    else
        echo "N/A"
    fi
}

# Generate CSV score summary
print_message ""
print_message "Generating score summary CSV..."

{
    # Header
    echo "Benchmarks,$MODEL_NAME"

    # AIME24
    score=$(extract_score "aime24")
    echo "AIME24,$score"

    # AIME24-TH
    score=$(extract_score "aime24-th")
    echo "AIME24-TH,$score"

    # Language Accuracy (Code Switching)
    score=$(extract_score "code_switching")
    echo "Language Accuracy (Code Switching),$score"

    # LiveCodeBench
    score=$(extract_score "live_code_bench")
    echo "LiveCodeBench,$score"

    # LiveCodeBench-TH
    score=$(extract_score "live_code_bench-th")
    echo "LiveCodeBench-TH,$score"

    # MATH500
    score=$(extract_score "math_500")
    echo "MATH500,$score"

    # MATH500-TH
    score=$(extract_score "math_500-th")
    echo "MATH500-TH,$score"

    # OpenThaiEval
    score=$(extract_score "openthaieval")
    echo "OpenThaiEval,$score"

    # HellaSwag
    score=$(extract_score "hellaswag")
    echo "HellaSwag,$score"

    # HellaSwag-TH
    score=$(extract_score "hellaswag-th")
    echo "HellaSwag-TH,$score"

    # IFEval
    score=$(extract_score "ifeval")
    echo "IFEval (inst_level_loose_acc),$score"

    # IFEval-TH
    score=$(extract_score "ifeval-th")
    echo "IFEval-TH (inst_level_loose_acc),$score"

} > "$OUTPUT_DIR/score_summary.csv.tmp"

# Calculate average (excluding N/A values) and append to the CSV
avg=$(python3 -c "
scores = []
with open('$OUTPUT_DIR/score_summary.csv.tmp', 'r') as f:
    lines = f.readlines()[1:]  # Skip header
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

# Append the average to the CSV
echo "AVERAGE,$avg" >> "$OUTPUT_DIR/score_summary.csv.tmp"

# Move the temp file to the final location
mv "$OUTPUT_DIR/score_summary.csv.tmp" "$OUTPUT_DIR/score_summary.csv"

print_message "Score summary saved to $OUTPUT_DIR/score_summary.csv"

# Display the score summary
print_message ""
print_message "Score Summary:"
cat "$OUTPUT_DIR/score_summary.csv" | column -t -s ','

# Exit status
if [ $failed -gt 0 ]; then
    exit 1
else
    exit 0
fi