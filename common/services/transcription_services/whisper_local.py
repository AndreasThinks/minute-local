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

    Current capabilities:
    - Local transcription (no external API calls)
    - GPU acceleration (CUDA)
    - Multiple language support
    - Configurable model sizes

    TODO: Speaker Diarization
    ========================
    Future enhancement: Add speaker identification to label who is speaking.

    Options to consider:
    1. resemblyzer + spectral clustering (lightweight, fully local)
       - ~50MB model size
       - Good for basic speaker separation
       - No external dependencies

    2. NVIDIA NeMo (fully local, no HuggingFace account)
       - Download directly from NVIDIA
       - ~3GB model size
       - Better quality than option 1

    3. pyannote.audio (best quality, requires one-time HF setup)
       - Best-in-class diarization
       - Requires HuggingFace token (free) for initial model download
       - After download, works 100% offline
       - Models cached in ~/.cache/huggingface/

    Implementation notes:
    - Add speaker_id field to DialogueEntry when ready
    - Process audio with diarization library to get speaker timestamps
    - Merge speaker timestamps with transcription segments
    - Return transcript with speaker labels (e.g., "SPEAKER_00", "SPEAKER_01")
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
            # If Recording object, we'd need to get the path - this depends on your implementation
            # For now, assume it has a path attribute or similar
            audio_path = Path(audio_file_path_or_recording.file_path)

        logger.info(f"Starting Whisper transcription for: {audio_path}")

        # Initialize Whisper model
        # Model size can be: tiny, base, small, medium, large-v2, large-v3
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
            # TODO: Add speaker identification when diarization is implemented
            # For now, all segments have speaker="Speaker 1" (single speaker)
            dialogue_entry: DialogueEntry = {
                "speaker": "Speaker 1",  # TODO: Replace with actual speaker from diarization
                "text": segment.text.strip(),
                "start_time": segment.start,
                "end_time": segment.end,
            }
            dialogue_entries.append(dialogue_entry)

            logger.debug(
                f"[{segment.start:.2f}s -> {segment.end:.2f}s] "
                f"Speaker {dialogue_entry['speaker']}: {segment.text}"
            )

        logger.info(f"Transcription complete: {len(dialogue_entries)} segments")

        # TODO: Future diarization implementation
        # =====================================
        # When adding diarization, the flow would be:
        # 1. Run diarization on audio_path to get speaker segments
        #    Example: diarization = pipeline(audio_path)
        # 2. For each transcription segment, find overlapping speaker segment
        # 3. Assign speaker_id based on the overlap
        # 4. Update dialogue_entry.speaker_id accordingly
        #
        # Example code structure:
        # ```
        # if settings.ENABLE_SPEAKER_DIARIZATION:
        #     diarization_segments = await cls._perform_diarization(audio_path)
        #     for dialogue_entry in dialogue_entries:
        #         speaker_id = cls._find_speaker_for_segment(
        #             dialogue_entry.start,
        #             dialogue_entry.end,
        #             diarization_segments
        #         )
        #         dialogue_entry.speaker_id = speaker_id
        # ```

        return TranscriptionJobMessageData(
            transcription_service=cls.name,
            transcript=dialogue_entries,
        )

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


# TODO: Future diarization helper functions
# ==========================================
# Uncomment and implement when adding speaker diarization:
#
# async def _perform_diarization(audio_path: Path) -> list[dict]:
#     """
#     Perform speaker diarization on audio file.
#
#     Args:
#         audio_path: Path to audio file
#
#     Returns:
#         List of dicts with 'start', 'end', 'speaker' keys
#     """
#     # Option 1: Using pyannote.audio (best quality)
#     # from pyannote.audio import Pipeline
#     # pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
#     # diarization = pipeline(str(audio_path))
#     # return [{'start': turn.start, 'end': turn.end, 'speaker': speaker}
#     #         for turn, _, speaker in diarization.itertracks(yield_label=True)]
#
#     # Option 2: Using resemblyzer (lightweight)
#     # from resemblyzer import VoiceEncoder, preprocess_wav
#     # from spectral_cluster import SpectralClusterer
#     # ... implementation here ...
#
#     pass
#
# def _find_speaker_for_segment(
#     start: float,
#     end: float,
#     diarization_segments: list[dict]
# ) -> int:
#     """
#     Find which speaker is talking during a transcription segment.
#
#     Uses overlap-based matching to assign speaker IDs.
#
#     Args:
#         start: Segment start time in seconds
#         end: Segment end time in seconds
#         diarization_segments: List of speaker segments from diarization
#
#     Returns:
#         Speaker ID (integer)
#     """
#     max_overlap = 0
#     assigned_speaker = 0
#
#     for seg in diarization_segments:
#         overlap = min(end, seg['end']) - max(start, seg['start'])
#         if overlap > max_overlap:
#             max_overlap = overlap
#             assigned_speaker = int(seg['speaker'].split('_')[-1])
#
#     return assigned_speaker
