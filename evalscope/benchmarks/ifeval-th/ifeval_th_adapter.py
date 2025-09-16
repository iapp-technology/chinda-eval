from typing import Any, Dict, List

from evalscope.api.benchmark import BenchmarkMeta, DefaultDataAdapter
from evalscope.api.dataset import Sample
from evalscope.api.evaluator import TaskState
from evalscope.api.messages import ChatMessageUser
from evalscope.api.metric import Score
from evalscope.api.registry import register_benchmark
from evalscope.constants import Tags
from evalscope.utils.logger import get_logger

logger = get_logger()


@register_benchmark(
    BenchmarkMeta(
        name='ifeval-th',
        pretty_name='IFEval-Thai',
        description='IFEval Thai is a benchmark for evaluating instruction-following language models in Thai language, focusing on their ability to understand and respond to various prompts.',  # noqa: E501
        tags=[Tags.INSTRUCTION_FOLLOWING],
        dataset_id='scb10x/ifeval-th',
        subset_list=['default'],
        extra_params={'dataset_hub': 'huggingface'},
        metric_list=[
            'prompt_level_strict',
            'inst_level_strict',
            'prompt_level_loose',
            'inst_level_loose',
        ],
        few_shot_num=0,
        train_split=None,
        eval_split='train',
        prompt_template='คุณคือผู้ช่วยอัจฉริยะที่ต้องปฏิบัติตามคำสั่งอย่างระมัดระวังและแม่นยำ\n\n{question}'
    )
)
class IFEvalThAdapter(DefaultDataAdapter):

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def record_to_sample(self, record: Dict[str, Any]) -> Sample:
        """
        Convert a data record to a Sample object.

        Args:
            record (Dict[str, Any]): Input data record.

        Returns:
            Sample: Sample object with input, target, and metadata.
        """
        prompt = record['prompt']

        # Apply prompt template if available
        if self.prompt_template:
            prompt = self.prompt_template.format(question=prompt)

        return Sample(
            input=[ChatMessageUser(content=prompt)],
            target=record.get('instruction_id_list', []),
            metadata={
                'instruction_id_list': record.get('instruction_id_list', []),
                'kwargs': record.get('kwargs', []),
                'prompt': record.get('prompt', ''),
            }
        )

    def extract_answer(self, prediction: str, task_state: TaskState) -> str:
        """Extract the answer from the prediction."""
        return prediction

    def match_score(
        self, original_prediction: str, filtered_prediction: str, reference: List, task_state: TaskState
    ) -> Score:
        """
        Calculate the match score for IFEval.

        Args:
            original_prediction (str): The original model prediction.
            filtered_prediction (str): The filtered prediction.
            reference (List): The reference instruction IDs.
            task_state (TaskState): The task state.

        Returns:
            Score: The calculated score.
        """
        from .instructions_registry import INSTRUCTION_DICT
        from .utils import test_instruction_following_loose, test_instruction_following_strict

        score = Score(
            extracted_prediction=filtered_prediction,
            prediction=original_prediction,
        )

        # Get instructions and kwargs from metadata
        instruction_id_list = task_state.metadata.get('instruction_id_list', [])
        kwargs_list = task_state.metadata.get('kwargs', [])

        # Evaluate strict and loose
        strict_results = []
        loose_results = []

        for instruction_id, kwargs in zip(instruction_id_list, kwargs_list):
            instruction_cls = INSTRUCTION_DICT.get(instruction_id)
            if instruction_cls:
                # Create instruction with instruction_id (all Instructions take this parameter)
                instruction = instruction_cls(instruction_id)

                # Build the description with kwargs
                # Remove None values to avoid errors
                filtered_kwargs = {k: v for k, v in kwargs.items() if v is not None}
                instruction.build_description(**filtered_kwargs)

                # Test strict
                strict_pass = test_instruction_following_strict(
                    filtered_prediction,
                    instruction
                )
                strict_results.append(strict_pass)

                # Test loose
                loose_pass = test_instruction_following_loose(
                    filtered_prediction,
                    instruction
                )
                loose_results.append(loose_pass)

        # Calculate scores
        inst_level_strict = sum(strict_results) / len(strict_results) if strict_results else 0
        inst_level_loose = sum(loose_results) / len(loose_results) if loose_results else 0
        prompt_level_strict = int(all(strict_results)) if strict_results else 0
        prompt_level_loose = int(all(loose_results)) if loose_results else 0

        score.value = {
            'inst_level_strict': inst_level_strict,
            'inst_level_loose': inst_level_loose,
            'prompt_level_strict': prompt_level_strict,
            'prompt_level_loose': prompt_level_loose,
        }

        score.main_score_name = 'prompt_level_strict'
        score.metadata = {
            'instruction_id_list': instruction_id_list,
            'strict_results': strict_results,
            'loose_results': loose_results,
        }

        return score

    def aggregate_scores(self, sample_scores: List[Score]) -> List[Dict[str, Any]]:
        """
        Aggregate scores across all samples.

        Args:
            sample_scores (List[Score]): List of scores for all samples.

        Returns:
            List[Dict[str, Any]]: Aggregated scores.
        """
        total_inst_level_strict = 0
        total_inst_level_loose = 0
        total_prompt_level_strict = 0
        total_prompt_level_loose = 0
        total_instructions = 0
        total_prompts = len(sample_scores)

        for score in sample_scores:
            values = score.value
            # Count instructions
            if 'strict_results' in score.metadata:
                total_instructions += len(score.metadata['strict_results'])

            # Sum scores
            total_inst_level_strict += values.get('inst_level_strict', 0) * len(score.metadata.get('strict_results', []))
            total_inst_level_loose += values.get('inst_level_loose', 0) * len(score.metadata.get('loose_results', []))
            total_prompt_level_strict += values.get('prompt_level_strict', 0)
            total_prompt_level_loose += values.get('prompt_level_loose', 0)

        # Calculate averages
        avg_inst_level_strict = total_inst_level_strict / total_instructions if total_instructions > 0 else 0
        avg_inst_level_loose = total_inst_level_loose / total_instructions if total_instructions > 0 else 0
        avg_prompt_level_strict = total_prompt_level_strict / total_prompts if total_prompts > 0 else 0
        avg_prompt_level_loose = total_prompt_level_loose / total_prompts if total_prompts > 0 else 0

        return [
            {'name': 'inst_level_strict', 'value': avg_inst_level_strict},
            {'name': 'inst_level_loose', 'value': avg_inst_level_loose},
            {'name': 'prompt_level_strict', 'value': avg_prompt_level_strict},
            {'name': 'prompt_level_loose', 'value': avg_prompt_level_loose},
        ]