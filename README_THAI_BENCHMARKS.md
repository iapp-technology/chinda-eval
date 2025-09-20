# Chinda Evaluation Framework - Thai & English LLM Benchmarks

A comprehensive evaluation framework for assessing Thai and English language models using EvalScope v2.0 with vLLM optimization.

## ✨ Key Features

- **9 Pre-configured Models**: Qwen3 (0.6B-32B), GPT-OSS (20B-120B), Qwen3-Next (80B)
- **12+ Benchmarks**: Thai and English versions of math, reasoning, code generation, and instruction following
- **Optimized Performance**: vLLM batching with 6-9x speedup through parallelization
- **Docker-based**: Easy deployment with pre-configured Docker compose files
- **Multi-GPU Support**: Automatic tensor parallelism (2-8 GPUs)
- **Comprehensive Results**: Automated scoring and reporting

## 🚀 Quick Start

### 1. Start vLLM Server (Docker)

#### Available Models
```bash
# GPT-OSS Models
docker compose -f dockers/docker-compose.gpt-oss-20b.yml up -d
docker compose -f dockers/docker-compose.gpt-oss-120b.yml up -d

# Qwen3 Models
docker compose -f dockers/docker-compose.chinda-qwen3-0.6b.yml up -d
docker compose -f dockers/docker-compose.chinda-qwen3-1.7b.yml up -d
docker compose -f dockers/docker-compose.chinda-qwen3-8b.yml up -d
docker compose -f dockers/docker-compose.chinda-qwen3-14b.yml up -d
docker compose -f dockers/docker-compose.chinda-qwen3-32b.yml up -d

# Qwen3-Next Models
docker compose -f dockers/docker-compose.qwen3-next-80b-instruct.yml up -d
docker compose -f dockers/docker-compose.qwen3-next-80b-thinking.yml up -d

# Check server status
curl http://localhost:8801/v1/models
```

### 2. Run Benchmarks

#### Multi-Model Evaluation (Recommended)
```bash
# Run all configured models with all benchmarks
./run_thai_benchmarks.sh

# Run specific models only
./run_thai_benchmarks.sh --models chinda-qwen3-0.6b chinda-qwen3-1.7b

# Run specific benchmarks only
./run_thai_benchmarks.sh --benchmarks aime24-th hellaswag-th math_500-th

# Combine model and benchmark selection
./run_thai_benchmarks.sh --models gpt-oss-20b --benchmarks aime24-th hellaswag-th

# Set custom sample limit (default: 1500)
./run_thai_benchmarks.sh --limit 100
```

#### Single Model - Parallel Execution
```bash
# Run 3 benchmarks concurrently - 6-9x speedup
./tests/test_thai_benchmarks_parallel.sh
```

#### Single Model - Sequential Execution
```bash
# Run benchmarks one by one - 2-3x speedup from batching
./tests/test_thai_benchmarks_sequence.sh
```

#### Test Single Benchmark
```bash
# Quick test with 10 samples
./tests/test_thai_single_benchmark.sh aime24-th
```

### 3. Monitor & Control

```bash
# Monitor GPU usage
watch -n 1 nvidia-smi

# Kill running benchmarks if needed
./kill_benchmarks.sh  # Kill all benchmark processes

# Stop vLLM server (replace with your model)
docker compose -f dockers/docker-compose.<model-name>.yml down
```

## 🤖 Available Models

