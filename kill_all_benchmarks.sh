#!/bin/bash

# Script to kill all running benchmark evaluation processes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Killing All Benchmark Processes${NC}"
echo -e "${YELLOW}=========================================${NC}"

# Find and count running evalscope processes
EVAL_COUNT=$(ps aux | grep -E "evalscope eval|python.*evalscope" | grep -v grep | wc -l)

if [ $EVAL_COUNT -eq 0 ]; then
    echo -e "${GREEN}No evalscope processes are currently running.${NC}"
else
    echo -e "${YELLOW}Found $EVAL_COUNT evalscope process(es) running:${NC}"
    echo ""

    # Show running processes
    ps aux | grep -E "evalscope eval|python.*evalscope" | grep -v grep | while read line; do
        PID=$(echo "$line" | awk '{print $2}')
        BENCHMARK=$(echo "$line" | grep -oE "datasets [a-z0-9_-]+" | awk '{print $2}')
        if [ -z "$BENCHMARK" ]; then
            BENCHMARK="unknown"
        fi
        echo -e "  PID: ${RED}$PID${NC} - Benchmark: ${YELLOW}$BENCHMARK${NC}"
    done

    echo ""
    echo -e "${YELLOW}Killing all evalscope processes...${NC}"

    # Kill all evalscope processes
    ps aux | grep -E "evalscope eval|python.*evalscope" | grep -v grep | awk '{print $2}' | xargs -r kill -TERM 2>/dev/null

    # Wait a moment
    sleep 2

    # Force kill any remaining processes
    REMAINING=$(ps aux | grep -E "evalscope eval|python.*evalscope" | grep -v grep | wc -l)
    if [ $REMAINING -gt 0 ]; then
        echo -e "${YELLOW}Force killing $REMAINING stubborn process(es)...${NC}"
        ps aux | grep -E "evalscope eval|python.*evalscope" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
        sleep 1
    fi

    echo -e "${GREEN}✓ All evalscope processes have been terminated.${NC}"
fi

# Also check for any orphaned benchmark script processes
echo ""
echo -e "${YELLOW}Checking for orphaned benchmark scripts...${NC}"

# Find benchmark script processes
SCRIPT_COUNT=$(ps aux | grep -E "test.*benchmark.*\.sh|run.*benchmark.*\.sh" | grep -v grep | wc -l)

if [ $SCRIPT_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Found $SCRIPT_COUNT benchmark script(s) running:${NC}"
    ps aux | grep -E "test.*benchmark.*\.sh|run.*benchmark.*\.sh" | grep -v grep | while read line; do
        PID=$(echo "$line" | awk '{print $2}')
        SCRIPT=$(echo "$line" | awk '{print $NF}')
        echo -e "  PID: ${RED}$PID${NC} - Script: ${YELLOW}$(basename $SCRIPT)${NC}"
    done

    echo -e "${YELLOW}Killing benchmark scripts...${NC}"
    ps aux | grep -E "test.*benchmark.*\.sh|run.*benchmark.*\.sh" | grep -v grep | awk '{print $2}' | xargs -r kill -TERM 2>/dev/null
    sleep 1
    echo -e "${GREEN}✓ Benchmark scripts terminated.${NC}"
else
    echo -e "${GREEN}No benchmark scripts are running.${NC}"
fi

# Check for any background Python processes that might be benchmarking
echo ""
echo -e "${YELLOW}Checking for other benchmark-related processes...${NC}"

# Look for Python processes with benchmark-related paths
PYTHON_COUNT=$(ps aux | grep -E "python.*thai_benchmark|python.*aime24|python.*hellaswag|python.*humaneval|python.*ifeval|python.*math_500" | grep -v grep | wc -l)

if [ $PYTHON_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Found $PYTHON_COUNT related Python process(es):${NC}"
    ps aux | grep -E "python.*thai_benchmark|python.*aime24|python.*hellaswag|python.*humaneval|python.*ifeval|python.*math_500" | grep -v grep | while read line; do
        PID=$(echo "$line" | awk '{print $2}')
        echo -e "  PID: ${RED}$PID${NC}"
    done

    echo -e "${YELLOW}Killing related Python processes...${NC}"
    ps aux | grep -E "python.*thai_benchmark|python.*aime24|python.*hellaswag|python.*humaneval|python.*ifeval|python.*math_500" | grep -v grep | awk '{print $2}' | xargs -r kill -TERM 2>/dev/null
    sleep 1
    echo -e "${GREEN}✓ Related processes terminated.${NC}"
else
    echo -e "${GREEN}No other benchmark-related processes found.${NC}"
fi

# Final check
echo ""
echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Final Status Check${NC}"
echo -e "${YELLOW}=========================================${NC}"

FINAL_COUNT=$(ps aux | grep -E "evalscope|benchmark" | grep -v grep | grep -v "kill_all_benchmarks" | wc -l)

if [ $FINAL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All benchmark processes have been successfully terminated!${NC}"
    echo -e "${GREEN}The system is clean and ready for new benchmark runs.${NC}"
else
    echo -e "${YELLOW}⚠ Warning: $FINAL_COUNT process(es) might still be running:${NC}"
    ps aux | grep -E "evalscope|benchmark" | grep -v grep | grep -v "kill_all_benchmarks"
    echo ""
    echo -e "${YELLOW}You may need to manually kill these with: kill -9 <PID>${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"