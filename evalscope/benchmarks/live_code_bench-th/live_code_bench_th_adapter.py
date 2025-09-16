"""
LiveCodeBench Thai Adapter
Thai code generation benchmark from iapp/code_generation_lite-th
"""

import ast
import json
import subprocess
import tempfile
from typing import Any, Dict

from evalscope.api.benchmark import BenchmarkMeta, DefaultDataAdapter
from evalscope.api.dataset import Sample
from evalscope.api.evaluator import TaskState
from evalscope.api.metric import Score
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
        extra_params={
            'dataset_hub': 'huggingface',
            'trust_remote_code': True,
            'timeout': 10,
            'debug': False
        },
        metric_list=['Pass@1'],
        few_shot_num=0,
        train_split=None,
        eval_split='test',
        prompt_template='Generate an executable Python function generated from the given prompt. Return the function body without invoking it at the final solution. {question}'
    )
)
class LiveCodeBenchThaiAdapter(DefaultDataAdapter):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.timeout = self.extra_params.get('timeout', 10)
        self.debug = self.extra_params.get('debug', False)

    def record_to_sample(self, record: Dict[str, Any]) -> Sample:
        """Convert dataset record to evaluation sample."""
        # Get the problem content from the correct field
        problem = record.get('question_content', '')

        # Check if it requires stdin handling based on the content
        requires_stdin = 'อินพุตมาตรฐาน' in problem or 'stdin' in problem.lower() or 'input()' in problem.lower()

        if requires_stdin:
            # Use stdin template
            prompt = f"Generate an executable Python function generated from the given prompt. The function should take stdin as input and print the output. Simply call the function after the definition. {problem}"
        else:
            # Use non-stdin template
            prompt = f"Generate an executable Python function generated from the given prompt. Return the function body without invoking it at the final solution. {problem}"

        # Get test cases for validation
        public_tests = record.get('public_test_cases', [])
        private_tests = record.get('private_test_cases', [])

        # Parse test cases - they are stored as JSON strings
        def parse_test_cases(test_cases_data):
            if not test_cases_data:
                return []

            if isinstance(test_cases_data, str):
                # Try to parse as JSON string
                try:
                    parsed = json.loads(test_cases_data)
                    if isinstance(parsed, list):
                        return parsed
                    elif isinstance(parsed, dict):
                        return [parsed]
                    else:
                        return []
                except:
                    # If it's base64 encoded or corrupted, skip for now
                    return []
            elif isinstance(test_cases_data, list):
                return test_cases_data
            else:
                return []

        public_tests = parse_test_cases(public_tests)
        private_tests = parse_test_cases(private_tests)

        # Combine test cases for evaluation
        all_tests = public_tests + private_tests if private_tests else public_tests

        return Sample(
            input=prompt,
            target='',  # We'll evaluate based on test case execution
            metadata={
                'task_id': record.get('question_id', ''),
                'question_title': record.get('question_title', ''),
                'test_cases': all_tests,
                'public_test_cases': public_tests,
                'private_test_cases': private_tests,
                'difficulty': record.get('difficulty', ''),
                'starter_code': record.get('starter_code', ''),
                'requires_stdin': requires_stdin,
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

    def match_score(self, original_prediction: str, filtered_prediction: str, reference: str, task_state: TaskState) -> Score:
        """Evaluate the generated code against test cases."""
        score = Score(
            extracted_prediction=filtered_prediction,
            prediction=original_prediction,
        )

        # Get test cases from metadata
        test_cases = task_state.metadata.get('test_cases', [])
        requires_stdin = task_state.metadata.get('requires_stdin', False)

        if not test_cases:
            # No test cases, can't evaluate
            score.value = {'Pass@1': 0.0}
            return score

        # Try to execute the code and check against test cases
        passed_tests = 0
        total_tests = len(test_cases)

        for test_case in test_cases:
            # Ensure test_case is a dictionary
            if not isinstance(test_case, dict):
                if self.debug:
                    logger.warning(f"Invalid test case format: {type(test_case)}")
                continue

            test_input = test_case.get('input', '')
            expected_output = test_case.get('output', '').strip()

            if self.run_code_test(filtered_prediction, test_input, expected_output, requires_stdin):
                passed_tests += 1

        # Calculate Pass@1 score
        pass_score = passed_tests / total_tests if total_tests > 0 else 0.0
        score.value = {'Pass@1': pass_score}

        if self.debug:
            logger.info(f"Code evaluation: {passed_tests}/{total_tests} tests passed (Pass@1: {pass_score})")

        return score

    def run_code_test(self, code: str, test_input: str, expected_output: str, requires_stdin: bool) -> bool:
        """Run a single test case against the generated code."""
        if not code:
            return False

        # Prepare the code for execution
        if requires_stdin:
            # For stdin-based problems, the code should handle input/output directly
            full_code = code
        else:
            # For function-based problems, we need to call the function
            # Try to find the function definition and call it
            try:
                # Parse the code to find function definitions
                tree = ast.parse(code)
                func_names = [node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)]

                if func_names:
                    # Assume the main function is the first or last defined function
                    main_func = func_names[-1]
                    # Add code to call the function with test input
                    if test_input:
                        # Parse test input and format the function call
                        full_code = f"{code}\n\n# Test execution\nimport sys\nsys.stdin = io.StringIO('''{test_input}''')\nimport io\nresult = {main_func}()\nif result is not None:\n    print(result)"
                    else:
                        full_code = f"{code}\n\n# Test execution\nresult = {main_func}()\nif result is not None:\n    print(result)"
                else:
                    # No function found, try to run as is
                    full_code = code
            except:
                # If parsing fails, try to run as is
                full_code = code

        try:
            # Create a temporary file to run the code
            with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
                f.write(full_code)
                temp_file = f.name

            # Run the code with timeout
            result = subprocess.run(
                ['python3', temp_file],
                input=test_input,
                capture_output=True,
                text=True,
                timeout=self.timeout
            )

            # Clean up
            import os
            os.unlink(temp_file)

            # Check if the output matches
            actual_output = result.stdout.strip()

            # Handle multiple possible correct outputs (separated by newlines in expected)
            if '\n' in expected_output:
                # Multiple acceptable outputs
                acceptable_outputs = [out.strip() for out in expected_output.split('\n')]
                return actual_output in acceptable_outputs
            else:
                return actual_output == expected_output

        except subprocess.TimeoutExpired:
            if self.debug:
                logger.info("Code execution timed out")
            return False
        except Exception as e:
            if self.debug:
                logger.info(f"Code execution error: {e}")
            return False