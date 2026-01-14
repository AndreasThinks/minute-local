"""
Local Speaker Diarization using Resemblyzer + Spectral Clustering

This module provides fully local speaker diarization without requiring
any external accounts or API keys. It uses:

1. Resemblyzer - A speaker embedding model that converts voice segments
   into speaker embedding vectors (~256 dimensions)
2. Spectral Clustering - Groups embeddings by speaker identity

Model Details:
- Resemblyzer model: ~50MB, downloads automatically on first use
- No accounts required
- Works with 2-10 speakers typically
- Fully offline after first model download
"""

import logging
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np

logger = logging.getLogger(__name__)


@dataclass
class SpeakerSegment:
    """A segment of audio with speaker identification."""

    start: float
    end: float
    speaker: str


def perform_diarization(
    audio_path: Path,
    num_speakers: int | None = None,
    min_speakers: int = 2,
    max_speakers: int = 10,
) -> list[SpeakerSegment]:
    """
    Perform speaker diarization on an audio file.

    Uses resemblyzer for speaker embeddings and spectral clustering
    for speaker assignment.

    Args:
        audio_path: Path to audio file (any format ffmpeg can read)
        num_speakers: Exact number of speakers if known, otherwise auto-detected
        min_speakers: Minimum speakers for auto-detection
        max_speakers: Maximum speakers for auto-detection

    Returns:
        List of SpeakerSegment objects with start, end, and speaker label
    """
    try:
        from resemblyzer import VoiceEncoder, preprocess_wav
        from sklearn.cluster import SpectralClustering
        import librosa
    except ImportError as e:
        logger.error(
            "Required packages not installed. Please install: "
            "pip install resemblyzer scikit-learn librosa"
        )
        raise ImportError(
            "Speaker diarization requires: resemblyzer, scikit-learn, librosa"
        ) from e

    logger.info(f"Starting diarization for: {audio_path}")

    # Load and preprocess audio
    # Resemblyzer expects 16kHz mono audio
    wav, sr = librosa.load(str(audio_path), sr=16000, mono=True)
    wav = preprocess_wav(wav)

    # Create voice encoder (downloads model on first use ~50MB)
    encoder = VoiceEncoder()

    # Segment audio into chunks for embedding extraction
    # Use 1.5 second windows with 0.75 second overlap
    window_size = 1.5  # seconds
    hop_size = 0.75  # seconds

    # Calculate segment boundaries
    segments = []
    embeddings = []

    window_samples = int(window_size * sr)
    hop_samples = int(hop_size * sr)

    for start_sample in range(0, len(wav) - window_samples, hop_samples):
        end_sample = start_sample + window_samples
        segment_wav = wav[start_sample:end_sample]

        # Skip silent segments
        if np.abs(segment_wav).max() < 0.01:
            continue

        # Get speaker embedding for this segment
        embedding = encoder.embed_utterance(segment_wav)
        embeddings.append(embedding)

        start_time = start_sample / sr
        end_time = end_sample / sr
        segments.append(
            {
                "start": start_time,
                "end": end_time,
            }
        )

    if len(embeddings) < 2:
        logger.warning("Not enough audio segments for diarization")
        return [SpeakerSegment(start=0, end=len(wav) / sr, speaker="SPEAKER_00")]

    embeddings = np.array(embeddings)

    # Determine number of speakers
    if num_speakers is None:
        # Auto-detect using silhouette score
        num_speakers = _estimate_num_speakers(
            embeddings,
            min_speakers=min_speakers,
            max_speakers=min(max_speakers, len(embeddings)),
        )

    logger.info(f"Clustering into {num_speakers} speakers")

    # Perform spectral clustering
    clustering = SpectralClustering(
        n_clusters=num_speakers,
        affinity="nearest_neighbors",
        n_neighbors=min(10, len(embeddings) - 1),
        random_state=42,
    )
    labels = clustering.fit_predict(embeddings)

    # Merge adjacent segments with same speaker
    speaker_segments = []
    for i, (segment, label) in enumerate(zip(segments, labels)):
        speaker_segments.append(
            SpeakerSegment(
                start=segment["start"],
                end=segment["end"],
                speaker=f"SPEAKER_{label:02d}",
            )
        )

    # Merge consecutive segments with same speaker
    merged_segments = _merge_consecutive_segments(speaker_segments)

    logger.info(
        f"Diarization complete: {len(merged_segments)} segments, {num_speakers} speakers"
    )

    return merged_segments


def _estimate_num_speakers(
    embeddings: np.ndarray,
    min_speakers: int = 2,
    max_speakers: int = 10,
) -> int:
    """
    Estimate optimal number of speakers using silhouette score.

    Args:
        embeddings: Speaker embedding vectors
        min_speakers: Minimum speakers to consider
        max_speakers: Maximum speakers to consider

    Returns:
        Estimated number of speakers
    """
    from sklearn.cluster import SpectralClustering
    from sklearn.metrics import silhouette_score

    best_score = -1
    best_n = min_speakers

    max_speakers = min(max_speakers, len(embeddings) - 1)

    for n_clusters in range(min_speakers, max_speakers + 1):
        try:
            clustering = SpectralClustering(
                n_clusters=n_clusters,
                affinity="nearest_neighbors",
                n_neighbors=min(10, len(embeddings) - 1),
                random_state=42,
            )
            labels = clustering.fit_predict(embeddings)
            score = silhouette_score(embeddings, labels)

            if score > best_score:
                best_score = score
                best_n = n_clusters
        except Exception as e:
            logger.debug(f"Clustering with {n_clusters} failed: {e}")
            continue

    logger.info(f"Estimated {best_n} speakers (silhouette score: {best_score:.3f})")
    return best_n


def _merge_consecutive_segments(
    segments: list[SpeakerSegment],
    gap_tolerance: float = 0.5,
) -> list[SpeakerSegment]:
    """
    Merge consecutive segments with the same speaker.

    Args:
        segments: List of speaker segments
        gap_tolerance: Maximum gap (seconds) to merge across

    Returns:
        List of merged segments
    """
    if not segments:
        return []

    merged = []
    current = segments[0]

    for next_seg in segments[1:]:
        # Check if same speaker and close enough in time
        if (
            next_seg.speaker == current.speaker
            and next_seg.start - current.end <= gap_tolerance
        ):
            # Extend current segment
            current = SpeakerSegment(
                start=current.start,
                end=next_seg.end,
                speaker=current.speaker,
            )
        else:
            merged.append(current)
            current = next_seg

    merged.append(current)
    return merged


def assign_speakers_to_transcript(
    transcript_segments: list[dict],
    speaker_segments: list[SpeakerSegment],
) -> list[dict]:
    """
    Assign speaker labels to transcript segments based on diarization.

    Uses overlap-based matching to find the best speaker for each
    transcript segment.

    Args:
        transcript_segments: List of dicts with 'start_time', 'end_time', 'text'
        speaker_segments: List of SpeakerSegment from diarization

    Returns:
        Transcript segments with 'speaker' field updated
    """
    result = []

    for seg in transcript_segments:
        start = seg.get("start_time", 0)
        end = seg.get("end_time", 0)

        # Find speaker with maximum overlap
        best_speaker = "SPEAKER_00"
        max_overlap = 0

        for speaker_seg in speaker_segments:
            overlap = min(end, speaker_seg.end) - max(start, speaker_seg.start)
            if overlap > max_overlap:
                max_overlap = overlap
                best_speaker = speaker_seg.speaker

        result.append(
            {
                **seg,
                "speaker": best_speaker,
            }
        )

    return result
