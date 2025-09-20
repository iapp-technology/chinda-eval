#!/bin/bash

# Universal script to kill all running benchmark processes
# Works for both parallel and sequential benchmark runs

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=========================================${NC}"
echo -e "${YELLOW}Killing All Benchmark Processes${NC}"
echo -e "${YELLOW}=========================================${NC}"

# Track all PIDs to kill
declare -a PIDS_TO_KILL
TOTAL_FOUND=0

# 1. Find the main benchmark runner scripts
echo -e "${YELLOW}Checking for main benchmark runner scripts...${NC}"

# Check for run_thai_benchmarks.sh (main multi-model runner)
MAIN_PID=$(ps aux | grep "run_thai_benchmarks.sh" | grep -v grep | awk '{print $2}' | head -1)
if [ ! -z "$MAIN_PID" ]; then
    echo -e "${RED}Main runner script is running with PID: $MAIN_PID${NC}"
    kill -TERM $MAIN_PID 2>/dev/null
    sleep 1
    if ps -p $MAIN_PID > /dev/null 2>&1; then
        kill -9 $MAIN_PID 2>/dev/null
    fi
    echo -e "${GREEN}✓ Main runner script terminated${NC}"
fi

# Check for test benchmark scripts
TEST_SCRIPTS=$(ps aux | grep -E "test.*benchmark.*\.sh" | grep -v grep | awk '{print $2}')
if [ ! -z "$TEST_SCRIPTS" ]; then
    echo -e "${YELLOW}Found test benchmark scripts:${NC}"
    for pid in $TEST_SCRIPTS; do
        echo -e "  ${RED}PID $pid${NC}"
        kill -TERM $pid 2>/dev/null
    done
    sleep 1
    echo -e "${GREEN}✓ Test scripts terminated${NC}"
fi

# 2. Find all evalscope processes
echo ""
echo -e "${YELLOW}Looking for evalscope processes...${NC}"

# All possible benchmark names
BENCHMARKS=("aime24" "aime24-th" "hellaswag" "hellaswag-th" "humaneval" "humaneval-th"
            "ifeval" "ifeval-th" "math_500" "math_500-th" "code_switching"
            "live_code_bench" "live_code_bench-th" "openthaieval")

for benchmark in "${BENCHMARKS[@]}"; do
    PIDS=$(ps aux | grep "evalscope eval" | grep "datasets $benchmark" | grep -v grep | awk '{print $2}')

    if [ ! -z "$PIDS" ]; then
        for pid in $PIDS; do
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

# 3. Also check for processes using outputs directory
echo ""
echo -e "${YELLOW}Checking for processes using outputs directory...${NC}"

WORK_DIR_PIDS=$(ps aux | grep -E "work-dir.*outputs|outputs.*work-dir" | grep -v grep | awk '{print $2}')

for pid in $WORK_DIR_PIDS; do
    if [[ ! " ${PIDS_TO_KILL[@]} " =~ " ${pid} " ]]; then
        PROC_INFO=$(ps -p $pid -o pid,etime,args --no-headers 2>/dev/null)
        if [ ! -z "$PROC_INFO" ]; then
            ELAPSED=$(echo "$PROC_INFO" | awk '{print $2}')
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

# 4. Look for any other Python evalscope processes
echo ""
echo -e "${YELLOW}Checking for other evalscope/benchmark processes...${NC}"

OTHER_PIDS=$(ps aux | grep -E "python.*evalscope|python.*benchmark" | grep -v grep | awk '{print $2}')
for pid in $OTHER_PIDS; do
    if [[ ! " ${PIDS_TO_KILL[@]} " =~ " ${pid} " ]]; then
        echo -e "  ${RED}PID $pid${NC} - Python benchmark process"
        PIDS_TO_KILL+=($pid)
        ((TOTAL_FOUND++))
    fi
done

# 5. Kill all collected processes
if [ $TOTAL_FOUND -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Found $TOTAL_FOUND process(es) to terminate${NC}"
    echo -e "${YELLOW}Sending SIGTERM to all processes...${NC}"

    for pid in "${PIDS_TO_KILL[@]}"; do
        kill -TERM $pid 2>/dev/null
    done

    sleep 2

    # Check for survivors and force kill
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
    echo -e "${GREEN}No benchmark processes found running${NC}"
fi

# 6. Clean up background shell jobs
echo ""
echo -e "${YELLOW}Checking for background shell jobs...${NC}"

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

# 7. Clean up temporary files
echo ""
echo -e "${YELLOW}Cleaning up temporary files...${NC}"

if [ -d "./outputs" ]; then
    find ./outputs -name "*.pid" -type f -delete 2>/dev/null
    find ./outputs -name "*.lock" -type f -delete 2>/dev/null
    echo -e "${GREEN}✓ Cleaned up temporary files${NC}"
fi

# 8. Final verification
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}Final Status Check${NC}"
echo -e "${BLUE}=========================================${NC}"

# Check if any benchmark processes are still running
REMAINING=$(ps aux | grep -E "evalscope|benchmark" | grep -v grep | grep -v "kill_benchmarks" | wc -l)

if [ $REMAINING -eq 0 ]; then
    echo -e "${GREEN}✓ All benchmark processes successfully terminated!${NC}"
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
    echo -e "${RED}⚠ Warning: $REMAINING process(es) might still be running:${NC}"
    ps aux | grep -E "evalscope|benchmark" | grep -v grep | grep -v "kill_benchmarks"
    echo ""
    echo -e "${YELLOW}You may need to manually kill these with: kill -9 <PID>${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"