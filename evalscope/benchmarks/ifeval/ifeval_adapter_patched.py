"""
IFEval adapter with error handling for gpt-oss-120b compatibility issues.
This is a patched version that handles 500 errors gracefully.
"""
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


class IFEvalAdapterPatched(DefaultDataAdapter):
    """
    IFEval adapter with enhanced error handling for models that struggle with
    certain instruction-following tasks (e.g., gpt-oss-120b with JSON generation).
    """

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.problematic_formats = ['json_format', 'xml_format']  # Known problematic formats

    def run_inference(self, model, sample: Sample, output_dir: str) -> TaskState:
        """Override to add error handling for problematic samples."""
        try:
            # Check if this sample might cause issues
            metadata = sample.metadata or {}
            instruction_ids = metadata.get('instruction_id_list', [])

            # Check if any problematic format is requested
            is_problematic = any(
                fmt in str(instruction_ids)
                for fmt in self.problematic_formats
            )

            if is_problematic and 'gpt-oss-120b' in str(model.model_id):
                logger.warning(f"Skipping potentially problematic sample for gpt-oss-120b: {instruction_ids}")
                # Return a dummy response that will fail validation but won't crash
                task_state = TaskState(
                    inputs=sample.input,
                    target=sample.target or '',
                    choices=[{'content': 'SKIPPED: Model cannot handle this format request.'}],
                    sample_id=sample.id,
                    group_id=sample.group_id,
                    sample_metadata=sample.metadata,
                )
                return task_state

            # Normal processing for other cases
            return super().run_inference(model, sample, output_dir)

        except Exception as e:
            if '500' in str(e) or 'InternalServerError' in str(e):
                logger.error(f"Server error for sample {sample.id}: {e}")
                # Return a failed state instead of crashing
                task_state = TaskState(
                    inputs=sample.input,
                    target=sample.target or '',
                    choices=[{'content': f'ERROR: {str(e)}'}],
                    sample_id=sample.id,
                    group_id=sample.group_id,
                    sample_metadata=sample.metadata,
                )
                return task_state
            else:
                raise  # Re-raise other exceptions

    def record_to_sample(self, record: Dict[str, Any]) -> Sample:
        """Convert a data record to a Sample object."""
        prompt = record['prompt']

        # Create the input message
        input_message = ChatMessageUser(content=prompt)

        # Store metadata for evaluation
        metadata = {
            'key': record.get('key'),
            'prompt': prompt,
            'instruction_id_list': record.get('instruction_id_list', []),
            'kwargs': record.get('kwargs', []),
        }

        return Sample(
            id=record.get('key', 0),
            input=[input_message],
            target='',  # IFEval doesn't have explicit targets
            metadata=metadata
        )