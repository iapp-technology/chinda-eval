"""
Code Switching Benchmark Adapter
Thai-English code switching evaluation using WangchanThaiInstruct dataset
"""

import re
from typing import Any, Dict

from evalscope.api.benchmark import BenchmarkMeta, DefaultDataAdapter
from evalscope.api.dataset import Sample
from evalscope.api.evaluator import TaskState
from evalscope.api.metric import Score
from evalscope.api.registry import register_benchmark
from evalscope.constants import Tags
from evalscope.utils.logger import get_logger

logger = get_logger()


def is_mainly_thai(response: str) -> bool:
    """
    Check if a response is mainly in Thai language.
    Based on the logic from SkyThought code_switching_handler.py

    Args:
        response: The text response to check

    Returns:
        bool: True if the response is mainly in Thai, False otherwise
    """
    # Remove everything before </think> if present (for thinking models)
    response = re.sub(r'^.*?</think>', '', response, flags=re.DOTALL)

    # Thai character ranges (based on Unicode blocks)
    thai_ranges = [
        (0x0E00, 0x0E7F),  # Thai
    ]

    # ASCII characters (English)
    english_ranges = [
        (0x0041, 0x005A),  # Uppercase A-Z
        (0x0061, 0x007A),  # Lowercase a-z
    ]

    # Digits (0-9)
    digit_range = (0x0030, 0x0039)

    # Allowed symbols (that don't count against being Thai)
    allowed_symbols = set()

    # Basic ASCII punctuation
    for c in ",.;:!?()[]{}'\"-_+=*/\\<>@#$%^&|~`®":
        allowed_symbols.add(c)

    # Whitespace
    for c in " \t\n\r\f\v":
        allowed_symbols.add(c)

    # Mathematical symbols
    for i in range(0x2200, 0x22FF + 1):  # Mathematical Operators
        allowed_symbols.add(chr(i))
    for i in range(0x27C0, 0x27EF + 1):  # Miscellaneous Mathematical Symbols-A
        allowed_symbols.add(chr(i))
    for i in range(0x2980, 0x29FF + 1):  # Miscellaneous Mathematical Symbols-B
        allowed_symbols.add(chr(i))

    # Latin with diacritics (for names, brands, etc.)
    for i in range(0x00C0, 0x00FF + 1):  # Latin-1 Supplement
        allowed_symbols.add(chr(i))
    for i in range(0x0100, 0x017F + 1):  # Latin Extended-A
        allowed_symbols.add(chr(i))
    for i in range(0x0180, 0x024F + 1):  # Latin Extended-B
        allowed_symbols.add(chr(i))

    # Quotes and punctuation
    for i in range(0x2000, 0x206F + 1):  # General Punctuation
        allowed_symbols.add(chr(i))

    # Emoji ranges
    emoji_ranges = [
        (0x1F300, 0x1F5FF),  # Miscellaneous Symbols and Pictographs
        (0x1F600, 0x1F64F),  # Emoticons
        (0x1F680, 0x1F6FF),  # Transport and Map Symbols
        (0x1F700, 0x1F77F),  # Alchemical Symbols
        (0x1F780, 0x1F7FF),  # Geometric Shapes Extended
        (0x1F800, 0x1F8FF),  # Supplemental Arrows-C
        (0x1F900, 0x1F9FF),  # Supplemental Symbols and Pictographs
        (0x1FA00, 0x1FA6F),  # Chess Symbols
        (0x1FA70, 0x1FAFF),  # Symbols and Pictographs Extended-A
        (0x2600, 0x26FF),    # Miscellaneous Symbols
        (0x2700, 0x27BF),    # Dingbats
        (0x1F1E6, 0x1F1FF),  # Regional Indicator Symbols (for flags)
    ]

    for start, end in emoji_ranges:
        for i in range(start, end + 1):
            try:
                allowed_symbols.add(chr(i))
            except ValueError:
                pass  # Skip if the code point is not valid

    # Trademark and registered symbols
    allowed_symbols.update(['©', '™', '®'])

    # Currency symbols
    allowed_symbols.update(['€', '£', '¥', '₹', '₩', '₺', '₴', '₦', '₱', '₲', '₵', '₸'])

    # Superscripts
    allowed_symbols.update(['²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹', '⁰', '⁻', '⁺', '⁼', '⁽', '⁾', 'ⁿ', 'ⁱ'])

    # Arrows
    allowed_symbols.update(['→', '←', '↑', '↓', '↔', '↕', '↖', '↗', '↘', '↙', '↩', '↪', '↻', '↼', '↽', '↾', '↿',
                           '⇀', '⇁', '⇂', '⇃', '⇄', '⇅', '⇆', '⇇', '⇈', '⇉', '⇊', '⇋', '⇌', '⇍', '⇎', '⇏',
                           '⇐', '⇑', '⇒', '⇓', '⇔', '⇕', '⇖', '⇗', '⇘', '⇙', '⇚', '⇛', '⇜', '⇝', '⇞', '⇟',
                           '⇠', '⇡', '⇢', '⇣', '⇤', '⇥', '⇦', '⇧', '⇨', '⇩', '⇪', '⇫', '⇬', '⇭', '⇮', '⇯',
                           '⇰', '⇱', '⇲', '⇳', '⇴', '⇵', '⇶', '⇷', '⇸', '⇹', '⇺', '⇻', '⇼', '⇽', '⇾', '⇿',
                           '⟀', '⟁'])

    # Math symbols
    allowed_symbols.update(['∈', '∉', '∊', '∋', '∌', '∀', '∁', '∂', '∃', '∄', '∅', '∆', '∇',
                           '½', '⅓', '⅔', '¼', '¾', '⅛', '⅜', '⅝', '⅞', '⅑', '⅒', '⅕'])

    # Initialize counters
    thai_count = 0
    english_count = 0
    other_chars = set()

    for char in response:
        # Check if the character is Thai
        is_thai = any(start <= ord(char) <= end for start, end in thai_ranges)
        if is_thai:
            thai_count += 1
            continue

        # Check if it's a digit (classify as allowed, not English)
        is_digit = digit_range[0] <= ord(char) <= digit_range[1]
        if is_digit:
            # Don't count digits for or against being Thai
            continue

        # Check if the character is in allowed symbols
        if char in allowed_symbols:
            # Don't count these symbols for or against being Thai
            continue

        # Check if it's English
        is_english = any(start <= ord(char) <= end for start, end in english_ranges)
        if is_english:
            english_count += 1
            continue

        # If not Thai, digit, allowed symbol, or English, it's another language
        other_chars.add(char)

    # If there are characters from other languages (not Thai/English/allowed), it's not mainly Thai
    if other_chars:
        logger.debug(f"Found non-Thai/English characters: {other_chars}")
        return False

    # If there are more English characters than Thai, it's not mainly Thai
    if english_count > thai_count:
        logger.debug(f"English count ({english_count}) > Thai count ({thai_count})")
        return False

    logger.debug(f"Thai count: {thai_count}, English count: {english_count}")
    return True


