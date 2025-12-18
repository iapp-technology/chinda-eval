#!/bin/bash
# Extract benchmark scores from evaluation outputs
# Usage: ./extract_scores.sh <output_folder_path>
# Example: ./extract_scores.sh outputs/OpenThaiGPT-ThaiLLM-8B-FullSFT-v2-20251214-200000-sft

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$1" ]; then
    echo "Usage: $0 <output_folder_path>"
    echo "Example: $0 outputs/OpenThaiGPT-ThaiLLM-8B-FullSFT-v2-20251214-200000-sft"
    exit 1
fi

python3 "${SCRIPT_DIR}/extract_scores.py" "$1"
