#!/bin/bash

# Test the logging functionality
MODEL_KEY="gpt-oss-20b"
BASE_OUTPUT_DIR="/home/saiuser/kobkrit/chinda-eval/outputs"
MODEL_OUTPUT_DIR="$BASE_OUTPUT_DIR/$MODEL_KEY"
mkdir -p "$MODEL_OUTPUT_DIR"

OUTPUT_LOG="$MODEL_OUTPUT_DIR/output.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Test logging for $MODEL_KEY" > "$OUTPUT_LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] This is a test entry" >> "$OUTPUT_LOG"

echo "Log file created at: $OUTPUT_LOG"
echo "Contents:"
cat "$OUTPUT_LOG"