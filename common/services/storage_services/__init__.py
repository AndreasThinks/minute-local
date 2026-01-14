# Base storage service is always available
from .base import StorageService

# Local storage is always available (no external dependencies)
from .local.local import LocalStorageService


def _get_storage_services_map() -> dict:
    """Lazily build storage services map to avoid importing cloud SDKs when not needed."""
    services = {
        LocalStorageService.name: LocalStorageService,
    }

    # Try to import S3 service (requires boto3)
    try:
        from .s3 import S3StorageService

        services[S3StorageService.name] = S3StorageService
    except ImportError:
        pass

    # Try to import Azure Blob service (requires azure-storage-blob)
    try:
        from .azure_blob import AzureBlobStorageService

        services[AzureBlobStorageService.name] = AzureBlobStorageService
    except ImportError:
        pass

    return services


def get_storage_service(storage_service_name: str) -> StorageService:
    storage_services = _get_storage_services_map()
    service = storage_services.get(storage_service_name)
    if not service:
        available = ", ".join(storage_services.keys())
        msg = f"Invalid storage service name: {storage_service_name}. Available: {available}"
        raise ValueError(msg)
    return service
