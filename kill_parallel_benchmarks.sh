#!/bin/bash

# Script to kill all processes spawned by test_benchmarks_parallel_fixed.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Killing Parallel Benchmark Processes${NC}"
echo -e "${YELLOW}=========================================${NC}"

# First, check if the parent script is running
PARENT_SCRIPT="test_thai_benchmarks_parallel.sh"
PARENT_PID=$(ps aux | grep "$PARENT_SCRIPT" | grep -v grep | awk '{print $2}' | head -1)

if [ ! -z "$PARENT_PID" ]; then
    echo -e "${RED}Parent script is running with PID: $PARENT_PID${NC}"
    echo -e "${YELLOW}Killing parent script first...${NC}"
    kill -TERM $PARENT_PID 2>/dev/null
    sleep 1
    # Force kill if still running
    if ps -p $PARENT_PID > /dev/null 2>&1; then
        kill -9 $PARENT_PID 2>/dev/null
    fi
    echo -e "${GREEN}✓ Parent script terminated${NC}"
fi

# Find all evalscope processes that were likely spawned by the parallel script
echo ""
echo -e "${YELLOW}Looking for evalscope processes from parallel execution...${NC}"

# The parallel script runs these benchmarks:
BENCHMARKS=("aime24" "aime24-th" "hellaswag" "hellaswag-th" "ifeval" "ifeval-th" "math_500" "math_500-th")

# Track found processes
declare -a PIDS_TO_KILL
TOTAL_FOUND=0

for benchmark in "${BENCHMARKS[@]}"; do
    # Find processes for this benchmark
    PIDS=$(ps aux | grep "evalscope eval" | grep "datasets $benchmark" | grep -v grep | awk '{print $2}')

    if [ ! -z "$PIDS" ]; then
        for pid in $PIDS; do
            # Get process details
            PROC_INFO=$(ps -p $pid -o pid,etime,args --no-headers 2>/dev/null)
            if [ ! -z "$PROC_INFO" ]; then
                ELAPSED=$(echo "$PROC_INFO" | awk '{print $2}')
                echo -e "  ${RED}PID $pid${NC} - ${YELLOW}$benchmark${NC} (running for $ELAPSED)"
                PIDS_TO_KILL+=($pid)
                ((TOTAL_FOUND++))
            fi
        done
    fi
done

# Also look for processes with the specific work directory pattern
echo ""
echo -e "${YELLOW}Checking for processes using outputs directory...${NC}"

WORK_DIR_PIDS=$(ps aux | grep -E "work-dir.*outputs|outputs.*work-dir" | grep -v grep | awk '{print $2}')

for pid in $WORK_DIR_PIDS; do
    # Check if not already in our list
    if [[ ! " ${PIDS_TO_KILL[@]} " =~ " ${pid} " ]]; then
        PROC_INFO=$(ps -p $pid -o pid,etime,args --no-headers 2>/dev/null)
        if [ ! -z "$PROC_INFO" ]; then
            ELAPSED=$(echo "$PROC_INFO" | awk '{print $2}')
            # Try to extract benchmark name from command
            BENCHMARK=$(echo "$PROC_INFO" | grep -oE "datasets [a-z0-9_-]+" | awk '{print $2}')
            if [ -z "$BENCHMARK" ]; then
                BENCHMARK="unknown"
            fi
            echo -e "  ${RED}PID $pid${NC} - ${YELLOW}$BENCHMARK${NC} (running for $ELAPSED)"
            PIDS_TO_KILL+=($pid)
            ((TOTAL_FOUND++))
        fi
    fi
done

# Kill processes if found
if [ $TOTAL_FOUND -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Found $TOTAL_FOUND process(es) to terminate${NC}"
    echo -e "${YELLOW}Sending SIGTERM to all processes...${NC}"

    for pid in "${PIDS_TO_KILL[@]}"; do
        kill -TERM $pid 2>/dev/null
    done

    sleep 2

    # Check for any survivors and force kill
    SURVIVORS=0
    for pid in "${PIDS_TO_KILL[@]}"; do
        if ps -p $pid > /dev/null 2>&1; then
            ((SURVIVORS++))
            kill -9 $pid 2>/dev/null
        fi
    done

    if [ $SURVIVORS -gt 0 ]; then
        echo -e "${YELLOW}Force killed $SURVIVORS stubborn process(es)${NC}"
    fi

    echo -e "${GREEN}✓ All processes terminated successfully${NC}"
else
    echo -e "${GREEN}No processes from parallel benchmark execution found${NC}"
fi

# Also clean up any background shell jobs that might be hanging
echo ""
echo -e "${YELLOW}Checking for background shell jobs...${NC}"

# Look for bash processes that might be running benchmark functions
BASH_PROCS=$(ps aux | grep -E "bash.*run_benchmark|bash.*test_benchmark" | grep -v grep | awk '{print $2}')

if [ ! -z "$BASH_PROCS" ]; then
    echo -e "${YELLOW}Found background bash processes:${NC}"
    for pid in $BASH_PROCS; do
        echo -e "  ${RED}PID $pid${NC}"
        kill -TERM $pid 2>/dev/null
    done
    sleep 1
    echo -e "${GREEN}✓ Background bash processes terminated${NC}"
else
    echo -e "${GREEN}No background bash processes found${NC}"
fi

# Clean up any lock files or temporary files
echo ""
echo -e "${YELLOW}Cleaning up temporary files...${NC}"

# Remove any PID files that might have been created
if [ -d "./outputs" ]; then
    find ./outputs -name "*.pid" -type f -delete 2>/dev/null
    find ./outputs -name "*.lock" -type f -delete 2>/dev/null
    echo -e "${GREEN}✓ Cleaned up temporary files${NC}"
fi

# Final verification
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Final Status Check${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if any benchmark processes are still running
REMAINING=$(ps aux | grep "evalscope eval" | grep -E "aime24-th|hellaswag-th|humaneval-th|ifeval-th|math_500-th" | grep -v grep | wc -l)

if [ $REMAINING -eq 0 ]; then
    echo -e "${GREEN}✓ All parallel benchmark processes successfully terminated!${NC}"
    echo -e "${GREEN}System is clean and ready for new benchmark runs.${NC}"

    # Show vLLM server status
    echo ""
    echo -e "${BLUE}vLLM Server Status:${NC}"
    if curl -s http://localhost:8801/v1/models > /dev/null 2>&1; then
        echo -e "${GREEN}✓ vLLM server is running and available${NC}"
    else
        echo -e "${YELLOW}⚠ vLLM server is not responding${NC}"
    fi
else
    echo -e "${RED}⚠ Warning: $REMAINING benchmark process(es) still running:${NC}"
    ps aux | grep "evalscope eval" | grep -E "aime24-th|hellaswag-th|humaneval-th|ifeval-th|math_500-th" | grep -v grep
    echo ""
    echo -e "${YELLOW}You may need to run: ./kill_all_benchmarks.sh${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"