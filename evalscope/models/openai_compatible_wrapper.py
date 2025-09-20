"""
Wrapper for OpenAI compatible API with enhanced error handling.
This wrapper helps handle 500 errors and other issues gracefully.
"""

import time
import logging
from typing import Dict, Any, Optional
from openai import InternalServerError, APIConnectionError, APITimeoutError

logger = logging.getLogger(__name__)


class RobustOpenAIClient:
    """A wrapper around OpenAI client that handles errors more gracefully."""

    def __init__(self, base_client):
        self.client = base_client
        self.max_retries = 5  # Increased for connection issues
        self.retry_delay = 5   # Increased delay for connection recovery

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

            except (InternalServerError, APIConnectionError, APITimeoutError) as e:
                last_error = e
                error_msg = str(e)
                error_type = type(e).__name__

                logger.warning(f"Attempt {attempt + 1}/{self.max_retries}: {error_type} - {error_msg}")

                # Handle different error types
                if isinstance(e, (APIConnectionError, APITimeoutError)):
                    # Connection issues - wait longer before retrying
                    wait_time = self.retry_delay * (attempt + 1)
                    logger.info(f"Connection issue detected, waiting {wait_time} seconds before retry")
                    time.sleep(wait_time)

                    # On later attempts, try to reduce load
                    if attempt >= 2 and 'max_tokens' in kwargs:
                        original_max = kwargs.get('max_tokens', 32768)
                        kwargs['max_tokens'] = min(original_max, 4096)
                        logger.info(f"Reducing max_tokens to {kwargs['max_tokens']} to reduce load")

                elif isinstance(e, InternalServerError):
                    # Server errors - apply progressive degradation
                    if 'EngineCore' in error_msg or '500' in error_msg:
                        # Try reducing the request size progressively
                        if attempt == 0 and 'max_tokens' in kwargs:
                            # First retry: reduce max_tokens
                            original_max = kwargs.get('max_tokens', 32768)
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

                            # Also reduce max_tokens further
                            if 'max_tokens' in kwargs:
                                kwargs['max_tokens'] = min(kwargs.get('max_tokens', 8192), 4096)

                        elif attempt >= 2:
                            # Further attempts: more aggressive reductions
                            if 'max_tokens' in kwargs:
                                kwargs['max_tokens'] = min(kwargs.get('max_tokens', 4096), 2048)

                            # Truncate messages more aggressively
                            if 'messages' in kwargs:
                                for msg in kwargs['messages']:
                                    if isinstance(msg, dict) and 'content' in msg:
                                        content = msg['content']
                                        if len(content) > 5000:
                                            msg['content'] = content[:5000] + "... [truncated]"

                    # Wait before retrying
                    time.sleep(self.retry_delay * (attempt + 1))

            except Exception as e:
                # For other unexpected errors, log but still retry
                logger.error(f"Unexpected error: {type(e).__name__}: {e}")
                last_error = e

                # Still wait and retry for unexpected errors
                time.sleep(self.retry_delay * (attempt + 1))

        # If all retries failed, return a fallback response
        logger.error(f"All {self.max_retries} attempts failed")
        return self._create_fallback_response(kwargs)

    def _create_fallback_response(self, request_kwargs: Dict[str, Any]) -> Any:
        """Create a fallback response when all retries fail."""
        from openai.types.chat import ChatCompletion, ChatCompletionMessage
        from openai.types.chat.chat_completion import Choice, CompletionUsage

        # Create a proper ChatCompletion object instead of a dict
        return ChatCompletion(
            id='error-fallback',
            object='chat.completion',
            created=int(time.time()),
            model=request_kwargs.get('model', 'unknown'),
            choices=[
                Choice(
                    index=0,
                    message=ChatCompletionMessage(
                        role='assistant',
                        content='ERROR: Model failed to generate response after multiple retries.'
                    ),
                    finish_reason='stop'  # Changed from 'error' to 'stop' as it's a valid value
                )
            ],
            usage=CompletionUsage(
                prompt_tokens=0,
                completion_tokens=0,
                total_tokens=0
            )
        )


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