# Multi-Model Evaluation Guide

## Overview
The multi-model evaluation system automatically manages vLLM servers and evaluates multiple models sequentially on all Thai and English benchmarks.

## Models Configured

1. **GPT-OSS-20B** (`/mnt/disk3/openai_gpt-oss-20b`)
   - Tensor Parallel: 4 GPUs
   - Max Length: 16,384 tokens

2. **GPT-OSS-120B** (`/mnt/disk3/openai_gpt-oss-120b`)
   - Tensor Parallel: 8 GPUs
   - Max Length: 16,384 tokens

3. **Qwen3-Next-80B-A3B-Instruct** (`/mnt/disk3/Qwen_Qwen3-Next-80B-A3B-Instruct`)
   - Tensor Parallel: 8 GPUs
   - Max Length: 32,768 tokens

4. **Qwen3-Next-80B-A3B-Thinking** (`/mnt/disk3/Qwen_Qwen3-Next-80B-A3B-Thinking`)
   - Tensor Parallel: 8 GPUs
   - Max Length: 32,768 tokens

## Usage

### Run Multi-Model Evaluation
```bash
# Evaluate all 4 models sequentially
./test_thai_benchmarks_multi_model.sh
```

### Run Single Model Evaluation
```bash
# Default model (gpt-oss-20b) with 1 sample
./test_thai_benchmarks_parallel.sh

# Specific model with custom sample size
./test_thai_benchmarks_parallel.sh gpt-oss-120b 100

# Multi-model mode via parallel script
./test_thai_benchmarks_parallel.sh --multi-model
```

## Features

### Automatic Server Management
- Automatically starts vLLM server for each model
- Configures appropriate GPU allocation and memory settings
- Stops server after model evaluation completes
- Handles server cleanup between models

### Parallel Benchmark Execution
- Runs up to 3 benchmarks concurrently per model
- Optimizes evaluation time while managing system resources
- Tracks individual benchmark progress and status

### Score Summary Generation
- Generates `score_summary.csv` for each model
- Calculates average scores across all benchmarks
- Creates combined comparison report for all models

## Output Structure

```
thai_benchmark_results_api/
├── gpt-oss-20b/
│   ├── aime24/
│   ├── aime24-th/
│   ├── ...
│   └── score_summary.csv
├── gpt-oss-120b/
│   ├── aime24/
│   ├── ...
│   └── score_summary.csv
├── qwen3-next-80b-instruct/
│   └── ...
├── qwen3-next-80b-thinking/
│   └── ...
└── multi_model_evaluation_YYYYMMDD_HHMMSS.txt
```

## Benchmarks Evaluated

### Thai Benchmarks
- AIME24-TH (Thai mathematical reasoning)
- HellaSwag-TH (Thai commonsense reasoning)
- IFEval-TH (Thai instruction following)
- MATH500-TH (Thai mathematics)
- Code Switching (Thai-English language accuracy)
- LiveCodeBench-TH (Thai code generation)
- OpenThaiEval (Thai general evaluation)

### English Benchmarks
- AIME24 (Mathematical reasoning)
- HellaSwag (Commonsense reasoning)
- IFEval (Instruction following)
- MATH500 (Mathematics)
- LiveCodeBench (Code generation)

## Score Summary Format

Each model's `score_summary.csv` contains:
```csv
Benchmarks,model_name
AIME24,0.0667
AIME24-TH,0.0333
Language Accuracy (Code Switching),0.938
LiveCodeBench,0.2114
LiveCodeBench-TH,0.0811
MATH500,0.674
MATH500-TH,0.504
OpenThaiEval,0.45
HellaSwag,0.4733
HellaSwag-TH,0.3103
IFEval (inst_level_loose_acc),0.6811
IFEval-TH (inst_level_loose_acc),0.6275
AVERAGE,0.4208
```

## Requirements

- Docker and Docker Compose
- NVIDIA GPUs (8 GPUs recommended for large models)
- Conda environment: `chinda-eval`
- vLLM Docker image
- Sufficient disk space for model outputs

## Monitoring

During execution:
- Real-time status updates for each benchmark
- Color-coded messages for easy tracking
- Automatic error reporting with log excerpts
- Progress indicators for server startup

## Troubleshooting

### Server Won't Start
- Check Docker is running: `docker ps`
- Verify GPU availability: `nvidia-smi`
- Check port 8801 is free: `lsof -i:8801`

### Benchmark Failures
- Check individual logs: `thai_benchmark_results_api/{model}/{benchmark}/output.log`
- Verify model path exists
- Ensure sufficient GPU memory

### Cleanup
If interrupted, clean up Docker containers:
```bash
docker ps -q --filter "name=vllm" | xargs -r docker stop
docker ps -aq --filter "name=vllm" | xargs -r docker rm
```