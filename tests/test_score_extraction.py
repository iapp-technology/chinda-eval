#!/usr/bin/env python3
import json
import os

def extract_score(benchmark, model_name):
    """Extract score from benchmark results"""
    base_dir = "thai_benchmark_results_api"
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

# Test the extraction
model = "gpt-oss-20b"
benchmarks = [
    "aime24",
    "aime24-th",
    "code_switching",
    "live_code_bench",
    "live_code_bench-th",
    "math_500",
    "math_500-th",
    "openthaieval",
    "hellaswag",
    "hellaswag-th",
    "ifeval",
    "ifeval-th"
]

print(f"Score Summary for {model}:")
print("-" * 50)
scores = []
for bench in benchmarks:
    score = extract_score(bench, model)
    print(f"{bench:30} {score}")
    if score != "N/A":
        try:
            scores.append(float(score))
        except:
            pass

if scores:
    avg = sum(scores) / len(scores)
    print("-" * 50)
    print(f"{'AVERAGE':30} {avg:.2f}")
else:
    print("-" * 50)
    print(f"{'AVERAGE':30} N/A")