| Model | Size | GPUs | Docker Compose File |
|-------|------|------|-------------------|
| **chinda-qwen3-0.6b** | 0.6B | 2 GPUs | `dockers/docker-compose.chinda-qwen3-0.6b.yml` |
| **chinda-qwen3-1.7b** | 1.7B | 2 GPUs | `dockers/docker-compose.chinda-qwen3-1.7b.yml` |
| **chinda-qwen3-8b** | 8B | 4 GPUs | `dockers/docker-compose.chinda-qwen3-8b.yml` |
| **chinda-qwen3-14b** | 14B | 8 GPUs | `dockers/docker-compose.chinda-qwen3-14b.yml` |
| **chinda-qwen3-32b** | 32B | 8 GPUs | `dockers/docker-compose.chinda-qwen3-32b.yml` |
| **gpt-oss-20b** | 20B | 4 GPUs | `dockers/docker-compose.gpt-oss-20b.yml` |
| **gpt-oss-120b** | 120B | 8 GPUs | `dockers/docker-compose.gpt-oss-120b.yml` |
| **qwen3-next-80b-instruct** | 80B | 8 GPUs | `dockers/docker-compose.qwen3-next-80b-instruct.yml` |
| **qwen3-next-80b-thinking** | 80B | 8 GPUs | `dockers/docker-compose.qwen3-next-80b-thinking.yml` |

## 📊 Available Thai Benchmarks

| Benchmark | Description | Dataset | Samples | Metrics |
|-----------|------------|---------|---------|---------|
| **aime24-th** | AIME 2024 math problems in Thai | `iapp/aime_2024-th` | 30 | Accuracy |
| **hellaswag-th** | Commonsense reasoning in Thai | `Patt/HellaSwag_TH_cleanned` | 5,034 | Accuracy |
| **ifeval-th** | Instruction following in Thai | `scb10x/ifeval-th` | 215 | Prompt/Inst level |
| **math_500-th** | 500 math problems in Thai | `iapp/math-500-th` | 500 | Accuracy |
| **code_switching** | Thai-English code switching | `iapp/code_switching` | 215 | Language Accuracy |
| **live_code_bench-th** | Code generation with execution (Thai) | `iapp/live_code_bench-th` | 200 | Pass@1 |
| **openthaieval** | Thai national exams (O-NET, TGAT) | `iapp/openthaieval` | 2,000+ | Accuracy |

### English Benchmarks
| Benchmark | Description | Dataset | Samples | Metrics |
|-----------|------------|---------|---------|---------|
| **aime24** | AIME 2024 math problems | `iapp/aime_2024` | 30 | Accuracy |
| **hellaswag** | Commonsense reasoning | `hellaswag` | 10,042 | Accuracy |
| **ifeval** | Instruction following | `google/IFEval` | 541 | Prompt/Inst level |
| **math_500** | 500 math problems | `iapp/math-500` | 500 | Accuracy |
| **live_code_bench** | Code generation with execution | `livecodebench/code_generation_lite` | 200 | Pass@1 |

## ⚡ Performance Optimizations

### vLLM Server Configuration
The Docker container is configured with optimizations for batch processing:

```yaml
# dockers/docker-compose.gptoss20b.yml optimizations
- --max-num-seqs=256           # Process 256 sequences concurrently
- --max-num-batched-tokens=32768  # Large batch size
- --enable-chunked-prefill      # Efficient long prompt handling
- --gpu-memory-utilization=0.9  # Use 90% GPU memory
```

### Execution Strategies

| Strategy | Script | Use Case |
|----------|--------|----------|
| **Multi-Model** | `run_thai_benchmarks.sh` | Evaluate multiple models systematically |
| **Parallel** | `tests/test_thai_benchmarks_parallel.sh` | Single model, maximum speed |
| **Sequential** | `tests/test_thai_benchmarks_sequence.sh` | Single model, stable execution |
| **Single** | `tests/test_thai_single_benchmark.sh` | Test individual benchmarks |

### How Speed Improvements Work

1. **Parallel Execution (3x speedup)**
   - Runs up to 3 benchmarks simultaneously
   - Each benchmark is a separate process
   - Maximizes GPU utilization

2. **vLLM Batching (2-3x speedup)**
   - Automatically batches multiple requests
   - Processes up to 256 sequences concurrently
   - Groups up to 32,768 tokens per batch

3. **Combined Effect (6-9x total speedup)**
   - Parallel + Batching = Multiplicative speedup
   - ~1-2 hours instead of 5-10 hours for full test suite

## 🏗️ Architecture

