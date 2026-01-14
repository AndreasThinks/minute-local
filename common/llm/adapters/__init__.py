# Base adapter is always available
from .base import ModelAdapter

# Ollama adapter is always available (uses httpx which is a core dependency)
from .ollama import OllamaModelAdapter

# Cloud adapters are imported lazily to avoid import errors when their SDKs aren't installed
# These will be imported in client.py only when needed

__all__ = [
    "ModelAdapter",
    "OllamaModelAdapter",
]


def get_openai_adapter():
    """Lazy import for OpenAI adapter (requires openai package)."""
    from .azure_openai import OpenAIModelAdapter

    return OpenAIModelAdapter


def get_gemini_adapter():
    """Lazy import for Gemini adapter (requires google-genai package)."""
    from .gemini import GeminiModelAdapter

    return GeminiModelAdapter
