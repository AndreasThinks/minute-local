"""
Status API endpoint for system health monitoring.

Provides information about:
- Service health (backend, database, Ollama)
- Loaded models
- Configuration
- Queue status
"""

import os
from datetime import datetime
from typing import Optional

import httpx
from fastapi import APIRouter
from pydantic import BaseModel

from common.settings import Settings

status_router = APIRouter(prefix="/status", tags=["status"])


class ServiceStatus(BaseModel):
    name: str
    status: str  # "healthy", "unhealthy", "unknown"
    message: Optional[str] = None
    version: Optional[str] = None


class ModelStatus(BaseModel):
    name: str
    status: str  # "loaded", "available", "unavailable"
    size: Optional[str] = None
    role: str  # "fast", "best"


class ConfigurationInfo(BaseModel):
    environment: str
    whisper_model: str
    whisper_device: str
    gpu_type: Optional[str] = None
    storage_service: str
    transcription_services: list[str]


class QueueStatus(BaseModel):
    transcription_queue: str
    llm_queue: str
    pending_jobs: int


class SystemStatusResponse(BaseModel):
    timestamp: str
    services: list[ServiceStatus]
    models: list[ModelStatus]
    configuration: ConfigurationInfo
    queue: Optional[QueueStatus] = None


async def check_ollama_status(
    settings: Settings,
) -> tuple[ServiceStatus, list[ModelStatus]]:
    """Check Ollama connectivity and loaded models."""
    models = []

    try:
        ollama_url = settings.ollama_base_url or "http://localhost:11434"
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Check if Ollama is running
            response = await client.get(f"{ollama_url}/api/tags")

            if response.status_code == 200:
                data = response.json()
                available_models = {m["name"]: m for m in data.get("models", [])}

                # Check fast model
                fast_model = settings.fast_llm_model_name
                if fast_model:
                    if fast_model in available_models or any(
                        fast_model in k for k in available_models.keys()
                    ):
                        models.append(
                            ModelStatus(name=fast_model, status="loaded", role="fast")
                        )
                    else:
                        models.append(
                            ModelStatus(
                                name=fast_model, status="unavailable", role="fast"
                            )
                        )

                # Check best model
                best_model = settings.best_llm_model_name
                if best_model and best_model != fast_model:
                    if best_model in available_models or any(
                        best_model in k for k in available_models.keys()
                    ):
                        models.append(
                            ModelStatus(name=best_model, status="loaded", role="best")
                        )
                    else:
                        models.append(
                            ModelStatus(
                                name=best_model, status="unavailable", role="best"
                            )
                        )

                return (
                    ServiceStatus(
                        name="Ollama",
                        status="healthy",
                        message=f"{len(available_models)} models available",
                    ),
                    models,
                )
            else:
                return (
                    ServiceStatus(
                        name="Ollama",
                        status="unhealthy",
                        message=f"HTTP {response.status_code}",
                    ),
                    models,
                )

    except httpx.ConnectError:
        return (
            ServiceStatus(
                name="Ollama",
                status="unhealthy",
                message="Connection refused - is Ollama running?",
            ),
            models,
        )
    except Exception as e:
        return ServiceStatus(name="Ollama", status="unknown", message=str(e)), models


async def check_database_status() -> ServiceStatus:
    """Check PostgreSQL database connectivity."""
    try:
        from common.database import get_db_session
        from sqlalchemy import text

        async with get_db_session() as session:
            result = await session.execute(text("SELECT version()"))
            version = result.scalar()
            pg_version = version.split(",")[0] if version else "Unknown"

            return ServiceStatus(
                name="Database",
                status="healthy",
                message="Connected",
                version=pg_version,
            )
    except Exception as e:
        return ServiceStatus(name="Database", status="unhealthy", message=str(e))


def get_configuration(settings: Settings) -> ConfigurationInfo:
    """Get current configuration info."""
    # Detect GPU type
    gpu_type = None
    whisper_device = os.environ.get("WHISPER_DEVICE", "cpu")

    if whisper_device == "cuda":
        gpu_type = "NVIDIA CUDA"
    elif whisper_device == "mps":
        gpu_type = "Apple Metal"

    # Get transcription services
    transcription_services = []
    try:
        import json

        services_str = os.environ.get("TRANSCRIPTION_SERVICES", '["whisper_local"]')
        transcription_services = json.loads(services_str)
    except:
        transcription_services = ["whisper_local"]

    return ConfigurationInfo(
        environment=settings.environment or "local",
        whisper_model=os.environ.get("WHISPER_MODEL_SIZE", "large-v3"),
        whisper_device=whisper_device,
        gpu_type=gpu_type,
        storage_service=os.environ.get("STORAGE_SERVICE_NAME", "local"),
        transcription_services=transcription_services,
    )


@status_router.get("", response_model=SystemStatusResponse)
async def get_system_status():
    """
    Get comprehensive system status.

    Returns health status of all services, loaded models, and configuration.
    """
    settings = Settings()

    # Check services
    services = []

    # Backend is healthy if we can respond
    services.append(
        ServiceStatus(
            name="Backend", status="healthy", message="Running", version="1.0.0"
        )
    )

    # Check database
    db_status = await check_database_status()
    services.append(db_status)

    # Check Ollama and get models
    ollama_status, models = await check_ollama_status(settings)
    services.append(ollama_status)

    # Get configuration
    config = get_configuration(settings)

    return SystemStatusResponse(
        timestamp=datetime.utcnow().isoformat(),
        services=services,
        models=models,
        configuration=config,
    )


@status_router.get("/health")
async def status_health():
    """Simple health check for the status endpoint."""
    return {"status": "ok"}
