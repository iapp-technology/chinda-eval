#!/usr/bin/env python3
"""
Verification script for Thai benchmarks in OpenThaiEval2
This script checks if all Thai benchmarks are properly registered and can be loaded.
"""

import sys
import os
import traceback

# Add the project root to Python path
sys.path.insert(0, '/home/saiuser/kobkrit/chinda-eval')

def verify_thai_benchmarks():
    """Verify that all Thai benchmarks are properly registered and loadable."""

    thai_benchmarks = [
        'aime24-th',
        'hellaswag-th',
        'humaneval-th',
        'ifeval-th',
        'math_500-th'
    ]

    print("=" * 60)
    print("Thai Benchmarks Verification")
    print("=" * 60)

    results = {}

    # Try to import each benchmark
    for benchmark_name in thai_benchmarks:
        try:
            print(f"\n{benchmark_name}:")

            # Convert benchmark name to module path
            module_name = benchmark_name.replace('-', '_')
            adapter_file = f"{module_name}_adapter"

            # Try to import the adapter
            module_path = f"evalscope.benchmarks.{benchmark_name}.{adapter_file}"
            print(f"  Attempting to import: {module_path}")

            import importlib
            module = importlib.import_module(module_path)

            print(f"  ✓ Module imported successfully")

            # Check if adapter class exists
            adapter_classes = [name for name in dir(module) if 'Adapter' in name]
            if adapter_classes:
                print(f"  ✓ Found adapter class: {adapter_classes[0]}")
                results[benchmark_name] = "SUCCESS"
            else:
                print(f"  ✗ No adapter class found")
                results[benchmark_name] = "NO_ADAPTER"

        except Exception as e:
            print(f"  ✗ ERROR: {str(e)}")
            results[benchmark_name] = f"ERROR: {str(e)}"

    # Print summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)

    successful = [k for k, v in results.items() if v == "SUCCESS"]
    failed = [k for k, v in results.items() if v != "SUCCESS"]

    print(f"\nSuccessful: {len(successful)}/{len(thai_benchmarks)}")
    if successful:
        for bench in successful:
            print(f"  ✓ {bench}")

    if failed:
        print(f"\nFailed: {len(failed)}/{len(thai_benchmarks)}")
        for bench in failed:
            print(f"  ✗ {bench}: {results[bench]}")

    return len(failed) == 0

if __name__ == "__main__":
    try:
        success = verify_thai_benchmarks()

        # Also test if evalscope benchmarks can be imported
        print("\n" + "-" * 40)
        print("Testing evalscope.benchmarks import...")
        try:
            import evalscope.benchmarks
            print("✓ evalscope.benchmarks imported successfully")
        except Exception as e:
            print(f"✗ Failed to import evalscope.benchmarks: {e}")
            success = False

        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"\nFATAL ERROR: {e}")
        traceback.print_exc()
        sys.exit(1)