```
┌─────────────────────────┐
│  Chinda Eval Framework  │
│   (run_thai_benchmarks) │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│   Benchmark Runners     │
│  - Thai Benchmarks      │
│  - English Benchmarks   │
│  (evalscope eval)       │
└───────────┬─────────────┘
            │ OpenAI API
            ▼
┌─────────────────────────┐
│    vLLM Server          │
│  (Docker Container)     │
│    Port: 8801           │
└───────────┬─────────────┘
            │
┌───────────▼─────────────┐
│    Language Models      │
│  - Qwen3 (0.6B-32B)     │
│  - GPT-OSS (20B-120B)   │
│  - Qwen3-Next (80B)     │
│  Tensor Parallel=2-8    │
└─────────────────────────┘
```

## 🛠️ Setup Requirements

### Hardware
- **GPUs**: Varies by model (2-8 GPUs required)
  - Small models (0.6B-8B): 2-4 GPUs
  - Medium models (14B-32B): 4-8 GPUs
  - Large models (80B-120B): 8 GPUs
- **RAM**: 128GB+ recommended
- **Storage**: 100GB+ for models and results

### Software
- Docker & Docker Compose
- CUDA 12.0+
- Python 3.10+
- Conda environment: `chinda-eval`

### Models
All models are pre-configured in Docker compose files with appropriate:
- GPU allocation
- Memory settings
- Tensor parallelism
- Batch processing optimizations

## 📁 Project Structure

```
chinda-eval/
├── run_thai_benchmarks.sh          # Main multi-model benchmark runner
├── kill_benchmarks.sh              # Universal process killer
├── dockers/                        # Docker configurations
│   ├── docker-compose.chinda-qwen3-*.yml  # Qwen3 models
│   ├── docker-compose.gpt-oss-*.yml       # GPT-OSS models
│   └── docker-compose.qwen3-next-*.yml    # Qwen3-Next models
├── evalscope/                      # Core evaluation framework
│   └── benchmarks/                 # Benchmark adapters
│       ├── aime24/                 # English benchmarks
│       ├── aime24-th/              # Thai benchmarks
│       ├── code_switching/
│       ├── hellaswag/
│       ├── hellaswag-th/
│       ├── ifeval/
│       ├── ifeval-th/
│       ├── live_code_bench/
│       ├── live_code_bench-th/
│       ├── math_500/
│       ├── math_500-th/
│       └── openthaieval/
├── tests/                          # Test and utility scripts
│   ├── test_thai_benchmarks_parallel.sh
│   ├── test_thai_benchmarks_sequence.sh
│   ├── test_thai_single_benchmark.sh
│   ├── verify_benchmarks.py
│   ├── verify_datasets.py
│   └── verify_correct_datasets.py
└── outputs/                        # Benchmark results
    └── {model_name}/
        └── {benchmark_name}/
```

## 📝 Script Reference

### Main Runner Script
| Script | Purpose | Usage |
|--------|---------|-------|
| `run_thai_benchmarks.sh` | Run all models with all benchmarks | `./run_thai_benchmarks.sh` |

### Testing Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `tests/test_thai_benchmarks_parallel.sh` | Run benchmarks in parallel (single model) | `./tests/test_thai_benchmarks_parallel.sh` |
| `tests/test_thai_benchmarks_sequence.sh` | Run benchmarks sequentially | `./tests/test_thai_benchmarks_sequence.sh` |
| `tests/test_thai_single_benchmark.sh` | Test one benchmark | `./tests/test_thai_single_benchmark.sh <name>` |

### Control Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `kill_benchmarks.sh` | Stop all benchmark processes | `./kill_benchmarks.sh` |

### Utility Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `tests/verify_benchmarks.py` | Check benchmark registration | `python3 tests/verify_benchmarks.py` |
| `tests/verify_datasets.py` | Verify dataset availability | `python3 tests/verify_datasets.py` |
| `tests/verify_correct_datasets.py` | Check dataset configurations | `python3 tests/verify_correct_datasets.py` |

## 🔧 Configuration Details