@register_benchmark(
    BenchmarkMeta(
        name='code_switching',
        pretty_name='Code-Switching-Thai-English',
        tags=[Tags.QA],
        description='Thai-English code switching evaluation benchmark using WangchanThaiInstruct dataset. Tests the model\'s ability to understand and generate mixed Thai-English text, with responses expected to be primarily in Thai.',
        dataset_id='airesearch/WangchanThaiInstruct',
        subset_list=['default'],
        extra_params={'dataset_hub': 'huggingface'},
        metric_list=[{'accuracy': {}}],
        few_shot_num=0,
        train_split='train',
        eval_split='train',  # Using train split as specified in yaml
        prompt_template='{question}'
    )
)
class CodeSwitchingAdapter(DefaultDataAdapter):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Set max samples as specified in yaml
        self.max_samples = 500
        self.max_prompt_char_length = 10000

    def record_to_sample(self, record: Dict[str, Any]) -> Sample:
        """Convert dataset record to evaluation sample."""
        # Keys from yaml: question_key: Instruction, answer_key: Output
        instruction = record.get('Instruction', '')
        output = record.get('Output', '')
        input_text = record.get('Input', '')

        # Combine instruction and input if input exists
        if input_text:
            prompt = f"{instruction}\n\n{input_text}"
        else:
            prompt = instruction

        # Apply prompt length limit as specified in yaml
        if len(prompt) > self.max_prompt_char_length:
            prompt = prompt[:self.max_prompt_char_length]

        return Sample(
            input=prompt,
            target=output,  # Store the expected output for reference
            metadata={
                'instruction': instruction,
                'input': input_text,
                'output': output,
                'domain': record.get('Domain', ''),
                'task_type': record.get('Task_type', ''),
            }
        )

    def extract_answer(self, prediction: str, task_state: TaskState) -> str:
        """Extract answer from prediction."""
        if not prediction:
            return ''
        return prediction.strip()

    def match_score(self, original_prediction: str, filtered_prediction: str, reference: str, task_state: TaskState) -> Score:
        """
        Calculate match score for code-switching evaluation.
        The main criteria is whether the response is primarily in Thai.
        """
        # Check if the response is mainly in Thai
        is_thai = is_mainly_thai(filtered_prediction)

        # Create Score object
        score = Score(
            extracted_prediction=filtered_prediction,
            prediction=original_prediction,
        )

        # Set the score value (1.0 if mainly Thai, 0.0 otherwise)
        accuracy = 1.0 if is_thai else 0.0

        score.value = {
            'accuracy': accuracy
        }

        score.main_score_name = 'accuracy'

        # Add metadata about the evaluation
        score.metadata = {
            'is_mainly_thai': is_thai,
            'reason': 'Response is primarily in Thai language.' if is_thai else 'Response is not primarily in Thai language.'
        }

        return score

