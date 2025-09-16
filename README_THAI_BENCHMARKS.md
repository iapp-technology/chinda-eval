# Thai Language Benchmarks with vLLM and GPT-OSS-20B

## 🚀 Quick Start

### 1. Start vLLM Server (Docker)
```bash
# Start optimized vLLM server with batching
docker compose -f docker-compose.gptoss20b.yml up -d

# Check server status
curl http://localhost:8801/v1/models
```

### 2. Run Benchmarks

#### For Maximum Speed (Parallel Execution)
```bash
# Run 3 benchmarks concurrently - 6-9x speedup
./test_thai_benchmarks_parallel.sh
```

#### For Stability (Sequential Execution)
```bash
# Run benchmarks one by one - 2-3x speedup from batching
./test_thai_benchmarks_sequence.sh
```

#### Test Single Benchmark
```bash
# Quick test with 10 samples
./test_thai_single_benchmark.sh aime24-th
```

### 3. Monitor & Control

```bash
# Monitor GPU usage
watch -n 1 nvidia-smi

# Kill running benchmarks if needed
./kill_parallel_benchmarks.sh  # Kill parallel execution only
./kill_all_benchmarks.sh       # Kill all benchmark processes

# Stop vLLM server
docker compose -f docker-compose.gptoss20b.yml down
```

## 📊 Available Thai Benchmarks

| Benchmark | Description | Dataset | Samples | Metrics |
|-----------|------------|---------|---------|---------|
| **aime24-th** | AIME 2024 math problems in Thai | `iapp/aime_2024-th` | 30 | Accuracy |
| **hellaswag-th** | Commonsense reasoning | `Patt/HellaSwag_TH_cleanned` | 5,034 | Accuracy |
| **humaneval-th** | Code generation | `iapp/openai_humaneval-th` | 164 | Pass@1 |
| **ifeval-th** | Instruction following | `scb10x/ifeval-th` | 215 | Prompt/Inst level |
| **math_500-th** | 500 math problems | `iapp/math-500-th` | 500 | Accuracy |

## ⚡ Performance Optimizations

### vLLM Server Configuration
The Docker container is configured with optimizations for batch processing:

```yaml
# docker-compose.gptoss20b.yml optimizations
- --max-num-seqs=256           # Process 256 sequences concurrently
- --max-num-batched-tokens=32768  # Large batch size
- --enable-chunked-prefill      # Efficient long prompt handling
- --gpu-memory-utilization=0.9  # Use 90% GPU memory
```

### Execution Strategies

| Strategy | Script | Speedup | Use Case |
|----------|--------|---------|----------|
| **Parallel** | `test_thai_benchmarks_parallel.sh` | 6-9x | Maximum speed, high resource usage |
| **Sequential** | `test_thai_benchmarks_sequence.sh` | 2-3x | Stable, lower resource usage |
| **Single** | `test_thai_single_benchmark.sh` | 1x | Testing individual benchmarks |

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
┌─────────────────────┐
│   Thai Benchmarks   │
│  (evalscope eval)   │
└──────────┬──────────┘
           │ OpenAI API
           ▼
┌─────────────────────┐
│   vLLM Server       │
│  (Docker Container) │
│   Port: 8801        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│   GPT-OSS-20B       │
│  4x H100 80GB GPUs  │
│  Tensor Parallel=4  │
└─────────────────────┘
```

## 🛠️ Setup Requirements

### Hardware
- **GPUs**: 4x H100 80GB (or equivalent)
- **RAM**: 128GB+ recommended
- **Storage**: 100GB+ for model and results

### Software
- Docker & Docker Compose
- CUDA 12.0+
- Python 3.10+
- Conda environment: `chinda-eval`

### Model
- **Model**: GPT-OSS-20B (20 billion parameters)
- **Location**: `/mnt/disk3/openai_gpt-oss-20b`
- **Format**: HuggingFace compatible

## 📁 Project Structure

```
chinda-eval/
├── docker-compose.gptoss20b.yml   # vLLM server configuration
├── evalscope/
│   └── benchmarks/                # Benchmark adapters
│       ├── aime24-th/
│       ├── hellaswag-th/
│       ├── humaneval-th/
│       ├── ifeval-th/
│       └── math_500-th/
├── thai_benchmark_results_api/    # Results directory
├── test_thai_benchmarks_parallel.sh  # Parallel execution
├── test_thai_benchmarks_sequence.sh   # Sequential execution
├── test_thai_single_benchmark.sh           # Single benchmark test
├── kill_parallel_benchmarks.sh        # Stop parallel tests
└── kill_all_benchmarks.sh            # Stop all tests
```

## 📝 Script Reference

### Testing Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `test_thai_benchmarks_parallel.sh` | Run benchmarks in parallel (fastest) | `./test_thai_benchmarks_parallel.sh` |
| `test_thai_benchmarks_sequence.sh` | Run benchmarks sequentially | `./test_thai_benchmarks_sequence.sh` |
| `test_thai_single_benchmark.sh` | Test one benchmark | `./test_thai_single_benchmark.sh <name>` |

### Control Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `kill_parallel_benchmarks.sh` | Stop parallel benchmark processes | `./kill_parallel_benchmarks.sh` |
| `kill_all_benchmarks.sh` | Stop all benchmark processes | `./kill_all_benchmarks.sh` |

### Utility Scripts
| Script | Purpose | Usage |
|--------|---------|-------|
| `verify_benchmarks.py` | Check benchmark registration | `python3 verify_benchmarks.py` |
| `verify_datasets.py` | Verify dataset availability | `python3 verify_datasets.py` |
| `verify_correct_datasets.py` | Check dataset configurations | `python3 verify_correct_datasets.py` |

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
docker compose -f docker-compose.gptoss20b.yml restart
```

#### Out of Memory
```bash
# Reduce batch size in docker-compose.gptoss20b.yml
- --max-num-seqs=128  # Reduce from 256
- --gpu-memory-utilization=0.8  # Reduce from 0.9
```

#### Benchmarks Hanging
```bash
# Kill stuck processes
./kill_all_benchmarks.sh

# Check for orphaned processes
ps aux | grep evalscope
```

#### Dataset Not Found
```bash
# Verify datasets are accessible
python3 verify_correct_datasets.py

# Check HuggingFace login if needed
huggingface-cli login
```

## 📊 Results

Results are saved in `thai_benchmark_results_api/` with structure:
```
thai_benchmark_results_api/
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
cat thai_benchmark_results_api/*/status.txt

# View summary reports
cat thai_benchmark_results_api/summary_report*.txt
cat thai_benchmark_results_api/parallel_summary_*.txt
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
4. Test with `./test_thai_single_benchmark.sh <name>`

## 📄 License

This project uses:
- evalscope framework (Apache 2.0)
- GPT-OSS-20B model (check model license)
- Thai benchmark datasets (various licenses)

---

*Last updated: September 2025*
*Optimized for: GPT-OSS-20B with vLLM on H100 GPUs*