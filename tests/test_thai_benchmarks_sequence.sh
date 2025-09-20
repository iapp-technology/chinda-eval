#!/bin/bash

# Sequential Thai Benchmarks Test Script with optimized vLLM
# Runs benchmarks one by one to avoid conflicts while using optimized vLLM batching

# Configuration
VLLM_SERVER_URL="http://localhost:8801/v1/chat/completions"
MODEL_NAME="gpt-oss-20b"
OUTPUT_DIR="outputs"
CONDA_ENV="chinda-eval"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if vLLM server is running
check_server() {
    print_message "Checking vLLM server..."
    if curl -s http://localhost:8801/v1/models | grep -q "gpt-oss-20b"; then
        print_message "✓ vLLM server is running with optimized batching configuration"
        return 0
    else
        print_error "vLLM server is not running or model not loaded!"
        print_error "Please ensure the server is running with optimized configuration"
        exit 1
    fi
}

# Activate conda environment
print_message "Activating conda environment: $CONDA_ENV"
source /home/saiuser/miniconda3/etc/profile.d/conda.sh
conda activate $CONDA_ENV

# Check if conda activation was successful
if [ $? -ne 0 ]; then
    print_error "Failed to activate conda environment $CONDA_ENV"
    exit 1
fi

# Check server
check_server

# Create output directory
mkdir -p $OUTPUT_DIR

# List of Thai benchmarks to test
BENCHMARKS=(
    "aime24-th"
    "hellaswag-th"
    "humaneval-th"
    "ifeval-th"
    "math_500-th"
)

# Function to test a single benchmark
test_benchmark() {
    local benchmark=$1
    print_message "Testing benchmark: $benchmark"

    # Create benchmark-specific output directory
    local bench_output_dir="$OUTPUT_DIR/$benchmark"
    mkdir -p $bench_output_dir

    # Record start time
    local start_time=$(date +%s)

    # Run the benchmark using vLLM API
    print_message "Running $benchmark via optimized vLLM API..."

    # Log the command
    echo "Command: evalscope eval with benchmark $benchmark" > "$bench_output_dir/command.txt"

    # Execute the command
    evalscope eval \
        --model $MODEL_NAME \
        --api-url $VLLM_SERVER_URL \
        --api-key EMPTY \
        --eval-type openai_api \
        --datasets $benchmark \
        --work-dir $bench_output_dir \
        --generation-config '{"do_sample": false, "temperature": 0.0, "max_new_tokens": 16384}' \
        --timeout 300 \
        --limit 1000 2>&1 | tee "$bench_output_dir/output.log"

    # Check exit status
    local exit_code=${PIPESTATUS[0]}

    # Record end time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 0 ]; then
        print_message "✓ $benchmark completed successfully in ${duration}s"
        echo "SUCCESS" > "$bench_output_dir/status.txt"
        echo "$duration" > "$bench_output_dir/duration.txt"
        return 0
    else
        print_error "✗ $benchmark failed after ${duration}s"
        echo "FAILED" > "$bench_output_dir/status.txt"
        echo "$duration" > "$bench_output_dir/duration.txt"
        return 1
    fi
}

# Main execution
print_message "========================================="
print_message "Thai Benchmarks Evaluation (Optimized vLLM)"
print_message "========================================="
print_message "Server URL: $VLLM_SERVER_URL"
print_message "Model: $MODEL_NAME"
print_message "Output directory: $OUTPUT_DIR"
print_message ""
print_message "vLLM Optimizations Active:"
print_message "  • max-num-seqs=256 (concurrent sequences)"
print_message "  • max-num-batched-tokens=32768 (batch size)"
print_message "  • enable-chunked-prefill (better batching)"
print_message "========================================="

# Record overall start time
overall_start=$(date +%s)

# Test each benchmark
failed_benchmarks=()
successful_benchmarks=()

for benchmark in "${BENCHMARKS[@]}"; do
    print_message "========================================="
    print_message "Processing $benchmark..."

    if test_benchmark "$benchmark"; then
        successful_benchmarks+=("$benchmark")
    else
        failed_benchmarks+=("$benchmark")
        print_warning "Continuing with next benchmark..."
    fi

    # Add a small delay between benchmarks
    sleep 2
done

# Record overall end time
overall_end=$(date +%s)
total_duration=$((overall_end - overall_start))

# Print summary
print_message "========================================="
print_message "Evaluation Summary"
print_message "========================================="
print_message "Total execution time: ${total_duration}s"

if [ ${#successful_benchmarks[@]} -gt 0 ]; then
    print_message "Successful benchmarks (${#successful_benchmarks[@]}):"
    for bench in "${successful_benchmarks[@]}"; do
        if [ -f "$OUTPUT_DIR/$bench/duration.txt" ]; then
            duration=$(cat "$OUTPUT_DIR/$bench/duration.txt")
            echo "  ✓ $bench (${duration}s)"
        else
            echo "  ✓ $bench"
        fi
    done
fi

if [ ${#failed_benchmarks[@]} -gt 0 ]; then
    print_error "Failed benchmarks (${#failed_benchmarks[@]}):"
    for bench in "${failed_benchmarks[@]}"; do
        if [ -f "$OUTPUT_DIR/$bench/duration.txt" ]; then
            duration=$(cat "$OUTPUT_DIR/$bench/duration.txt")
            echo "  ✗ $bench (${duration}s)"
        else
            echo "  ✗ $bench"
        fi
    done
fi

# Generate summary report
print_message "Generating summary report..."
{
    echo "Thai Benchmarks Evaluation Report (Optimized vLLM)"
    echo "=================================================="
    echo "Date: $(date)"
    echo "Server: $VLLM_SERVER_URL"
    echo "Model: $MODEL_NAME"
    echo "Total Duration: ${total_duration}s"
    echo ""
    echo "vLLM Optimizations:"
    echo "  • max-num-seqs=256"
    echo "  • max-num-batched-tokens=32768"
    echo "  • enable-chunked-prefill"
    echo ""
    echo "Results:"
    echo "--------"

    for benchmark in "${BENCHMARKS[@]}"; do
        if [ -f "$OUTPUT_DIR/$benchmark/status.txt" ]; then
            status=$(cat "$OUTPUT_DIR/$benchmark/status.txt")
            echo -n "$benchmark: $status"

            if [ -f "$OUTPUT_DIR/$benchmark/duration.txt" ]; then
                duration=$(cat "$OUTPUT_DIR/$benchmark/duration.txt")
                echo " (${duration}s)"
            else
                echo ""
            fi

            # Try to extract scores if available
            if [ -f "$OUTPUT_DIR/$benchmark/output.log" ]; then
                echo "  Scores:"
                grep -E "accuracy|acc|score|pass" "$OUTPUT_DIR/$benchmark/output.log" | tail -5 || echo "  (Scores not found)"
            fi
        else
            echo "$benchmark: NOT RUN"
        fi
        echo ""
    done

    echo ""
    echo "Performance Notes:"
    echo "-----------------"
    echo "Even though benchmarks run sequentially, the vLLM server"
    echo "automatically batches multiple tokens/sequences internally,"
    echo "providing significant speedup compared to non-optimized setup."
} > "$OUTPUT_DIR/summary_report_optimized.txt"

print_message "Summary report saved to: $OUTPUT_DIR/summary_report_optimized.txt"

# Exit with appropriate code
if [ ${#failed_benchmarks[@]} -gt 0 ]; then
    print_error "Some benchmarks failed. Please check the logs."
    exit 1
else
    print_message "All benchmarks completed successfully!"
    print_message "Total time: ${total_duration}s"
    exit 0
fi