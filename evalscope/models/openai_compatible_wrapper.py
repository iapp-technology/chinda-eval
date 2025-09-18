"""
Wrapper for OpenAI compatible API with enhanced error handling.
This wrapper helps handle 500 errors and other issues gracefully.
"""

import time
import logging
from typing import Dict, Any, Optional
from openai import InternalServerError

logger = logging.getLogger(__name__)


class RobustOpenAIClient:
    """A wrapper around OpenAI client that handles errors more gracefully."""

    def __init__(self, base_client):
        self.client = base_client
        self.max_retries = 3
        self.retry_delay = 2

    def chat_completions_create(self, **kwargs) -> Any:
        """
        Create chat completion with robust error handling.

        For models that frequently encounter 500 errors (like Qwen3 models),
        this will attempt fallback strategies.
        """
        last_error = None

        for attempt in range(self.max_retries):
            try:
                # Try the original request using the stored original method
                return self.client.chat.completions._original_create(**kwargs)

            except InternalServerError as e:
                last_error = e
                error_msg = str(e)

                logger.warning(f"Attempt {attempt + 1}: InternalServerError - {error_msg}")

                # Check if it's an EngineCore issue (common with large models)
                if 'EngineCore' in error_msg:
                    # Try reducing the request size
                    if attempt == 0 and 'max_tokens' in kwargs:
                        # First retry: reduce max_tokens
                        original_max = kwargs['max_tokens']
                        kwargs['max_tokens'] = min(original_max, 8192)
                        logger.info(f"Reducing max_tokens from {original_max} to {kwargs['max_tokens']}")

                    elif attempt == 1 and 'messages' in kwargs:
                        # Second retry: truncate the message if it's too long
                        for msg in kwargs['messages']:
                            if isinstance(msg, dict) and 'content' in msg:
                                content = msg['content']
                                if len(content) > 10000:
                                    msg['content'] = content[:10000] + "... [truncated]"
                                    logger.info("Truncating message content to 10000 characters")

                    elif attempt == 2:
                        # Final retry: return a fallback response
                        logger.error("All retries failed, returning fallback response")
                        return self._create_fallback_response(kwargs)

                # Wait before retrying
                time.sleep(self.retry_delay * (attempt + 1))

            except Exception as e:
                # For other errors, raise immediately
                logger.error(f"Unexpected error: {e}")
                raise

        # If all retries failed, return a fallback response
        logger.error(f"All {self.max_retries} attempts failed")
        return self._create_fallback_response(kwargs)

    def _create_fallback_response(self, request_kwargs: Dict[str, Any]) -> Dict[str, Any]:
        """Create a fallback response when all retries fail."""
        return {
            'id': 'error-fallback',
            'object': 'chat.completion',
            'created': int(time.time()),
            'model': request_kwargs.get('model', 'unknown'),
            'choices': [{
                'index': 0,
                'message': {
                    'role': 'assistant',
                    'content': 'ERROR: Model failed to generate response after multiple retries.'
                },
                'finish_reason': 'error'
            }],
            'usage': {
                'prompt_tokens': 0,
                'completion_tokens': 0,
                'total_tokens': 0
            }
        }


def wrap_openai_client(client):
    """Wrap an OpenAI client with robust error handling."""
    # Store the original method BEFORE any modification
    if not hasattr(client.chat.completions, '_original_create'):
        client.chat.completions._original_create = client.chat.completions.create

    wrapper = RobustOpenAIClient(client)

    def wrapped_create(**kwargs):
        # Check if this is a model known to have issues
        model = kwargs.get('model', '')
        if 'qwen3' in model.lower() or 'gpt-oss-120b' in model.lower():
            # Use the robust wrapper for problematic models
            return wrapper.chat_completions_create(**kwargs)
        else:
            # Use the original method for other models
            return client.chat.completions._original_create(**kwargs)

    client.chat.completions.create = wrapped_create
    return client