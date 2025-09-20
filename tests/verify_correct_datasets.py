#!/usr/bin/env python3
"""Verify correct dataset IDs and splits."""

from datasets import load_dataset

BENCHMARKS = [
    {
        'name': 'aime24-th',
        'dataset_id': 'iapp/aime_2024-th',
        'expected_split': 'train'
    },
    {
        'name': 'hellaswag-th',
        'dataset_id': 'Patt/HellaSwag_TH_cleanned',
        'expected_split': 'validation'
    },
    {
        'name': 'humaneval-th',
        'dataset_id': 'iapp/openai_humaneval-th',
        'expected_split': 'test'
    },
    {
        'name': 'ifeval-th',
        'dataset_id': 'scb10x/ifeval-th',
        'expected_split': 'train'
    },
    {
        'name': 'math_500-th',
        'dataset_id': 'iapp/math-500-th',
        'expected_split': 'test'
    }
]

print("Verifying correct Thai benchmark datasets...")
print("=" * 50)

all_ok = True
for benchmark in BENCHMARKS:
    print(f"\n{benchmark['name']}")
    print(f"  Dataset: {benchmark['dataset_id']}")

    try:
        # Try loading with expected split
        ds = load_dataset(benchmark['dataset_id'], split=benchmark['expected_split'])
        print(f"  ✓ Split '{benchmark['expected_split']}': {len(ds)} samples")
    except Exception as e:
        print(f"  ✗ Failed with split '{benchmark['expected_split']}': {str(e)[:100]}")
        all_ok = False

        # Try to find available splits
        try:
            ds_dict = load_dataset(benchmark['dataset_id'])
            print(f"  Available splits: {list(ds_dict.keys())}")
        except:
            print(f"  Dataset not accessible")

print("\n" + "=" * 50)
if all_ok:
    print("✅ All datasets verified successfully!")
else:
    print("⚠️ Some datasets need attention")