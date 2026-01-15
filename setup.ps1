# =============================================================================
# Minute Local Setup Script for Windows
# =============================================================================
# A foolproof setup script for running Minute locally with AI-powered
# transcription and meeting minutes generation.
#
# Supports: Windows 10/11 with Docker Desktop
# Features: Auto GPU detection, Ollama installation, model selection
#
# Usage:
#   .\setup.ps1           # Interactive setup
#   .\setup.ps1 -Auto     # Fully automatic setup
#   .\setup.ps1 -Small    # Force small models
#   .\setup.ps1 -Large    # Force large models
# =============================================================================

param(
    [switch]$Auto,
    [switch]$Small,
    [switch]$Large,
    [switch]$NoStart,
    [switch]$Help
)

# Ensure we stop on errors
$ErrorActionPreference = "Stop"

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $ScriptDir ".env.local"
$DataDir = Join-Path $ScriptDir ".data"

# Model configurations
$SmallFastModel = "llama3.2"
$SmallBestModel = "llama3.2"
$SmallWhisper = "medium"

$LargeFastModel = "llama3.2"
$LargeBestModel = "qwen2.5:32b"
$LargeWhisper = "large-v3"

# =============================================================================
# Utility Functions
# =============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    Write-Host ""
    Write-ColorOutput "================================================================" -Color Cyan
    Write-ColorOutput "              Minute Local Setup                                " -Color Cyan
    Write-ColorOutput "         AI-Powered Meeting Transcription & Minutes             " -Color Cyan
    Write-ColorOutput "================================================================" -Color Cyan
    Write-Host ""
}

function Write-Step {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Message
    )
    Write-Host "[$Step/$Total] " -NoNewline -ForegroundColor Blue
    Write-Host $Message -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "      [OK] " -NoNewline -ForegroundColor Green
    Write-Host $Message
}

function Write-Warning {
    param([string]$Message)
    Write-Host "      [!]  " -NoNewline -ForegroundColor Yellow
    Write-Host $Message
}

function Write-Error {
    param([string]$Message)
    Write-Host "      [X]  " -NoNewline -ForegroundColor Red
    Write-Host $Message
}

function Write-Info {
    param([string]$Message)
    Write-Host "      [*]  " -NoNewline -ForegroundColor Cyan
    Write-Host $Message
}

# =============================================================================
# Help Message
# =============================================================================

if ($Help) {
    Write-Host "Usage: .\setup.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Auto      Fully automatic setup (no prompts)"
    Write-Host "  -Small     Force small model configuration"
    Write-Host "  -Large     Force large model configuration"
    Write-Host "  -NoStart   Don't start Docker after setup"
    Write-Host "  -Help      Show this help message"
    exit 0
}

# =============================================================================
# System Detection
# =============================================================================

function Get-SystemInfo {
    $script:OS = "windows"
    $script:Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
    
    # Get Windows version
    $script:WindowsVersion = [System.Environment]::OSVersion.Version.ToString()
    
    # Get total RAM in GB
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $script:TotalRAM = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB)
}

function Get-GPUInfo {
    $script:GPUType = "none"
    $script:GPUName = ""
    $script:GPUVRAM = 0
    
    # Check for NVIDIA GPU using nvidia-smi
    try {
        $nvidiaSmi = Get-Command "nvidia-smi" -ErrorAction SilentlyContinue
        if ($nvidiaSmi) {
            $gpuInfo = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>$null
            if ($gpuInfo) {
                $parts = $gpuInfo.Split(',')
                $script:GPUType = "cuda"
                $script:GPUName = $parts[0].Trim()
                $script:GPUVRAM = [math]::Round([int]$parts[1].Trim() / 1024)  # Convert MB to GB
            }
        }
    }
    catch {
        # nvidia-smi not found or error, continue without GPU
    }
    
    # Fallback: check Windows GPU info
    if ($script:GPUType -eq "none") {
        try {
            $gpuWmi = Get-CimInstance -ClassName Win32_VideoController | Where-Object { $_.Name -like "*NVIDIA*" } | Select-Object -First 1
            if ($gpuWmi) {
                $script:GPUType = "cuda"
                $script:GPUName = $gpuWmi.Name
                if ($gpuWmi.AdapterRAM) {
                    $script:GPUVRAM = [math]::Round($gpuWmi.AdapterRAM / 1GB)
                }
            }
        }
        catch {
            # Continue without GPU detection
        }
    }
}

