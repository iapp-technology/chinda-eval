# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Chinda-Eval is a Thai LLM evaluation framework built on EvalScope v2.0. It provides comprehensive benchmarks for evaluating Thai language models through API-based evaluation with vLLM backends.

## Common Commands

### Installation
```bash
# Create environment and install
conda create -n chinda-eval python=3.10
conda activate chinda-eval
pip install -e .

# Development install with extras
pip install -e '.[dev,perf,docs]'
```

### Running Evaluations

```bash
# CLI evaluation (primary method)
evalscope eval \
    --model MODEL_NAME \
    --api-url http://localhost:8801/v1/chat/completions \
    --api-key EMPTY \
    --eval-type openai_api \
    --datasets aime24-th hellaswag-th math_500-th \
    --dataset-hub huggingface \
    --limit 100

# Parallel benchmark execution for single model
./tests/test_thai_benchmarks_parallel.sh MODEL_NAME MAX_SAMPLES

# Parallel 4-model evaluation (runs 4 models simultaneously)
./run_thai_benchmarks_parallel_4models.sh --benchmarks aime24-th math_500-th --limit 100
```

### vLLM Server Management
```bash
# Start/stop model servers (in dockers/ directory)
./dockers/start_chinda_qwen3_8b_vllm_docker.sh
./dockers/stop_chinda_qwen3_8b_vllm_docker.sh

# Or via docker-compose directly
docker compose -f dockers/docker-compose.chinda-qwen3-8b.yml up -d
```

### Development
```bash
make lint          # Run pre-commit hooks
make docs          # Generate documentation
make install       # Install package
```

## Architecture

### Core Evaluation Flow
```
evalscope CLI (evalscope/cli/start_eval.py)
    → TaskConfig (evalscope/config.py)
    → run_task() (evalscope/run.py)
    → Benchmark adapter loaded via registry
    → DefaultEvaluator runs inference loop
    → Reports generated in work_dir/
```

### Key Directories

- **`evalscope/benchmarks/`** - Benchmark adapters (60+ benchmarks)
- **`evalscope/api/`** - Core abstractions (benchmark, model, metric, evaluator interfaces)
- **`evalscope/models/`** - Model implementations (OpenAI API, ModelScope, etc.)
- **`evalscope/evaluator/`** - Evaluation execution logic
- **`dockers/`** - Docker compose files for vLLM servers
- **`outputs/`** - Evaluation results (created at runtime)

### Thai Benchmarks

Located in `evalscope/benchmarks/` with `-th` suffix:

| Benchmark | Dataset ID | Domain |
|-----------|------------|--------|
| `aime24-th` | iapp/aime_2024-th | Math |
| `hellaswag-th` | Patt/HellaSwag-th | Reasoning |
| `humaneval-th` | iapp/humaneval-th | Code |
| `ifeval-th` | iapp/ifeval-th | Instruction Following |
| `math_500-th` | iapp/math_500-th | Math |
| `live_code_bench-th` | iapp/live_code_bench-th | Code |
| `openthaieval` | scb10x/openthaieval | Thai National Exams |
| `code_switching` | iapp/thai_english_code_switching | Language Mixing |

### Benchmark Adapter Pattern

Each adapter uses the `@register_benchmark` decorator:

```python
@register_benchmark(
    BenchmarkMeta(
        name='benchmark-th',
        dataset_id='org/dataset-name',
        metric_list=[{'acc': {'numeric': True}}],
        prompt_template='...',
        ...
    )
)
class BenchmarkThAdapter(DefaultDataAdapter):
    def record_to_sample(self, record: Dict) -> Sample:
        # Convert dataset record to Sample

    def extract_answer(self, prediction: str, task_state: TaskState) -> str:
        # Extract answer from model output
```

### Model Configuration

Models are served via vLLM with OpenAI-compatible API. Port assignments:
- 8804: chinda-qwen3-4b
- 8808: chinda-qwen3-8b
- 8814: chinda-qwen3-14b
- 8832: chinda-qwen3-32b
- 8801: default/gpt-oss models

### Generation Config

Default generation settings used in evaluation:
```json
{"do_sample": false, "temperature": 0.0, "max_new_tokens": 32768}
```

## Output Structure

Results are saved to `outputs/{model_name}/{benchmark}/`:
- `reports/` - JSON score reports
- `reviews/` - Detailed sample reviews
- `output.log` - Execution logs
- `score_summary.csv` - Aggregated scores
