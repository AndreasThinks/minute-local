import logging
import os
from logging.handlers import RotatingFileHandler
from pathlib import Path

from i_dot_ai_utilities.logging.structured_logger import StructuredLogger
from i_dot_ai_utilities.logging.types.enrichment_types import ExecutionEnvironmentType
from i_dot_ai_utilities.logging.types.log_output_format import LogOutputFormat

# Default logging configuration
DEFAULT_LOG_FILE_PATH = ".data/logs/app.log"
DEFAULT_LOG_FILE_MAX_BYTES = 5 * 1024 * 1024  # 5MB
DEFAULT_LOG_FILE_BACKUP_COUNT = 5


def setup_logger(
    log_file_path: str | None = None,
    log_file_max_bytes: int | None = None,
    log_file_backup_count: int | None = None,
):
    """
    Set up logging with both console and file handlers.

    Args:
        log_file_path: Path to the log file. Defaults to .data/logs/app.log
        log_file_max_bytes: Max size of each log file in bytes. Defaults to 5MB
        log_file_backup_count: Number of backup files to keep. Defaults to 5
    """
    # Use environment variables or defaults
    log_file = log_file_path or os.environ.get("LOG_FILE_PATH", DEFAULT_LOG_FILE_PATH)
    max_bytes = log_file_max_bytes or int(
        os.environ.get("LOG_FILE_MAX_BYTES", DEFAULT_LOG_FILE_MAX_BYTES)
    )
    backup_count = log_file_backup_count or int(
        os.environ.get("LOG_FILE_BACKUP_COUNT", DEFAULT_LOG_FILE_BACKUP_COUNT)
    )

    # Create log directory if it doesn't exist
    log_dir = Path(log_file).parent
    log_dir.mkdir(parents=True, exist_ok=True)

    # Set up the root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)

    # Clear any existing handlers to avoid duplicates
    root_logger.handlers.clear()

    # Create formatter
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(formatter)
    root_logger.addHandler(console_handler)

    # File handler with rotation
    try:
        file_handler = RotatingFileHandler(
            log_file,
            maxBytes=max_bytes,
            backupCount=backup_count,
            encoding="utf-8",
        )
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(formatter)
        root_logger.addHandler(file_handler)
        root_logger.info(f"File logging enabled: {log_file}")
    except Exception as e:
        root_logger.warning(f"Could not set up file logging: {e}")


def setup_structured_logger(
    level: str,
    execution_environment: ExecutionEnvironmentType,
    logging_format: LogOutputFormat,
) -> StructuredLogger:
    return StructuredLogger(
        level=level or "info",
        options={
            "execution_environment": execution_environment,
            "log_format": logging_format,
        },
    )
