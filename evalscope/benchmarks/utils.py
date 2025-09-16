"""
Common utilities for benchmark adapters
"""

import re


def strip_thinking_blocks(text: str) -> str:
    """
    Strip Qwen3 thinking blocks from response text.

    Qwen3-Next models use <think>...</think> blocks for reasoning.
    This function removes these blocks to extract the actual response.

    Args:
        text: The raw response text from the model

    Returns:
        The text with thinking blocks removed
    """
    if not text:
        return text

    # Remove <think>...</think> blocks (including multiline)
    text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)

    # Also remove <thinking>...</thinking> blocks (alternative format)
    text = re.sub(r'<thinking>.*?</thinking>', '', text, flags=re.DOTALL)

    # Strip leading/trailing whitespace
    return text.strip()


def extract_code_block(text: str, language: str = 'python') -> str:
    """
    Extract code block from markdown-formatted text.

    Args:
        text: The text containing code blocks
        language: The programming language to look for (default: 'python')

    Returns:
        The extracted code, or the original text if no code block found
    """
    if not text:
        return text

    # First strip any thinking blocks
    text = strip_thinking_blocks(text)

    # Try to extract language-specific code block
    pattern = f'```{language}\\s*\\n(.*?)```'
    match = re.search(pattern, text, re.DOTALL)
    if match:
        return match.group(1).strip()

    # Try generic code block
    pattern = '```\\s*\\n(.*?)```'
    match = re.search(pattern, text, re.DOTALL)
    if match:
        return match.group(1).strip()

    # Return original text if no code block found
    return text


def normalize_answer(text: str) -> str:
    """
    Normalize answer text by stripping thinking blocks and extra whitespace.

    Args:
        text: The raw answer text

    Returns:
        Normalized answer text
    """
    if not text:
        return text

    # Strip thinking blocks
    text = strip_thinking_blocks(text)

    # Normalize whitespace
    text = ' '.join(text.split())

    return text.strip()