### vLLM Server Settings
```bash
# Port configuration
API_URL="http://localhost:8801/v1"
MODEL_NAME="gpt-oss-20b"

# Request settings
MAX_NEW_TOKENS=16384
TIMEOUT=300  # seconds per request
LIMIT=1000   # samples per benchmark

# Parallel execution
MAX_PARALLEL=3  # concurrent benchmarks
```

### Dataset Splits
| Benchmark | Dataset ID | Split |
|-----------|------------|-------|
| aime24-th | iapp/aime_2024-th | train |
| hellaswag-th | Patt/HellaSwag_TH_cleanned | validation |
| humaneval-th | iapp/openai_humaneval-th | test |
| ifeval-th | scb10x/ifeval-th | train |
| math_500-th | iapp/math-500-th | test |

## 📈 Expected Performance

### Time Estimates (1000 samples per benchmark)
| Configuration | Time | Notes |
|--------------|------|-------|
| Sequential (no optimization) | 5-10 hours | Baseline |
| Sequential + vLLM batching | 2-4 hours | 2-3x speedup |
| Parallel + vLLM batching | 1-2 hours | 6-9x speedup |

### Resource Usage
- **GPU Memory**: ~60-70GB per GPU
- **GPU Utilization**: 80-95% with batching
- **CPU**: Moderate (higher with parallel execution)
- **Network**: Minimal (local API calls)

## 🐛 Troubleshooting

### Common Issues

#### Server Not Starting
```bash
# Check Docker logs
docker logs chinda-eval-vllm-server-gptoss-20b-1

# Restart server
docker compose -f dockers/docker-compose.gptoss20b.yml restart
```

#### Out of Memory
```bash
# Reduce batch size in dockers/docker-compose.gptoss20b.yml
- --max-num-seqs=128  # Reduce from 256
- --gpu-memory-utilization=0.8  # Reduce from 0.9
```

#### Benchmarks Hanging
```bash
# Kill stuck processes
./kill_benchmarks.sh

# Check for orphaned processes
ps aux | grep evalscope
```

#### Dataset Not Found
```bash
# Verify datasets are accessible
python3 tests/verify_correct_datasets.py

# Check HuggingFace login if needed
huggingface-cli login
```

## 📊 Results

Results are saved in `outputs/` with structure:
```
outputs/
├── aime24-th/
│   ├── output.log
│   ├── status.txt
│   ├── duration.txt
│   └── [timestamp]/
│       └── predictions/
├── hellaswag-th/
├── humaneval-th/
├── ifeval-th/
└── math_500-th/
```

### Viewing Results
```bash
# Check benchmark status
cat outputs/*/status.txt

# View summary reports
cat outputs/summary_report*.txt
cat outputs/parallel_summary_*.txt
```

## 🎯 GPT-OSS-20B Response Format

The model returns responses with reasoning and answer sections:
```json
{
  "content": [
    {"type": "reasoning", "reasoning": "Step-by-step thinking..."},
    {"type": "text", "text": "Final answer with \\boxed{answer}"}
  ]
}
```

The evaluation framework correctly extracts answers from the `text` field.

## 📚 Migration Notes

This project was migrated from the original evalscope to chinda-eval:
1. Updated all benchmark adapters to new API (`BenchmarkMeta`, `DefaultDataAdapter`)
2. Fixed dataset IDs and splits for Thai datasets
3. Configured vLLM server with GPT-OSS specific optimizations
4. Implemented parallel execution for faster testing
5. Added proper answer extraction for math problems (`\boxed{}` format)

## 🤝 Contributing

To add new Thai benchmarks:
1. Create adapter in `evalscope/benchmarks/<name>/`
2. Register with `@register_benchmark` decorator
3. Ensure correct dataset ID and split
4. Test with `./tests/test_thai_single_benchmark.sh <name>`

## 📄 License

This project uses:
- evalscope framework (Apache 2.0)
- GPT-OSS-20B model (check model license)
- Thai benchmark datasets (various licenses)

---

*Last updated: September 2025*
*Optimized for: GPT-OSS-20B with vLLM on H100 GPUs*