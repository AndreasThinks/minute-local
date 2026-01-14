import logging
from pathlib import Path

from common.database.postgres_models import Recording
from common.services.transcription_services.adapter import (
    AdapterType,
    TranscriptionAdapter,
)
from common.settings import get_settings
from common.types import DialogueEntry, TranscriptionJobMessageData

settings = get_settings()
logger = logging.getLogger(__name__)


class WhisperLocalAdapter(TranscriptionAdapter):
    """
    Adapter for local Whisper transcription using faster-whisper.

    This adapter provides fully local speech-to-text transcription with GPU acceleration
    support. It uses the faster-whisper library which is optimized for performance.

    Capabilities:
    - Local transcription (no external API calls)
    - GPU acceleration (CUDA) or CPU fallback
    - Multiple language support
    - Configurable model sizes
    - Optional speaker diarization using resemblyzer (fully local, no accounts required)
    """

    max_audio_length = 36000  # 10 hours - essentially unlimited for local processing
    name = "whisper_local"
    adapter_type = AdapterType.SYNCHRONOUS

    @classmethod
    async def check(
        cls, data: TranscriptionJobMessageData
    ) -> TranscriptionJobMessageData:
        """
        For synchronous adapters, this simply returns the data as transcription
        is already complete.
        """
        return data

    @classmethod
    async def start(
        cls, audio_file_path_or_recording: Path | Recording
    ) -> TranscriptionJobMessageData:
        """
        Transcribe audio file using local Whisper model.

        Args:
            audio_file_path_or_recording: Path to audio file or Recording object

        Returns:
            TranscriptionJobMessageData with transcript populated

        Raises:
            ImportError: If faster-whisper is not installed
            RuntimeError: If transcription fails
        """
        try:
            from faster_whisper import WhisperModel
        except ImportError as e:
            msg = (
                "faster-whisper is not installed. "
                "Please install it: pip install faster-whisper"
            )
            raise ImportError(msg) from e

        # Get the file path
        if isinstance(audio_file_path_or_recording, Path):
            audio_path = audio_file_path_or_recording
        else:
            # If Recording object, get the path
            audio_path = Path(audio_file_path_or_recording.file_path)

        logger.info(f"Starting Whisper transcription for: {audio_path}")

        # Initialize Whisper model
        model_size = settings.WHISPER_MODEL_SIZE
        device = settings.WHISPER_DEVICE  # "cuda" or "cpu"
        compute_type = (
            settings.WHISPER_COMPUTE_TYPE
        )  # "float16" for GPU, "int8" for CPU

        logger.info(
            f"Loading Whisper model: {model_size} on {device} with {compute_type}"
        )

        model = WhisperModel(
            model_size,
            device=device,
            compute_type=compute_type,
        )

        # Transcribe the audio
        segments, info = model.transcribe(
            str(audio_path),
            language="en",  # Can make this configurable
            beam_size=5,
            vad_filter=True,  # Voice Activity Detection - removes silence
            vad_parameters=dict(
                min_silence_duration_ms=500,  # Minimum silence duration to split
            ),
        )

        logger.info(
            f"Detected language: {info.language} with probability {info.language_probability:.2f}"
        )

        # Convert segments to DialogueEntry format
        dialogue_entries = []

        for segment in segments:
            dialogue_entry: DialogueEntry = {
                "speaker": "Speaker 1",  # Default, will be updated by diarization
                "text": segment.text.strip(),
                "start_time": segment.start,
                "end_time": segment.end,
            }
            dialogue_entries.append(dialogue_entry)

            logger.debug(f"[{segment.start:.2f}s -> {segment.end:.2f}s] {segment.text}")

        logger.info(f"Transcription complete: {len(dialogue_entries)} segments")

        # Apply speaker diarization if enabled
        if settings.ENABLE_SPEAKER_DIARIZATION:
            dialogue_entries = await cls._apply_diarization(
                audio_path, dialogue_entries
            )

        return TranscriptionJobMessageData(
            transcription_service=cls.name,
            transcript=dialogue_entries,
        )

    @classmethod
    async def _apply_diarization(
        cls, audio_path: Path, dialogue_entries: list[DialogueEntry]
    ) -> list[DialogueEntry]:
        """
        Apply speaker diarization to identify different speakers.

        Uses resemblyzer + spectral clustering for fully local diarization
        without requiring any external accounts.

        Args:
            audio_path: Path to the audio file
            dialogue_entries: List of transcribed segments

        Returns:
            Updated dialogue_entries with speaker labels
        """
        try:
            from common.audio.diarization import (
                perform_diarization,
                assign_speakers_to_transcript,
            )
        except ImportError as e:
            logger.warning(
                f"Diarization dependencies not available: {e}. "
                "Continuing without speaker identification."
            )
            return dialogue_entries

        logger.info("Starting speaker diarization...")

        try:
            # Perform diarization
            speaker_segments = perform_diarization(
                audio_path,
                num_speakers=settings.DIARIZATION_NUM_SPEAKERS,
                min_speakers=settings.DIARIZATION_MIN_SPEAKERS,
                max_speakers=settings.DIARIZATION_MAX_SPEAKERS,
            )

            # Assign speakers to transcript segments
            updated_entries = assign_speakers_to_transcript(
                dialogue_entries, speaker_segments
            )

            # Convert back to DialogueEntry format with proper speaker labels
            result = []
            for entry in updated_entries:
                # Convert SPEAKER_00 format to more readable format
                speaker_num = entry["speaker"].split("_")[-1]
                result.append(
                    DialogueEntry(
                        speaker=f"Speaker {int(speaker_num) + 1}",
                        text=entry["text"],
                        start_time=entry["start_time"],
                        end_time=entry["end_time"],
                    )
                )

            # Count unique speakers
            unique_speakers = set(e["speaker"] for e in result)
            logger.info(
                f"Diarization complete: {len(unique_speakers)} speakers identified"
            )

            return result

        except Exception as e:
            logger.error(
                f"Diarization failed: {e}. Continuing without speaker identification."
            )
            return dialogue_entries

    @classmethod
    def is_available(cls) -> bool:
        """
        Check if Whisper local transcription is available.

        Returns:
            True if faster-whisper can be imported, False otherwise
        """
        try:
            import faster_whisper  # noqa: F401

            return True
        except ImportError:
            logger.warning(
                "faster-whisper not available. Install with: pip install faster-whisper"
            )
            return False

    @classmethod
    def is_diarization_available(cls) -> bool:
        """
        Check if speaker diarization is available.

        Returns:
            True if resemblyzer and dependencies can be imported
        """
        try:
            import resemblyzer  # noqa: F401
            import librosa  # noqa: F401
            from sklearn.cluster import SpectralClustering  # noqa: F401

            return True
        except ImportError:
            return False
