#!/usr/bin/env python3
"""
Test code extraction with gpt-oss-120b's verbose output
"""

import sys
sys.path.insert(0, '/home/saiuser/kobkrit/chinda-eval')

from evalscope.benchmarks.live_code_bench.extract_utils import extract_code_generation
from evalscope.benchmarks.utils import extract_code_block

# Example of gpt-oss-120b's verbose output with multiple code blocks
test_output = """
**Solution Explanation**

For every test case we are given  
* `n` – length of the array
* `k` – a small integer

In one operation we may increase any element by `1`.  
We have to obtain the smallest possible number of operations.

#### Algorithm
```
best = 0
for i = 0 … n-1                     # i – the digit we increase
        prod = 1
        for j = 0 … n-1
                if j == i
                        prod *= a[j] + 1
                else
                        prod *= a[j]
        best = max(best, prod)
output best
```

The product fits easily into Python's arbitrary length integers.

#### Reference Implementation  (Python 3)

```python
import sys

def solve() -> None:
    data = list(map(int, sys.stdin.read().split()))
    it = iter(data)
    t = next(it)
    out_lines = []
    for _ in range(t):
        n = next(it)
        a = [next(it) for _ in range(n)]
        best = 0
        for i in range(n):
            prod = 1
            for j in range(n):
                if j == i:
                    prod *= a[j] + 1
                else:
                    prod *= a[j]
            if prod > best:
                best = prod
        out_lines.append(str(best))
    sys.stdout.write("\\n".join(out_lines))

if __name__ == "__main__":
    solve()
```

The program follows exactly the algorithm proven correct above.
"""

print("Testing code extraction from verbose gpt-oss-120b output...\n")

# Test with extract_code_generation
print("Using extract_code_generation:")
print("=" * 50)
extracted1 = extract_code_generation(test_output)
print(extracted1[:200] if len(extracted1) > 200 else extracted1)
print("\n" + "=" * 50)
print(f"Extracted length: {len(extracted1)} characters")
print(f"Starts with 'import': {extracted1.strip().startswith('import')}")

# Test with extract_code_block
print("\nUsing extract_code_block:")
print("=" * 50)
extracted2 = extract_code_block(test_output)
print(extracted2[:200] if len(extracted2) > 200 else extracted2)
print("\n" + "=" * 50)
print(f"Extracted length: {len(extracted2)} characters")
print(f"Starts with 'import': {extracted2.strip().startswith('import')}")

# Check if we got the actual implementation instead of pseudocode
if "import sys" in extracted1:
    print("\n✓ SUCCESS: Extracted actual Python implementation (not pseudocode)")
else:
    print("\n✗ FAILED: Extracted pseudocode instead of implementation")

if "import sys" in extracted2:
    print("✓ SUCCESS: extract_code_block also got the implementation")
else:
    print("✗ FAILED: extract_code_block got pseudocode")