function Test-DockerInstalled {
    try {
        $dockerVersion = & docker --version 2>$null
        if ($dockerVersion) {
            $script:DockerInstalled = $true
            $script:DockerVersion = ($dockerVersion -split ' ')[2].TrimEnd(',')
            
            # Check if Docker is running
            $dockerInfo = & docker info 2>$null
            $script:DockerRunning = $?
        }
        else {
            $script:DockerInstalled = $false
            $script:DockerRunning = $false
        }
    }
    catch {
        $script:DockerInstalled = $false
        $script:DockerRunning = $false
    }
}

function Test-OllamaInstalled {
    try {
        $ollamaVersion = & ollama --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            $script:OllamaInstalled = $true
            
            # Check if Ollama is running
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
                $script:OllamaRunning = $response.StatusCode -eq 200
            }
            catch {
                $script:OllamaRunning = $false
            }
        }
        else {
            $script:OllamaInstalled = $false
            $script:OllamaRunning = $false
        }
    }
    catch {
        $script:OllamaInstalled = $false
        $script:OllamaRunning = $false
    }
}

# =============================================================================
# Installation Functions
# =============================================================================

function Install-Docker {
    Write-Host ""
    Write-Warning "Docker Desktop is not installed."
    Write-Host ""
    Write-Host "      Please install Docker Desktop for Windows:"
    Write-ColorOutput "      https://docs.docker.com/desktop/install/windows-install/" -Color Cyan
    Write-Host ""
    Write-Host "      After installation:"
    Write-Host "      1. Start Docker Desktop"
    Write-Host "      2. Wait for it to fully start (whale icon in system tray)"
    Write-Host "      3. Run this script again"
    Write-Host ""
    exit 1
}

