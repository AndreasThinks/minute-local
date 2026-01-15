'use client'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { useQuery } from '@tanstack/react-query'
import {
    Activity,
    CheckCircle2,
    XCircle,
    AlertCircle,
    RefreshCw,
    Database,
    Server,
    Bot,
    Cpu,
    HardDrive,
    ChevronLeft,
    FileText,
    Filter,
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'

interface ServiceStatus {
    name: string
    status: 'healthy' | 'unhealthy' | 'unknown'
    message?: string
    version?: string
}

interface ModelStatus {
    name: string
    status: 'loaded' | 'available' | 'unavailable'
    size?: string
    role: 'fast' | 'best'
}

interface ConfigurationInfo {
    environment: string
    whisper_model: string
    whisper_device: string
    gpu_type?: string
    storage_service: string
    transcription_services: string[]
}

interface LogEntry {
    timestamp: string
    level: string
    logger: string
    message: string
}

interface LogsResponse {
    logs: LogEntry[]
    total_lines: number
    log_file: string
    log_file_exists: boolean
}

interface SystemStatusResponse {
    timestamp: string
    services: ServiceStatus[]
    models: ModelStatus[]
    configuration: ConfigurationInfo
}

const fetchStatus = async (): Promise<SystemStatusResponse> => {
    const response = await fetch('/api/status')
    if (!response.ok) {
        throw new Error('Failed to fetch status')
    }
    return response.json()
}

const fetchLogs = async (level?: string, limit: number = 50): Promise<LogsResponse> => {
    const params = new URLSearchParams()
    params.set('limit', limit.toString())
    if (level) {
        params.set('level', level)
    }
    const response = await fetch(`/api/status/logs?${params.toString()}`)
    if (!response.ok) {
        throw new Error('Failed to fetch logs')
    }
    return response.json()
}

function StatusIcon({ status }: { status: string }) {
    switch (status) {
        case 'healthy':
        case 'loaded':
            return <CheckCircle2 className="h-5 w-5 text-green-500" />
        case 'unhealthy':
        case 'unavailable':
            return <XCircle className="h-5 w-5 text-red-500" />
        default:
            return <AlertCircle className="h-5 w-5 text-yellow-500" />
    }
}

function ServiceIcon({ name }: { name: string }) {
    switch (name.toLowerCase()) {
        case 'backend':
            return <Server className="h-5 w-5" />
        case 'database':
            return <Database className="h-5 w-5" />
        case 'ollama':
            return <Bot className="h-5 w-5" />
        default:
            return <Activity className="h-5 w-5" />
    }
}

function StatusBadge({ status }: { status: string }) {
    const variant =
        status === 'healthy' || status === 'loaded'
            ? 'default'
            : status === 'unhealthy' || status === 'unavailable'
                ? 'destructive'
                : 'secondary'

    return (
        <Badge variant={variant} className="capitalize">
            {status}
        </Badge>
    )
}

function ServiceCard({ service }: { service: ServiceStatus }) {
    return (
        <Card>
            <CardContent className="p-4">
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                        <div className="rounded-full bg-muted p-2">
                            <ServiceIcon name={service.name} />
                        </div>
                        <div>
                            <h3 className="font-semibold">{service.name}</h3>
                            <p className="text-sm text-muted-foreground">
                                {service.message || service.version || 'No details'}
                            </p>
                        </div>
                    </div>
                    <StatusIcon status={service.status} />
                </div>
            </CardContent>
        </Card>
    )
}

function ModelCard({ model }: { model: ModelStatus }) {
    return (
        <Card>
            <CardContent className="p-4">
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                        <div className="rounded-full bg-muted p-2">
                            <Bot className="h-5 w-5" />
                        </div>
                        <div>
                            <h3 className="font-semibold">{model.name}</h3>
                            <p className="text-sm text-muted-foreground capitalize">
                                {model.role} LLM
                            </p>
                        </div>
                    </div>
                    <StatusBadge status={model.status} />
                </div>
            </CardContent>
        </Card>
    )
}

function LogLevelBadge({ level }: { level: string }) {
    const upperLevel = level.toUpperCase()
    let variant: 'default' | 'secondary' | 'destructive' | 'outline' = 'secondary'
    let className = ''

    switch (upperLevel) {
        case 'ERROR':
        case 'CRITICAL':
            variant = 'destructive'
            break
        case 'WARNING':
            className = 'bg-yellow-500 text-white hover:bg-yellow-600'
            break
        case 'INFO':
            variant = 'default'
            break
        case 'DEBUG':
            variant = 'outline'
            break
    }

    return (
        <Badge variant={variant} className={`font-mono text-xs ${className}`}>
            {upperLevel}
        </Badge>
    )
}

function LogEntryRow({ log }: { log: LogEntry }) {
    return (
        <div className="flex items-start gap-3 py-2 px-3 hover:bg-muted/50 rounded text-sm border-b last:border-0">
            <span className="text-muted-foreground font-mono text-xs whitespace-nowrap">
                {log.timestamp}
            </span>
            <LogLevelBadge level={log.level} />
            <span className="text-muted-foreground font-mono text-xs truncate max-w-[120px]" title={log.logger}>
                {log.logger}
            </span>
            <span className="flex-1 break-words">{log.message}</span>
        </div>
    )
}

export default function StatusPage() {
    const router = useRouter()
    const [autoRefresh, setAutoRefresh] = useState(true)
    const [logLevel, setLogLevel] = useState<string | undefined>(undefined)

    const {
        data: status,
        isLoading,
        error,
        refetch,
        dataUpdatedAt,
    } = useQuery({
        queryKey: ['system-status'],
        queryFn: fetchStatus,
        refetchInterval: autoRefresh ? 10000 : false,
        retry: 1,
    })

    const {
        data: logsData,
        isLoading: logsLoading,
        error: logsError,
        refetch: refetchLogs,
    } = useQuery({
        queryKey: ['system-logs', logLevel],
        queryFn: () => fetchLogs(logLevel, 50),
        refetchInterval: autoRefresh ? 10000 : false,
        retry: 1,
    })

    const lastUpdated = dataUpdatedAt
        ? new Date(dataUpdatedAt).toLocaleTimeString()
        : 'Never'

    return (
        <div className="mx-auto max-w-4xl p-6">
            {/* Header */}
            <div className="mb-6 flex items-center justify-between">
                <div>
                    <Button
                        variant="link"
                        className="mb-2 px-0! underline hover:decoration-2"
                        onClick={() => router.back()}
                    >
                        <span className="flex items-center">
                            <ChevronLeft className="h-4 w-4" />
                            Back
                        </span>
                    </Button>
                    <h1 className="text-3xl font-bold flex items-center gap-2">
                        <Activity className="h-8 w-8" />
                        System Status
                    </h1>
                    <p className="text-muted-foreground">
                        Monitor the health of your Minute installation
                    </p>
                </div>
                <div className="flex items-center gap-2">
                    <Button
                        variant="outline"
                        size="sm"
                        onClick={() => setAutoRefresh(!autoRefresh)}
                    >
                        {autoRefresh ? 'Pause' : 'Resume'} Auto-refresh
                    </Button>
                    <Button variant="outline" size="icon" onClick={() => refetch()}>
                        <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
                    </Button>
                </div>
            </div>

            {/* Last Updated */}
            <p className="mb-4 text-sm text-muted-foreground">
                Last updated: {lastUpdated}
                {autoRefresh && ' (auto-refreshing every 10s)'}
            </p>

            {/* Error State */}
            {error && (
                <Card className="mb-6 border-red-500">
                    <CardContent className="p-4">
                        <div className="flex items-center gap-2 text-red-500">
                            <XCircle className="h-5 w-5" />
                            <span>Failed to fetch status. Is the backend running?</span>
                        </div>
                    </CardContent>
                </Card>
            )}

            {/* Loading State */}
            {isLoading && !status && (
                <div className="flex items-center justify-center py-12">
                    <RefreshCw className="h-8 w-8 animate-spin text-muted-foreground" />
                </div>
            )}

            {/* Status Content */}
            {status && (
                <>
                    {/* Services Section */}
                    <section className="mb-8">
                        <h2 className="mb-4 text-xl font-semibold">Services</h2>
                        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                            {status.services.map((service) => (
                                <ServiceCard key={service.name} service={service} />
                            ))}
                        </div>
                    </section>

                    {/* Models Section */}
                    {status.models.length > 0 && (
                        <section className="mb-8">
                            <h2 className="mb-4 text-xl font-semibold">AI Models</h2>
                            <div className="grid gap-4 sm:grid-cols-2">
                                {status.models.map((model) => (
                                    <ModelCard key={`${model.name}-${model.role}`} model={model} />
                                ))}
                            </div>
                        </section>
                    )}

                    {/* Configuration Section */}
                    <section className="mb-8">
                        <h2 className="mb-4 text-xl font-semibold">Configuration</h2>
                        <Card>
                            <CardContent className="p-6">
                                <div className="grid gap-4 sm:grid-cols-2">
                                    <div className="flex items-center gap-3">
                                        <div className="rounded-full bg-muted p-2">
                                            <HardDrive className="h-5 w-5" />
                                        </div>
                                        <div>
                                            <p className="text-sm text-muted-foreground">Environment</p>
                                            <p className="font-medium capitalize">
                                                {status.configuration.environment}
                                            </p>
                                        </div>
                                    </div>

                                    <div className="flex items-center gap-3">
                                        <div className="rounded-full bg-muted p-2">
                                            <Cpu className="h-5 w-5" />
                                        </div>
                                        <div>
                                            <p className="text-sm text-muted-foreground">GPU</p>
                                            <p className="font-medium">
                                                {status.configuration.gpu_type || 'CPU Only'}
                                            </p>
                                        </div>
                                    </div>

                                    <div className="flex items-center gap-3">
                                        <div className="rounded-full bg-muted p-2">
                                            <Activity className="h-5 w-5" />
                                        </div>
                                        <div>
                                            <p className="text-sm text-muted-foreground">Whisper Model</p>
                                            <p className="font-medium">
                                                {status.configuration.whisper_model} (
                                                {status.configuration.whisper_device})
                                            </p>
                                        </div>
                                    </div>

                                    <div className="flex items-center gap-3">
                                        <div className="rounded-full bg-muted p-2">
                                            <Database className="h-5 w-5" />
                                        </div>
                                        <div>
                                            <p className="text-sm text-muted-foreground">Storage</p>
                                            <p className="font-medium capitalize">
                                                {status.configuration.storage_service}
                                            </p>
                                        </div>
                                    </div>
                                </div>

                                <div className="mt-4 pt-4 border-t">
                                    <p className="text-sm text-muted-foreground mb-2">
                                        Transcription Services
                                    </p>
                                    <div className="flex flex-wrap gap-2">
                                        {status.configuration.transcription_services.map((service) => (
                                            <Badge key={service} variant="secondary">
                                                {service}
                                            </Badge>
                                        ))}
                                    </div>
                                </div>
                            </CardContent>
                        </Card>
                    </section>

                    {/* Quick Links */}
                    <section className="mb-8">
                        <h2 className="mb-4 text-xl font-semibold">Quick Links</h2>
                        <div className="flex flex-wrap gap-4">
                            <Button variant="outline" asChild>
                                <a href="http://localhost:8265" target="_blank" rel="noopener">
                                    Ray Dashboard
                                </a>
                            </Button>
                            <Button variant="outline" asChild>
                                <a href="http://localhost:8080/docs" target="_blank" rel="noopener">
                                    API Docs
                                </a>
                            </Button>
                            <Button variant="outline" asChild>
                                <a href="http://localhost:11434" target="_blank" rel="noopener">
                                    Ollama
                                </a>
                            </Button>
                        </div>
                    </section>
                </>
            )}

            {/* Logs Section - Always visible */}
            <section className="mt-8">
                <div className="flex items-center justify-between mb-4">
                    <h2 className="text-xl font-semibold flex items-center gap-2">
                        <FileText className="h-5 w-5" />
                        Application Logs
                    </h2>
                    <div className="flex items-center gap-2">
                        <div className="flex items-center gap-1">
                            <Filter className="h-4 w-4 text-muted-foreground" />
                            <select
                                className="text-sm border rounded px-2 py-1 bg-background"
                                value={logLevel || ''}
                                onChange={(e) => setLogLevel(e.target.value || undefined)}
                            >
                                <option value="">All levels</option>
                                <option value="DEBUG">DEBUG</option>
                                <option value="INFO">INFO</option>
                                <option value="WARNING">WARNING</option>
                                <option value="ERROR">ERROR</option>
                                <option value="CRITICAL">CRITICAL</option>
                            </select>
                        </div>
                        <Button
                            variant="outline"
                            size="icon"
                            onClick={() => refetchLogs()}
                        >
                            <RefreshCw className={`h-4 w-4 ${logsLoading ? 'animate-spin' : ''}`} />
                        </Button>
                    </div>
                </div>

                <Card>
                    <CardContent className="p-0">
                        {logsError && (
                            <div className="p-4 text-red-500 flex items-center gap-2">
                                <XCircle className="h-5 w-5" />
                                <span>Failed to fetch logs</span>
                            </div>
                        )}

                        {logsLoading && !logsData && (
                            <div className="flex items-center justify-center py-8">
                                <RefreshCw className="h-6 w-6 animate-spin text-muted-foreground" />
                            </div>
                        )}

                        {logsData && (
                            <>
                                {!logsData.log_file_exists && (
                                    <div className="p-4 text-muted-foreground text-sm">
                                        <AlertCircle className="h-4 w-4 inline mr-2" />
                                        Log file not found at: {logsData.log_file}
                                        <br />
                                        <span className="text-xs">Logs will appear here once the application starts logging.</span>
                                    </div>
                                )}

                                {logsData.log_file_exists && logsData.logs.length === 0 && (
                                    <div className="p-4 text-muted-foreground text-sm">
                                        No logs found{logLevel ? ` at ${logLevel} level or above` : ''}.
                                    </div>
                                )}

                                {logsData.logs.length > 0 && (
                                    <div className="max-h-96 overflow-y-auto">
                                        {logsData.logs.map((log, index) => (
                                            <LogEntryRow key={`${log.timestamp}-${index}`} log={log} />
                                        ))}
                                    </div>
                                )}

                                {logsData.log_file_exists && (
                                    <div className="p-3 border-t text-xs text-muted-foreground">
                                        Showing {logsData.logs.length} of {logsData.total_lines} total log lines
                                        {' • '}Log file: {logsData.log_file}
                                    </div>
                                )}
                            </>
                        )}
                    </CardContent>
                </Card>
            </section>
        </div>
    )
}
