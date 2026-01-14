import { Badge } from '@/components/ui/badge'
import { JobStatus } from '@/lib/client'
import { CircleCheckBig, CircleX, Loader2 } from 'lucide-react'

// Processing stage type (matches backend ProcessingStage enum)
// TODO: Import from @/lib/client once OpenAPI types are regenerated
export type ProcessingStage =
  | 'queued'
  | 'transcribing'
  | 'diarizing'
  | 'generating_title'
  | 'generating_minutes'
  | 'complete'

// Map processing stages to user-friendly messages
const PROCESSING_STAGE_LABELS: Record<ProcessingStage, string> = {
  queued: 'Queued',
  transcribing: 'Transcribing audio...',
  diarizing: 'Identifying speakers...',
  generating_title: 'Generating title...',
  generating_minutes: 'Generating minutes...',
  complete: 'Complete',
}

export const StatusBadge = ({
  status,
  processingStage,
  className,
}: {
  status: JobStatus
  processingStage?: ProcessingStage
  className?: string
}) => {
  if (['awaiting_start', 'in_progress'].includes(status)) {
    const label = processingStage
      ? PROCESSING_STAGE_LABELS[processingStage] || 'Processing'
      : 'Processing'
    return (
      <Badge variant="outline" className={className}>
        <Loader2 className="animate-spin" />
        <p>{label}</p>
      </Badge>
    )
  }

  if (status == 'completed') {
    return (
      <Badge variant="outline" className={className}>
        <CircleCheckBig />
        <p>Completed</p>
      </Badge>
    )
  }
  if (status == 'failed') {
    return (
      <Badge variant="outline" className={className}>
        <CircleX />
        <p>Failed</p>
      </Badge>
    )
  }
}
