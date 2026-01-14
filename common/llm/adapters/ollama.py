import json
import logging
from typing import TypeVar

import httpx
from pydantic import BaseModel

from common.settings import get_settings

from .base import ModelAdapter

settings = get_settings()
T = TypeVar("T", bound=BaseModel)
logger = logging.getLogger(__name__)


class OllamaModelAdapter(ModelAdapter):
    """
    Adapter for local Ollama LLM models.

    This adapter enables fully local LLM inference through Ollama, supporting both
    standard chat and structured JSON output modes.

    Attributes:
        model: The name of the Ollama model to use (e.g., 'llama3.2', 'qwen2.5:32b')
        base_url: The base URL for the Ollama API (default: http://localhost:11434)
        timeout: HTTP request timeout in seconds
    """

    def __init__(
        self,
        model: str,
        base_url: str | None = None,
        timeout: float = 300.0,
        **kwargs,
    ) -> None:
        self._model = model
        self._base_url = base_url or settings.OLLAMA_BASE_URL
        self._timeout = timeout
        self._kwargs = kwargs
        self._client = httpx.AsyncClient(timeout=timeout)

    async def chat(self, messages: list[dict[str, str]]) -> str:
        """
        Perform a standard chat completion with the Ollama model.

        Args:
            messages: List of message dicts with 'role' and 'content' keys

        Returns:
            The model's text response
        """
        url = f"{self._base_url}/api/chat"

        payload = {
            "model": self._model,
            "messages": messages,
            "stream": False,
            "options": {
                "temperature": self._kwargs.get("temperature", 0.0),
            },
        }

        try:
            response = await self._client.post(url, json=payload)
            response.raise_for_status()
            result = response.json()
            return result["message"]["content"]
        except httpx.HTTPError as e:
            logger.error(f"Ollama API error: {e}")
            raise
        except (KeyError, json.JSONDecodeError) as e:
            logger.error(f"Failed to parse Ollama response: {e}")
            raise

    async def structured_chat(
        self, messages: list[dict[str, str]], response_format: type[T]
    ) -> T:
        """
        Perform a structured chat completion that returns a Pydantic model instance.

        This method uses Ollama's JSON mode and schema validation to ensure the response
        conforms to the expected structure.

        Args:
            messages: List of message dicts with 'role' and 'content' keys
            response_format: A Pydantic model class defining the expected response structure

        Returns:
            An instance of the response_format model populated with the LLM's response
        """
        url = f"{self._base_url}/api/chat"

        # Add JSON format instruction to the system message
        json_instruction = (
            f"\n\nYou must respond with valid JSON that matches this schema:\n"
            f"```json\n{response_format.model_json_schema()}\n```"
        )

        # Inject JSON instruction into messages
        enhanced_messages = messages.copy()
        for i, msg in enumerate(enhanced_messages):
            if msg["role"] == "system":
                enhanced_messages[i] = {
                    "role": "system",
                    "content": msg["content"] + json_instruction,
                }
                break
        else:
            # No system message found, add one
            enhanced_messages.insert(
                0,
                {
                    "role": "system",
                    "content": f"You are a helpful assistant.{json_instruction}",
                },
            )

        payload = {
            "model": self._model,
            "messages": enhanced_messages,
            "stream": False,
            "format": "json",  # Enable JSON mode
            "options": {
                "temperature": self._kwargs.get("temperature", 0.0),
            },
        }

        try:
            response = await self._client.post(url, json=payload)
            response.raise_for_status()
            result = response.json()
            content = result["message"]["content"]

            # Parse and validate the JSON response
            parsed_data = json.loads(content)
            return response_format.model_validate(parsed_data)

        except httpx.HTTPError as e:
            logger.error(f"Ollama API error: {e}")
            raise
        except (KeyError, json.JSONDecodeError) as e:
            logger.error(f"Failed to parse Ollama response: {e}")
            raise
        except Exception as e:
            logger.error(f"Failed to validate response against schema: {e}")
            raise

    async def close(self):
        """Close the HTTP client."""
        await self._client.aclose()
