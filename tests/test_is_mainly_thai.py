#!/usr/bin/env python3
"""
Test the is_mainly_thai function with the user's example
"""

import sys
sys.path.insert(0, '/home/saiuser/kobkrit/chinda-eval')

from evalscope.benchmarks.code_switching.code_switching_adapter import is_mainly_thai

# User's example text that should be classified as mainly Thai
test_text = """ผมอยากลงทุนแบบ DCA ในกองทุน SSF และ RMF ครับ ผมมีเงินเดือน 50,000 บาท ควรแบ่งสัดส่วนการลงทุนอย่างไรดีครับ? และกองทุนไหนน่าสนใจบ้างในปี 2024 นี้"""

print(f"Testing text: {test_text}")
print(f"\nResult: is_mainly_thai = {is_mainly_thai(test_text)}")
print("\nExpected: True (this text is mainly Thai despite having English acronyms)")

# Test with pure Thai
pure_thai = "สวัสดีครับ วันนี้อากาศดีมาก"
print(f"\nPure Thai test: {pure_thai}")
print(f"Result: is_mainly_thai = {is_mainly_thai(pure_thai)}")

# Test with mostly English
mostly_english = "Hello, I want to invest in SSF and RMF funds. สวัสดี"
print(f"\nMostly English test: {mostly_english}")
print(f"Result: is_mainly_thai = {is_mainly_thai(mostly_english)}")

# Test with emojis
with_emoji = "สวัสดีครับ 😊 วันนี้อากาศดีมาก 🌞"
print(f"\nWith emoji test: {with_emoji}")
print(f"Result: is_mainly_thai = {is_mainly_thai(with_emoji)}")