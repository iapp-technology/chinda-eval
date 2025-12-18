#!/bin/bash

# Script to retest IFEval-TH benchmark and fix score extraction for 4 models
# This addresses the issue where IFEval-TH scores are showing as 0.0

# Configuration
BASE_OUTPUT_DIR="outputs"
CONDA_ENV="chinda-eval"
EVAL_BATCH_SIZE=1
MAX_SAMPLES=500  # IFEval-TH sample limit

# Model configurations with their ports
declare -A MODEL_PORTS
MODEL_PORTS["chinda-qwen3-4b"]=8804
MODEL_PORTS["chinda-qwen3-8b"]=8808
MODEL_PORTS["chinda-qwen3-14b"]=8814
MODEL_PORTS["chinda-qwen3-32b"]=8832

# Models to test
MODELS=(
    "chinda-qwen3-4b"
    "chinda-qwen3-8b"
    "chinda-qwen3-14b"
    "chinda-qwen3-32b"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_message() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

print_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to extract IFEval-TH score correctly
extract_ifeval_score() {
    local model_name=$1
    local bench_dir="$BASE_OUTPUT_DIR/$model_name/ifeval-th"

    # Find the latest report JSON file
    local report_file=""
    if [ -d "$bench_dir" ]; then
        report_file=$(find "$bench_dir" -name "*.json" -path "*/reports/*" 2>/dev/null | sort | tail -1)
    fi

    if [ -f "$report_file" ]; then
        python3 -c "
import json
data = json.load(open('$report_file'))
for metric in data.get('metrics', []):
    if 'inst_level_loose' in metric.get('name', ''):
        # Check if main score is 0 but subset score exists
        score = metric.get('score', 0)
        if score == 0 and metric.get('categories'):
            for cat in metric['categories']:
                if cat.get('subsets'):
                    for subset in cat['subsets']:
                        if subset.get('score', 0) != 0:
                            print(f\"{subset['score']:.4f}\")
                            exit()
        else:
            print(f\"{score:.4f}\")
            exit()
print('N/A')
" 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# Function to update score summary with correct IFEval-TH score
update_score_summary() {
    local model_name=$1
    local ifeval_th_score=$2
    local summary_file="$BASE_OUTPUT_DIR/$model_name/score_summary.csv"

    if [ -f "$summary_file" ]; then
        # Create backup
        cp "$summary_file" "${summary_file}.bak"

        # Update the IFEval-TH line
        python3 -c "
import csv

# Read the file
lines = []
with open('$summary_file', 'r') as f:
    lines = f.readlines()

# Update IFEval-TH score
new_lines = []
for line in lines:
    if line.startswith('IFEval-TH'):
        new_lines.append(f'IFEval-TH (inst_level_loose_acc),$ifeval_th_score\\n')
    elif line.startswith('AVERAGE'):
        # Recalculate average
        scores = []
        for l in lines[1:-1]:  # Skip header and average line
            if ',' in l:
                parts = l.strip().split(',')
                if len(parts) == 2 and parts[1] != 'N/A':
                    try:
                        # Use updated score for IFEval-TH
                        if l.startswith('IFEval-TH'):
                            scores.append(float('$ifeval_th_score'))
                        else:
                            scores.append(float(parts[1]))
                    except:
                        pass
        if scores:
            avg = sum(scores) / len(scores)
            new_lines.append(f'AVERAGE,{avg}\\n')
        else:
            new_lines.append(line)
    else:
        new_lines.append(line)

# Write updated file
with open('$summary_file', 'w') as f:
    f.writelines(new_lines)
"
        print_message "Updated score summary for $model_name with IFEval-TH score: $ifeval_th_score"
    fi
}

# Function to run IFEval-TH benchmark for a single model
run_ifeval_th() {
    local model_name=$1
    local port=$2

    print_info "Running IFEval-TH for $model_name on port $port..."

    local bench_output_dir="$BASE_OUTPUT_DIR/${model_name}/ifeval-th"
    mkdir -p "$bench_output_dir"

    # Run evalscope command
    evalscope eval \
        --model $model_name \
        --api-url "http://localhost:${port}/v1/chat/completions" \
        --api-key EMPTY \
        --eval-type openai_api \
        --datasets ifeval-th \
        --dataset-hub huggingface \
        --work-dir "$bench_output_dir" \
        --eval-batch-size $EVAL_BATCH_SIZE \
        --generation-config '{"do_sample": false, "temperature": 0.0, "max_new_tokens": 32768}' \
        --timeout 300 \
        --limit $MAX_SAMPLES > "$bench_output_dir/retest_output.log" 2>&1

    if [ $? -eq 0 ]; then
        print_message "✓ IFEval-TH completed for $model_name"
        return 0
    else
        print_error "✗ IFEval-TH failed for $model_name"
        tail -20 "$bench_output_dir/retest_output.log"
        return 1
    fi
}

# Main execution
print_message "========================================="
print_message "IFEval-TH RETEST AND SCORE FIX"
print_message "========================================="
print_message "Models: ${MODELS[@]}"
print_message "========================================="

# Activate conda environment
print_message "Activating conda environment: $CONDA_ENV"
source /home/saiuser/miniconda3/etc/profile.d/conda.sh
conda activate $CONDA_ENV

if [ $? -ne 0 ]; then
    print_error "Failed to activate conda environment $CONDA_ENV"
    exit 1
fi

# First, extract and display current scores
print_message ""
print_message "Current IFEval-TH scores (with correct extraction):"
echo ""
for model in "${MODELS[@]}"; do
    score=$(extract_ifeval_score "$model")
    printf "%-20s: %s\n" "$model" "$score"
done

# Ask user if they want to proceed with retesting
echo ""
read -p "Do you want to rerun IFEval-TH benchmarks? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_message "Starting IFEval-TH retesting..."

    # Check if servers are running
    for model in "${MODELS[@]}"; do
        port=${MODEL_PORTS[$model]}
        print_info "Checking if $model server is running on port $port..."

        if curl -s http://localhost:${port}/v1/models 2>/dev/null | grep -q "$model"; then
            print_message "✓ $model server is already running"

            # Run IFEval-TH benchmark
            run_ifeval_th "$model" "$port"

            # Extract new score
            new_score=$(extract_ifeval_score "$model")
            print_message "New IFEval-TH score for $model: $new_score"
        else
            print_error "$model server is not running on port $port"
            print_info "Please start the server using: ./dockers/start_${model}_vllm_docker.sh"
            print_info "Or run all servers with: ./run_thai_benchmarks_parallel_4models.sh"
        fi
    done
else
    print_message "Skipping benchmark rerun, only updating scores..."
fi

# Update all score summaries with correct scores
print_message ""
print_message "Updating score summaries with correct IFEval-TH scores..."
echo ""

for model in "${MODELS[@]}"; do
    score=$(extract_ifeval_score "$model")
    if [ "$score" != "N/A" ]; then
        update_score_summary "$model" "$score"
        print_message "$model - IFEval-TH score updated to: $score"
    else
        print_error "$model - No IFEval-TH score found"
    fi
done

# Display final summary
print_message ""
print_message "========================================="
print_message "FINAL IFEval-TH SCORES"
print_message "========================================="
for model in "${MODELS[@]}"; do
    if [ -f "$BASE_OUTPUT_DIR/$model/score_summary.csv" ]; then
        score=$(grep "IFEval-TH" "$BASE_OUTPUT_DIR/$model/score_summary.csv" | cut -d',' -f2)
        printf "%-20s: %s\n" "$model" "$score"
    fi
done

print_message ""
print_message "Score summaries have been updated!"
print_message "Check individual files at: $BASE_OUTPUT_DIR/{model_name}/score_summary.csv"