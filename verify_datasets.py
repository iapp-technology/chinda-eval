#!/usr/bin/env python3
"""Verify all Thai benchmark datasets can be loaded."""

from datasets import load_dataset

BENCHMARKS = [
    {
        'name': 'aime24-th',
        'dataset_id': 'scb10x/aime24-th',
        'split': 'test'
    },
    {
        'name': 'hellaswag-th',
        'dataset_id': 'scb10x/hellaswag_thai',
        'split': 'validation'
    },
    {
        'name': 'humaneval-th',
        'dataset_id': 'iapp/openai_humaneval-th',
        'split': 'test'
    },
    {
        'name': 'ifeval-th',
        'dataset_id': 'scb10x/ifeval-th',
        'split': 'test'
    },
    {
        'name': 'math_500-th',
        'dataset_id': 'scb10x/math_500-th',
        'split': 'test'
    }
]

print("Verifying Thai benchmark datasets...")
print("=" * 50)

for benchmark in BENCHMARKS:
    print(f"\nBenchmark: {benchmark['name']}")
    print(f"Dataset ID: {benchmark['dataset_id']}")
    print(f"Expected split: {benchmark['split']}")

    try:
        # Try loading with specified split
        ds = load_dataset(benchmark['dataset_id'], split=benchmark['split'])
        print(f"✓ Successfully loaded with split='{benchmark['split']}'")
        print(f"  Number of samples: {len(ds)}")
        if len(ds) > 0:
            print(f"  Sample keys: {list(ds[0].keys())[:5]}")
    except Exception as e:
        print(f"✗ Failed with split='{benchmark['split']}': {e}")

        # Try loading without split to see available ones
        try:
            ds_dict = load_dataset(benchmark['dataset_id'])
            print(f"  Available splits: {list(ds_dict.keys())}")

            # Try each available split
            for split_name in ds_dict.keys():
                print(f"  Split '{split_name}' has {len(ds_dict[split_name])} samples")
        except Exception as e2:
            print(f"  ✗ Dataset not found or inaccessible: {e2}")

print("\n" + "=" * 50)
print("Verification complete!")