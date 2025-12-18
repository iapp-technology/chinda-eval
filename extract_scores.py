#!/usr/bin/env python3
"""
Extract benchmark scores from evaluation outputs and generate a CSV summary.

Usage:
    python extract_scores.py <output_dir>

Example:
    python extract_scores.py outputs/OpenThaiGPT-ThaiLLM-8B-FullSFT-v2-20251214-200000-sft

Output:
    Creates score_summary_{model_name}.csv in the chinda-eval directory
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, Optional, Tuple


# Benchmark mappings: folder_name -> (display_name, metric_name or None for main score)
BENCHMARK_CONFIG = {
    'aime24': ('AIME24', None),
    'aime24-th': ('AIME24-TH', None),
    'code_switching': ('Language Accuracy (Code Switching)', None),
    'live_code_bench': ('LiveCodeBench', None),
    'live_code_bench-th': ('LiveCodeBench-TH', None),
    'math_500': ('MATH500', None),
    'math_500-th': ('MATH500-TH', None),
    'openthaieval': ('OpenThaiEval', None),
    'hellaswag': ('HellaSwag', None),
    'hellaswag-th': ('HellaSwag-TH', None),
    'ifeval': ('IFEval (inst_level_loose_acc)', 'mean_inst_level_loose'),
    'ifeval-th': ('IFEval-TH (inst_level_loose_acc)', 'mean_inst_level_loose'),
}

# Order of benchmarks in the output CSV
BENCHMARK_ORDER = [
    'aime24',
    'aime24-th',
    'code_switching',
    'live_code_bench',
    'live_code_bench-th',
    'math_500',
    'math_500-th',
    'openthaieval',
    'hellaswag',
    'hellaswag-th',
    'ifeval',
    'ifeval-th',
]


def find_json_file(benchmark_dir: Path, model_name: str, benchmark_name: str) -> Optional[Path]:
    """Find the JSON result file in the latest timestamp directory."""
    # JSON files are in: {benchmark_dir}/{timestamp}/reports/{model_name}/{benchmark_name}.json
    # Get all timestamp directories and sort to find the latest one
    timestamp_dirs = []
    for d in benchmark_dir.iterdir():
        if d.is_dir() and (d.name.isdigit() or '_' in d.name):
            timestamp_dirs.append(d)

    if not timestamp_dirs:
        return None

    # Sort by name (timestamp format YYYYMMDD_HHMMSS sorts correctly alphabetically)
    timestamp_dirs.sort(key=lambda x: x.name)

    # Use only the latest (last) timestamp directory
    latest_dir = timestamp_dirs[-1]
    json_path = latest_dir / 'reports' / model_name / f'{benchmark_name}.json'

    if json_path.exists():
        return json_path
    return None


def extract_score(json_path: Path, metric_name: Optional[str] = None) -> Optional[float]:
    """Extract the score from a JSON result file."""
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)

        if metric_name is None:
            # Use the main score
            return data.get('score')
        else:
            # Find the specific metric
            metrics = data.get('metrics', [])
            for metric in metrics:
                if metric.get('name') == metric_name:
                    score = metric.get('score')
                    # For IFEval metrics, the score might be 0 while actual score is in categories
                    # This happens when num=0 but macro_score has the correct value
                    if score == 0 and metric.get('num') == 0:
                        categories = metric.get('categories', [])
                        if categories:
                            # Get macro_score from categories (which contains the actual score)
                            category_score = categories[0].get('macro_score')
                            if category_score is not None and category_score > 0:
                                # Convert from percentage (0-100) to ratio (0-1)
                                return category_score / 100.0
                    return score
        return None
    except (json.JSONDecodeError, IOError) as e:
        print(f"Error reading {json_path}: {e}", file=sys.stderr)
        return None


def extract_all_scores(output_dir: Path) -> Tuple[str, Dict[str, Optional[float]]]:
    """Extract all benchmark scores from an output directory."""
    model_name = output_dir.name
    scores = {}

    for benchmark_folder, (display_name, metric_name) in BENCHMARK_CONFIG.items():
        benchmark_dir = output_dir / benchmark_folder

        if not benchmark_dir.exists():
            print(f"Warning: Benchmark directory not found: {benchmark_dir}", file=sys.stderr)
            scores[benchmark_folder] = None
            continue

        json_path = find_json_file(benchmark_dir, model_name, benchmark_folder)

        if json_path is None:
            print(f"Warning: JSON file not found for {benchmark_folder}", file=sys.stderr)
            scores[benchmark_folder] = None
            continue

        score = extract_score(json_path, metric_name)
        scores[benchmark_folder] = score

    return model_name, scores


def generate_csv(model_name: str, scores: Dict[str, Optional[float]], output_path: Path):
    """Generate the CSV summary file."""
    lines = []
    lines.append(f"Benchmarks,{model_name}")

    valid_scores = []

    for benchmark_folder in BENCHMARK_ORDER:
        display_name, _ = BENCHMARK_CONFIG[benchmark_folder]
        score = scores.get(benchmark_folder)

        if score is not None:
            # Round to 4 decimal places
            score_str = f"{score:.4f}"
            lines.append(f"{display_name},{score_str}")
            valid_scores.append(score)
        else:
            lines.append(f"{display_name},N/A")

    # Calculate and add average
    if valid_scores:
        avg = sum(valid_scores) / len(valid_scores)
        lines.append(f"AVERAGE,{avg:.10f}")
    else:
        lines.append("AVERAGE,N/A")

    # Write to file
    with open(output_path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    print(f"CSV saved to: {output_path}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python extract_scores.py <output_dir>", file=sys.stderr)
        print("Example: python extract_scores.py outputs/OpenThaiGPT-ThaiLLM-8B-FullSFT-v2-20251214-200000-sft", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(sys.argv[1])

    if not output_dir.exists():
        print(f"Error: Directory not found: {output_dir}", file=sys.stderr)
        sys.exit(1)

    if not output_dir.is_dir():
        print(f"Error: Not a directory: {output_dir}", file=sys.stderr)
        sys.exit(1)

    # Extract scores
    model_name, scores = extract_all_scores(output_dir)

    # Determine output path
    script_dir = Path(__file__).parent
    output_csv = script_dir / f"score_summary_{model_name}.csv"

    # Generate CSV
    generate_csv(model_name, scores, output_csv)

    # Print summary
    print(f"\nSummary for {model_name}:")
    print("-" * 50)
    for benchmark_folder in BENCHMARK_ORDER:
        display_name, _ = BENCHMARK_CONFIG[benchmark_folder]
        score = scores.get(benchmark_folder)
        if score is not None:
            print(f"{display_name}: {score:.4f}")
        else:
            print(f"{display_name}: N/A")

    # Print scores only (for Excel copy-paste)
    print("\n" + "=" * 50)
    print("Scores only (for Excel copy-paste):")
    print("=" * 50)
    for benchmark_folder in BENCHMARK_ORDER:
        score = scores.get(benchmark_folder)
        if score is not None:
            print(f"{score:.4f}")
        else:
            print("N/A")

    # Print average
    valid_scores = [s for s in scores.values() if s is not None]
    if valid_scores:
        avg = sum(valid_scores) / len(valid_scores)
        print(f"{avg:.10f}")


if __name__ == '__main__':
    main()
