#!/usr/bin/env python3
import json
import os
import sys

def extract_score(benchmark, model_name, base_dir="thai_benchmark_results_api"):
    """Extract score from benchmark results"""
    bench_dir = f"{base_dir}/{model_name}/{benchmark}"

    # Look for the latest report JSON file
    report_file = None
    if os.path.isdir(bench_dir):
        for root, dirs, files in os.walk(bench_dir):
            if 'reports' in root:
                for file in files:
                    if file.endswith('.json'):
                        report_file = os.path.join(root, file)
                        break

    if not report_file or not os.path.exists(report_file):
        return "N/A"

    try:
        with open(report_file) as f:
            data = json.load(f)

        if benchmark == "code_switching":
            for metric in data.get('metrics', []):
                if 'language_accuracy' in metric.get('name', ''):
                    return metric.get('score', 'N/A')
            return data.get('score', 'N/A')

        elif benchmark in ["ifeval-th", "ifeval"]:
            for metric in data.get('metrics', []):
                if 'inst_level_loose' in metric.get('name', ''):
                    # Try to get the actual score from subsets if main score is 0
                    if metric.get('score', 0) == 0 and metric.get('categories'):
                        for cat in metric['categories']:
                            if cat.get('subsets'):
                                for subset in cat['subsets']:
                                    if subset.get('score', 0) != 0:
                                        return subset['score']
                    return metric.get('score', 'N/A')
            return data.get('score', 'N/A')

        elif benchmark in ["live_code_bench", "live_code_bench-th"]:
            for metric in data.get('metrics', []):
                if 'exact_match' in metric.get('name', '') or 'pass@1' in metric.get('name', '') or 'pass' in metric.get('name', ''):
                    return metric.get('score', 'N/A')
            return data.get('score', 'N/A')

        else:  # Default case
            for metric in data.get('metrics', []):
                if 'mean_acc' in metric.get('name', '') or 'accuracy' in metric.get('name', ''):
                    return metric.get('score', 'N/A')
            return data.get('score', 'N/A')

    except Exception as e:
        print(f"Error reading {report_file}: {e}")
        return "N/A"

def generate_score_summary(model_name, base_dir="thai_benchmark_results_api"):
    """Generate score summary CSV for a model"""
    output_dir = f"{base_dir}/{model_name}"
    csv_file = f"{output_dir}/score_summary.csv"

    scores = []
    lines = []

    lines.append(f"Benchmarks,{model_name}")

    # Extract scores for each benchmark
    benchmarks = [
        ("AIME24", "aime24"),
        ("AIME24-TH", "aime24-th"),
        ("Language Accuracy (Code Switching)", "code_switching"),
        ("LiveCodeBench", "live_code_bench"),
        ("LiveCodeBench-TH", "live_code_bench-th"),
        ("MATH500", "math_500"),
        ("MATH500-TH", "math_500-th"),
        ("OpenThaiEval", "openthaieval"),
        ("HellaSwag", "hellaswag"),
        ("HellaSwag-TH", "hellaswag-th"),
        ("IFEval (inst_level_loose_acc)", "ifeval"),
        ("IFEval-TH (inst_level_loose_acc)", "ifeval-th")
    ]

    for name, bench in benchmarks:
        score = extract_score(bench, model_name, base_dir)
        lines.append(f"{name},{score}")
        if score != "N/A":
            try:
                # Convert percentage scores (like IFEval-TH's 60.0) to decimal
                score_val = float(score)
                if bench == "ifeval-th" and score_val > 1:
                    score_val = score_val / 100.0
                scores.append(score_val)
            except:
                pass

    # Calculate average
    if scores:
        avg = sum(scores) / len(scores)
        lines.append(f"AVERAGE,{avg:.4f}")
    else:
        lines.append("AVERAGE,N/A")

    # Write to CSV
    with open(csv_file, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    print(f"Score summary saved to {csv_file}")
    print("\nScore Summary:")
    print("-" * 50)
    for line in lines:
        parts = line.split(',')
        if len(parts) == 2:
            print(f"{parts[0]:35} {parts[1]:>10}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        model_name = sys.argv[1]
    else:
        model_name = "gpt-oss-20b"

    generate_score_summary(model_name)