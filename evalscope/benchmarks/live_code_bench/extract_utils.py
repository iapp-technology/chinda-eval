# Copyright LiveCodeBench @ 2024,

import re


def strip_thinking_blocks(text: str) -> str:
    """Strip Qwen3 thinking blocks from response text."""
    if not text:
        return text
    # Remove <think>...</think> blocks
    text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
    # Remove <thinking>...</thinking> blocks
    text = re.sub(r'<thinking>.*?</thinking>', '', text, flags=re.DOTALL)
    return text.strip()


def extract_code_generation(model_output: str, model_type: str = 'chat'):
    # modified from
    # First strip any Qwen3 thinking blocks
    model_output = strip_thinking_blocks(model_output)

    outputlines = model_output.split('\n')
    # TODO: handle codellama

    if model_type == 'base':
        return model_output.strip()
    elif model_type == 'chat':
        indexlines = [i for i, line in enumerate(outputlines) if '```' in line]
    else:
        raise ValueError(f'Invalid mode type: {model_type}')

    if len(indexlines) < 2:
        return ''

    # Extract ALL code blocks and return the longest one
    # This handles cases where models generate multiple code blocks
    # (e.g., pseudocode followed by implementation)
    all_code_blocks = []
    i = 0
    while i < len(indexlines) - 1:
        # Look for pairs of ``` that form a code block
        start = indexlines[i]
        # Find the next ``` after this one
        end = indexlines[i + 1]

        # Check if this looks like a code block start
        # (either ```python, ```Python, or just ```)
        start_line = outputlines[start].lower()
        if '```' in outputlines[start]:
            code_block = '\n'.join(outputlines[start + 1:end])
            # Only add non-empty code blocks
            if code_block.strip():
                all_code_blocks.append(code_block)
            i += 2  # Move past this pair
        else:
            i += 1

    if not all_code_blocks:
        # Fallback to original behavior if no valid blocks found
        return '\n'.join(outputlines[indexlines[0] + 1:indexlines[1]])

    # Return the longest code block
    # This is likely to be the actual implementation rather than pseudocode
    return max(all_code_blocks, key=len)


def extract_code_execution(model_output: str, cot: bool = False):
    pattern = r'\[PYTHON\](.*?)\[\/PYTHON\]'
    matches = re.findall(pattern, model_output, re.DOTALL)
    if matches:
        # fetch the last one
        model_output = matches[-1]

    if '[PYTHON]' in model_output:
        model_output
    if cot:
        if '[ANSWER]' in model_output:
            model_output = model_output.split('[ANSWER]')[1].strip()
    if '==' in model_output:
        model_output = model_output.split('==')[1].strip()
    if '[/ANSWER]' in model_output:
        model_output = model_output.split('[/ANSWER]')[0].strip()
    else:
        model_output = model_output.split('\n')[0].strip()
    return model_output.strip()


def extract_test_output_code(model_output: str):
    outputlines = model_output.split('\n')
    # find the last line startwith assert...
    indexlines = [i for i, line in enumerate(outputlines) if line.startswith('assert')]
    if indexlines:
        return outputlines[indexlines[-1]]

    # TODO: handle codellama format
    # if lmstyle and lmstyle == LMStyle.CodeLLaMaInstruct:
    #     indexlines = \
    # [i for i, line in enumerate(outputlines) if "PYTHON]" in line]
    # else:

    # first try to extract ```python if not then try ```
    indexlines = [i for i, line in enumerate(outputlines) if '```python' in line or '```Python' in line]
    if indexlines:
        start_index = indexlines[0]
    else:
        start_index = None
    indexlines = [i for i, line in enumerate(outputlines) if '```' in line]
    if start_index is not None:
        indexlines = [i for i in indexlines if i > start_index]
        indexlines = [start_index] + indexlines

    if len(indexlines) < 2:
        return ''
    return '\n'.join(outputlines[indexlines[0] + 1:indexlines[1]])
