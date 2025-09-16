"""
LiveCodeBench Thai Adapter
Thai code generation benchmark from iapp/code_generation_lite-th
"""

from typing import Any, Dict

from evalscope.api.benchmark import BenchmarkMeta, DefaultDataAdapter
from evalscope.api.dataset import Sample
from evalscope.api.evaluator import TaskState
from evalscope.api.registry import register_benchmark
from evalscope.constants import Tags
from evalscope.utils.logger import get_logger

logger = get_logger()


@register_benchmark(
    BenchmarkMeta(
        name='live_code_bench-th',
        pretty_name='Live-Code-Bench-Thai',
        tags=[Tags.CODING, Tags.REASONING],
        description='Thai version of LiveCodeBench for code generation. Tests the model\'s ability to generate correct Python code from Thai problem descriptions.',
        dataset_id='iapp/code_generation_lite-th',
        subset_list=['default'],
        extra_params={'dataset_hub': 'huggingface'},
        metric_list=[{'exact_match': {}}],
        few_shot_num=0,
        train_split=None,
        eval_split='test',
        prompt_template='Generate an executable Python function generated from the given prompt. Return the function body without invoking it at the final solution. {question}'
    )
)
class LiveCodeBenchThaiAdapter(DefaultDataAdapter):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    def record_to_sample(self, record: Dict[str, Any]) -> Sample:
        """Convert dataset record to evaluation sample."""
        problem = record.get('problem', '')

        # Check if it requires stdin handling
        requires_stdin = 'stdin' in problem.lower() or 'input()' in problem.lower()

        if requires_stdin:
            # Use stdin template
            prompt = f"Generate an executable Python function generated from the given prompt. The function should take stdin as input and print the output. Simply call the function after the definition. {problem}"
        else:
            # Use non-stdin template
            prompt = f"Generate an executable Python function generated from the given prompt. Return the function body without invoking it at the final solution. {problem}"

        return Sample(
            input=prompt,
            target=record.get('canonical_solution', ''),
            metadata={
                'task_id': record.get('task_id', ''),
                'test': record.get('test', ''),
                'entry_point': record.get('entry_point', ''),
            }
        )

    def extract_answer(self, prediction: str, task_state: TaskState) -> str:
        """Extract code from prediction."""
        if not prediction:
            return ''

        # Try to extract Python code block
        if '```python' in prediction:
            code_start = prediction.find('```python') + 9
            code_end = prediction.find('```', code_start)
            if code_end != -1:
                return prediction[code_start:code_end].strip()
        elif '```' in prediction:
            code_start = prediction.find('```') + 3
            code_end = prediction.find('```', code_start)
            if code_end != -1:
                return prediction[code_start:code_end].strip()

        # Return as is if no code block found
        return prediction.strip()