function Install-Ollama {
    Write-Host ""
    Write-Info "Installing Ollama..."
    
    $installerUrl = "https://ollama.com/download/OllamaSetup.exe"
    $installerPath = Join-Path $env:TEMP "OllamaSetup.exe"
    
    try {
        Write-Info "Downloading Ollama installer..."
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
        
        Write-Info "Running Ollama installer..."
        Write-Host ""
        Write-ColorOutput "      Please complete the Ollama installation wizard." -Color Yellow
        Write-ColorOutput "      After installation, this script will continue automatically." -Color Yellow
        Write-Host ""
        
        Start-Process -FilePath $installerPath -Wait
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        
        # Re-detect Ollama
        Test-OllamaInstalled
        
        if (-not $script:OllamaInstalled) {
            Write-Error "Ollama installation may have failed. Please install manually from https://ollama.com/download"
            exit 1
        }
    }
    catch {
        Write-Error "Failed to download Ollama installer: $_"
        Write-Host ""
        Write-Host "      Please install Ollama manually from:"
        Write-ColorOutput "      https://ollama.com/download" -Color Cyan
        exit 1
    }
    finally {
        if (Test-Path $installerPath) {
            Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-OllamaService {
    if (-not $script:OllamaRunning) {
        Write-Info "Starting Ollama service..."
        
        # Try to start Ollama
        try {
            Start-Process "ollama" -ArgumentList "serve" -WindowStyle Hidden
        }
        catch {
            # Ollama might already be running or will start via the app
        }
        
        # Wait for Ollama to start
        Write-Info "Waiting for Ollama to start..."
        $maxAttempts = 30
        for ($i = 0; $i -lt $maxAttempts; $i++) {
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
                if ($response.StatusCode -eq 200) {
                    $script:OllamaRunning = $true
                    break
                }
            }
            catch {
                Start-Sleep -Seconds 1
            }
        }
        
        if (-not $script:OllamaRunning) {
            Write-Error "Failed to start Ollama. Please start it manually from the Start menu."
            exit 1
        }
    }
}

function Pull-OllamaModel {
    param(
        [string]$Model,
        [string]$Description
    )
    
    # Check if model already exists
    try {
        $modelList = & ollama list 2>$null
        if ($modelList -match "^$Model") {
            Write-Success "$Description ($Model) already downloaded"
            return
        }
    }
    catch {}
    
    Write-Info "Downloading $Description ($Model)..."
    try {
        & ollama pull $Model
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$Description downloaded"
        }
        else {
            Write-Error "Failed to download $Model"
        }
    }
    catch {
        Write-Error "Failed to download $Model : $_"
    }
}

# =============================================================================
# Configuration Selection
# =============================================================================

function Get-RecommendedSize {
    if ($script:GPUType -eq "cuda" -and $script:GPUVRAM -ge 16) {
        return "large"
    }
    elseif ($script:TotalRAM -ge 32) {
        return "large"
    }
    return "small"
}

function Select-Configuration {
    if ($Small) {
        $script:SelectedSize = "small"
        return
    }
    if ($Large) {
        $script:SelectedSize = "large"
        return
    }
    
    $recommended = Get-RecommendedSize
    
    if ($Auto) {
        $script:SelectedSize = $recommended
        Write-Info "Auto-selected: $($script:SelectedSize) configuration"
        return
    }
    
    Write-Host ""
    Write-Host "      Choose your configuration:" -ForegroundColor White
    Write-Host ""
    
    if ($recommended -eq "large") {
        Write-Host "      Based on your hardware, we recommend " -NoNewline
        Write-ColorOutput "LARGE" -Color Green
        Write-Host " models."
    }
    else {
        Write-Host "      Based on your hardware, we recommend " -NoNewline
        Write-ColorOutput "SMALL" -Color Yellow
        Write-Host " models."
    }
    
    Write-Host ""
    Write-ColorOutput "      [S] Small - Faster startup, works on any machine" -Color Cyan
    Write-Host "          * LLM: llama3.2 (~2GB)"
    Write-Host "          * Whisper: medium (~1.5GB)"
    Write-Host ""
    Write-ColorOutput "      [L] Large - Best quality, requires more resources" -Color Cyan
    Write-Host "          * LLM: qwen2.5:32b (~20GB)"
    Write-Host "          * Whisper: large-v3 (~3GB)"
    Write-Host ""
    
    $defaultKey = if ($recommended -eq "large") { "L" } else { "S" }
    $choice = Read-Host "      Press S or L [$defaultKey]"
    
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $defaultKey
    }
    
    switch ($choice.ToUpper()) {
        "L" { $script:SelectedSize = "large" }
        default { $script:SelectedSize = "small" }
    }
}

# =============================================================================
# Environment File Generation
# =============================================================================

function New-EnvFile {
    $fastModel = $SmallFastModel
    $bestModel = $SmallBestModel
    $whisperSize = $SmallWhisper
    
    if ($script:SelectedSize -eq "large") {
        $fastModel = $LargeFastModel
        $bestModel = $LargeBestModel
        $whisperSize = $LargeWhisper
    }
    
    $whisperDevice = "cpu"
    $whisperCompute = "int8"
    
    if ($script:GPUType -eq "cuda") {
        $whisperDevice = "cuda"
        $whisperCompute = "float16"
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $gpuInfo = if ($script:GPUName) { $script:GPUName } else { "CPU only" }
    
    $envContent = @(
        "# ============================================================================="
        "# Minute - Local Mode Configuration"
        "# ============================================================================="
        "# Auto-generated by setup.ps1 on $timestamp"
        "# Configuration: $($script:SelectedSize)"
        "# GPU: $($script:GPUType) ($gpuInfo)"
        "# ============================================================================="
        ""
        "# === Application Settings ==="
        "DOCKER_BUILDER_CONTAINER=minute"
        "APP_NAME=minute"
        "ENVIRONMENT=local"
        "APP_URL=http://localhost:3000"
        "BACKEND_HOST=http://localhost:8080"
        ""
        "# === PostgreSQL Database ==="
        "POSTGRES_HOST=localhost"
        "POSTGRES_PORT=5432"
        "POSTGRES_DB=minute_db"
        "POSTGRES_USER=postgres"
        "POSTGRES_PASSWORD=insecure"
        ""
        "# === Message Queues (LocalStack) ==="
        "TRANSCRIPTION_QUEUE_NAME=minute-transcription-queue"
        "TRANSCRIPTION_DEADLETTER_QUEUE_NAME=minute-transcription-queue-deadletter"
        "LLM_QUEUE_NAME=minute-llm-queue"
        "LLM_DEADLETTER_QUEUE_NAME=minute-llm-queue-deadletter"
        ""
        "# === Local Storage ==="
        "STORAGE_SERVICE_NAME=local"
        "LOCAL_STORAGE_PATH=/static"
        ""
        "# === Local LLM with Ollama ==="
        "OLLAMA_BASE_URL=http://localhost:11434"
        ""
        "FAST_LLM_PROVIDER=ollama"
        "FAST_LLM_MODEL_NAME=$fastModel"
        ""
        "BEST_LLM_PROVIDER=ollama"
        "BEST_LLM_MODEL_NAME=$bestModel"
        ""
        "# === Local Transcription with Whisper ==="
        "TRANSCRIPTION_SERVICES=[`"whisper_local`"]"
        "WHISPER_MODEL_SIZE=$whisperSize"
        "WHISPER_DEVICE=$whisperDevice"
        "WHISPER_COMPUTE_TYPE=$whisperCompute"
        ""
        "# === Speaker Diarization ==="
        "ENABLE_SPEAKER_DIARIZATION=true"
        "DIARIZATION_MIN_SPEAKERS=2"
        "DIARIZATION_MAX_SPEAKERS=10"
        ""
        "# === Authentication (Disabled for Local) ==="
        "REPO=minute"
        "AUTH_API_URL=http://localhost:8080"
        "DISABLE_AUTH_SIGNATURE_VERIFICATION=true"
        ""
        "# === Azure Speech (Not used in local mode) ==="
        "AZURE_SPEECH_KEY=placeholder"
        "AZURE_SPEECH_REGION=placeholder"
        ""
        "# === Telemetry (Disabled) ==="
        "SENTRY_DSN="
        "POSTHOG_API_KEY="
        ""
        "# === AWS (For LocalStack) ==="
        "AWS_ACCOUNT_ID=000000000000"
        "AWS_REGION=eu-west-2"
        "DATA_S3_BUCKET=minute-data"
        "AWS_ACCESS_KEY_ID=test"
        "AWS_SECRET_ACCESS_KEY=test"
        "AWS_SESSION_TOKEN=test"
    ) -join "`r`n"

    $envContent | Out-File -FilePath $EnvFile -Encoding UTF8 -Force
    Write-Success "Created .env.local with $($script:SelectedSize) configuration"
}

# =============================================================================
# Main Setup Flow
# =============================================================================

function Main {
    Write-Header
    
    # Step 1: System Detection
    Write-Step -Step 1 -Total 5 -Message "Checking system..."
    
    Get-SystemInfo
    Get-GPUInfo
    Test-DockerInstalled
    Test-OllamaInstalled
    
    Write-Info "OS: Windows $script:WindowsVersion ($script:Arch)"
    
    if ($script:GPUType -ne "none") {
        Write-Success "GPU: $script:GPUName ($($script:GPUVRAM)GB) - $script:GPUType"
    }
    else {
        Write-Info "GPU: None detected (will use CPU)"
    }
    
    Write-Info "RAM: $($script:TotalRAM)GB"
    
    # Check Docker
    if (-not $script:DockerInstalled) {
        Write-Error "Docker not installed"
        Install-Docker
    }
    elseif (-not $script:DockerRunning) {
        Write-Warning "Docker is installed but not running"
        Write-Host ""
        Write-Host "      Please start Docker Desktop and run this script again."
        Write-Host "      Look for the Docker whale icon in your system tray."
        Write-Host ""
        exit 1
    }
    else {
        Write-Success "Docker $script:DockerVersion"
    }
    
    # Step 2: Ollama Installation
    Write-Step -Step 2 -Total 5 -Message "Setting up Ollama..."
    
    if (-not $script:OllamaInstalled) {
        Write-Warning "Ollama not installed"
        Install-Ollama
    }
    
    Start-OllamaService
    Write-Success "Ollama is running"
    
    # Step 3: Configuration Selection
    Write-Step -Step 3 -Total 5 -Message "Selecting configuration..."
    Select-Configuration
    Write-Success "Selected: $($script:SelectedSize) configuration"
    
    # Step 4: Download Models
    Write-Step -Step 4 -Total 5 -Message "Downloading AI models..."
    
    $fastModel = $SmallFastModel
    $bestModel = $SmallBestModel
    
    if ($script:SelectedSize -eq "large") {
        $fastModel = $LargeFastModel
        $bestModel = $LargeBestModel
    }
    
    Pull-OllamaModel -Model $fastModel -Description "Fast LLM"
    
    if ($fastModel -ne $bestModel) {
        Pull-OllamaModel -Model $bestModel -Description "Best LLM"
    }
    
    # Step 5: Setup Files and Directories
    Write-Step -Step 5 -Total 5 -Message "Finalizing setup..."
    
    # Create data directory
    if (-not (Test-Path $DataDir)) {
        New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
    }
    Write-Success "Created .data directory"
    
    # Generate environment file
    New-EnvFile
    
    Write-Host ""
    Write-ColorOutput "================================================================" -Color Green
    Write-ColorOutput "                    Setup Complete!                             " -Color Green
    Write-ColorOutput "================================================================" -Color Green
    Write-Host ""
    
    if ($NoStart) {
        Write-Host "      Run " -NoNewline
        Write-ColorOutput "docker compose -f docker-compose.local.yaml up -d" -Color Cyan
        Write-Host " to launch Minute"
        Write-Host "      Then open " -NoNewline
        Write-ColorOutput "http://localhost:3000" -Color Cyan
    }
    else {
        Write-Host "      Starting Minute..."
        Write-Host ""
        
        Set-Location $ScriptDir
        
        # Stop any existing containers first
        $existingContainers = & docker compose -f docker-compose.local.yaml ps --quiet 2>$null
        if ($existingContainers) {
            Write-Info "Stopping existing services..."
            & docker compose -f docker-compose.local.yaml down --remove-orphans 2>$null
            Write-Success "Existing services stopped"
        }
        
        # Start Docker containers
        $startResult = & docker compose -f docker-compose.local.yaml up -d --wait 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Success "Minute is running!"
            Write-Host ""
            Write-Host "      Open in your browser:" -ForegroundColor White
            Write-ColorOutput "      ->  http://localhost:3000" -Color Cyan
            Write-Host ""
            Write-Host "      Useful commands:" -ForegroundColor White
            Write-ColorOutput "      docker compose -f docker-compose.local.yaml logs -f" -Color Cyan
            Write-Host "        - View logs"
            Write-ColorOutput "      docker compose -f docker-compose.local.yaml down" -Color Cyan
            Write-Host "        - Stop services"
            Write-Host ""
            
            # Open browser
            Start-Sleep -Seconds 3
            Start-Process "http://localhost:3000"
        }
        else {
            Write-Host ""
            Write-Error "Failed to start Docker containers"
            Write-Host "      Check the logs with: docker compose -f docker-compose.local.yaml logs"
            exit 1
        }
    }
}

# Run main function
Main
