#!/bin/bash

# =============================================================================
# Minute Local Setup Script
# =============================================================================
# A foolproof setup script for running Minute locally with AI-powered
# transcription and meeting minutes generation.
#
# Supports: macOS, Linux (Ubuntu/Debian/Fedora/Arch)
# Features: Auto GPU detection, Ollama installation, model selection
#
# Usage:
#   ./setup.sh          # Interactive setup
#   ./setup.sh --auto   # Fully automatic setup
#   ./setup.sh --small  # Force small models
#   ./setup.sh --large  # Force large models
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env.local"
DATA_DIR="$SCRIPT_DIR/.data"

# Model configurations
SMALL_FAST_MODEL="llama3.2"
SMALL_BEST_MODEL="llama3.2"
SMALL_WHISPER="medium"

LARGE_FAST_MODEL="llama3.2"
LARGE_BEST_MODEL="qwen2.5:32b"
LARGE_WHISPER="large-v3"

# Parse arguments
AUTO_MODE=false
FORCE_SIZE=""
SKIP_DOCKER_START=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_MODE=true
            shift
            ;;
        --small)
            FORCE_SIZE="small"
            shift
            ;;
        --large)
            FORCE_SIZE="large"
            shift
            ;;
        --no-start)
            SKIP_DOCKER_START=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./setup.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto      Fully automatic setup (no prompts)"
            echo "  --small     Force small model configuration"
            echo "  --large     Force large model configuration"
            echo "  --no-start  Don't start Docker after setup"
            echo "  -h, --help  Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Utility Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}              ${BOLD}🎙️  Minute Local Setup${NC}                        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}         AI-Powered Meeting Transcription & Minutes          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local message=$3
    echo -e "${BLUE}[${step}/${total}]${NC} ${BOLD}${message}${NC}"
}

print_success() {
    echo -e "      ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "      ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "      ${RED}✗${NC} $1"
}

print_info() {
    echo -e "      ${CYAN}•${NC} $1"
}

# =============================================================================
# System Detection
# =============================================================================

detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            if [[ $(uname -m) == "arm64" ]]; then
                ARCH="arm64"
                IS_APPLE_SILICON=true
            else
                ARCH="x86_64"
                IS_APPLE_SILICON=false
            fi
            ;;
        Linux*)
            OS="linux"
            ARCH=$(uname -m)
            IS_APPLE_SILICON=false
            # Detect Linux distribution
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                DISTRO=$ID
            else
                DISTRO="unknown"
            fi
            ;;
        *)
            echo -e "${RED}Unsupported operating system. Please use macOS or Linux.${NC}"
            echo "For Windows, please use setup.ps1"
            exit 1
            ;;
    esac
}

detect_gpu() {
    GPU_TYPE="none"
    GPU_NAME=""
    GPU_VRAM=0
    
    if [[ "$OS" == "macos" ]]; then
        if [[ "$IS_APPLE_SILICON" == true ]]; then
            GPU_TYPE="metal"
            GPU_NAME="Apple Silicon"
            # Estimate unified memory available for GPU
            TOTAL_MEM=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
            GPU_VRAM=$((TOTAL_MEM / 1024 / 1024 / 1024 / 2))  # Assume ~half for GPU
        fi
    else
        # Check for NVIDIA GPU
        if command -v nvidia-smi &> /dev/null; then
            GPU_TYPE="cuda"
            GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || echo "NVIDIA GPU")
            # Get VRAM in GB
            GPU_VRAM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 || echo 0)
            GPU_VRAM=$((GPU_VRAM / 1024))  # Convert MB to GB
        fi
    fi
}

detect_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_INSTALLED=true
        DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
        
        # Check if Docker daemon is running
        if docker info &> /dev/null; then
            DOCKER_RUNNING=true
        else
            DOCKER_RUNNING=false
        fi
    else
        DOCKER_INSTALLED=false
        DOCKER_RUNNING=false
    fi
}

detect_ollama() {
    if command -v ollama &> /dev/null; then
        OLLAMA_INSTALLED=true
        
        # Check if Ollama is running
        if curl -s http://localhost:11434/api/tags &> /dev/null; then
            OLLAMA_RUNNING=true
        else
            OLLAMA_RUNNING=false
        fi
    else
        OLLAMA_INSTALLED=false
        OLLAMA_RUNNING=false
    fi
}

get_total_ram() {
    if [[ "$OS" == "macos" ]]; then
        TOTAL_RAM=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    else
        TOTAL_RAM=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    fi
}

# =============================================================================
# Installation Functions
# =============================================================================

install_docker() {
    echo ""
    print_warning "Docker is not installed."
    echo ""
    
    if [[ "$OS" == "macos" ]]; then
        echo -e "      Please install Docker Desktop for Mac:"
        echo -e "      ${CYAN}https://docs.docker.com/desktop/install/mac-install/${NC}"
        echo ""
        echo -e "      Or install with Homebrew:"
        echo -e "      ${CYAN}brew install --cask docker${NC}"
    else
        echo -e "      Install Docker with:"
        echo -e "      ${CYAN}curl -fsSL https://get.docker.com | sh${NC}"
        echo ""
        echo -e "      Then add your user to the docker group:"
        echo -e "      ${CYAN}sudo usermod -aG docker \$USER${NC}"
    fi
    echo ""
    exit 1
}

install_ollama() {
    echo ""
    
    if [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            print_info "Installing Ollama via Homebrew..."
            brew install ollama
        else
            print_info "Downloading Ollama installer..."
            curl -fsSL https://ollama.com/download/Ollama-darwin.zip -o /tmp/Ollama.zip
            unzip -q /tmp/Ollama.zip -d /Applications
            rm /tmp/Ollama.zip
            print_info "Ollama installed to /Applications"
        fi
    else
        print_info "Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi
    
    # Re-detect Ollama
    detect_ollama
}

start_ollama() {
    if [[ "$OLLAMA_RUNNING" == false ]]; then
        print_info "Starting Ollama service..."
        
        if [[ "$OS" == "macos" ]]; then
            # On macOS, open the app or use brew services
            if [ -d "/Applications/Ollama.app" ]; then
                open -a Ollama
            else
                ollama serve &>/dev/null &
            fi
        else
            # On Linux, start as a background service
            if systemctl is-enabled ollama &>/dev/null; then
                sudo systemctl start ollama
            else
                ollama serve &>/dev/null &
            fi
        fi
        
        # Wait for Ollama to start
        print_info "Waiting for Ollama to start..."
        for i in {1..30}; do
            if curl -s http://localhost:11434/api/tags &> /dev/null; then
                OLLAMA_RUNNING=true
                break
            fi
            sleep 1
        done
        
        if [[ "$OLLAMA_RUNNING" == false ]]; then
            print_error "Failed to start Ollama. Please start it manually with: ollama serve"
            exit 1
        fi
    fi
}

pull_model() {
    local model=$1
    local description=$2
    
    # Check if model already exists
    if ollama list 2>/dev/null | grep -q "^${model}"; then
        print_success "${description} (${model}) already downloaded"
        return 0
    fi
    
    print_info "Downloading ${description} (${model})..."
    if ollama pull "$model"; then
        print_success "${description} downloaded"
    else
        print_error "Failed to download ${model}"
        return 1
    fi
}

# =============================================================================
# Configuration Selection
# =============================================================================

recommend_size() {
    # Recommend based on available resources
    local recommended="small"
    
    if [[ "$GPU_TYPE" == "cuda" ]] && [[ $GPU_VRAM -ge 16 ]]; then
        recommended="large"
    elif [[ "$GPU_TYPE" == "metal" ]] && [[ $GPU_VRAM -ge 16 ]]; then
        recommended="large"
    elif [[ $TOTAL_RAM -ge 32 ]]; then
        recommended="large"
    fi
    
    echo "$recommended"
}

select_configuration() {
    if [[ -n "$FORCE_SIZE" ]]; then
        SELECTED_SIZE="$FORCE_SIZE"
        return
    fi
    
    local recommended=$(recommend_size)
    
    if [[ "$AUTO_MODE" == true ]]; then
        SELECTED_SIZE="$recommended"
        print_info "Auto-selected: ${SELECTED_SIZE} configuration"
        return
    fi
    
    echo ""
    echo -e "      ${BOLD}Choose your configuration:${NC}"
    echo ""
    
    if [[ "$recommended" == "large" ]]; then
        echo -e "      Based on your hardware, we recommend ${GREEN}LARGE${NC} models."
    else
        echo -e "      Based on your hardware, we recommend ${YELLOW}SMALL${NC} models."
    fi
    
    echo ""
    echo -e "      ${CYAN}[S]${NC} Small - Faster startup, works on any machine"
    echo -e "          • LLM: llama3.2 (~2GB)"
    echo -e "          • Whisper: medium (~1.5GB)"
    echo ""
    echo -e "      ${CYAN}[L]${NC} Large - Best quality, requires more resources"
    echo -e "          • LLM: qwen2.5:32b (~20GB)"
    echo -e "          • Whisper: large-v3 (~3GB)"
    echo ""
    
    local default_key="s"
    if [[ "$recommended" == "large" ]]; then
        default_key="l"
    fi
    
    read -p "      Press S or L [$default_key]: " -n 1 choice
    echo ""
    
    choice=${choice:-$default_key}
    
    case ${choice,,} in
        l)
            SELECTED_SIZE="large"
            ;;
        *)
            SELECTED_SIZE="small"
            ;;
    esac
}

# =============================================================================
# Environment File Generation
# =============================================================================

generate_env_file() {
    local fast_model="$SMALL_FAST_MODEL"
    local best_model="$SMALL_BEST_MODEL"
    local whisper_size="$SMALL_WHISPER"
    
    if [[ "$SELECTED_SIZE" == "large" ]]; then
        fast_model="$LARGE_FAST_MODEL"
        best_model="$LARGE_BEST_MODEL"
        whisper_size="$LARGE_WHISPER"
    fi
    
    local whisper_device="cpu"
    local whisper_compute="int8"
    
    if [[ "$GPU_TYPE" == "cuda" ]]; then
        whisper_device="cuda"
        whisper_compute="float16"
    fi
    
    cat > "$ENV_FILE" << EOF
# =============================================================================
# Minute - Local Mode Configuration
# =============================================================================
# Auto-generated by setup.sh on $(date)
# Configuration: ${SELECTED_SIZE}
# GPU: ${GPU_TYPE} (${GPU_NAME:-CPU only})
# =============================================================================

# === Application Settings ===
DOCKER_BUILDER_CONTAINER=minute
APP_NAME=minute
ENVIRONMENT=local
APP_URL=http://localhost:3000
BACKEND_HOST=http://localhost:8080

# === PostgreSQL Database ===
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=minute_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=insecure

# === Message Queues (LocalStack) ===
TRANSCRIPTION_QUEUE_NAME=minute-transcription-queue
TRANSCRIPTION_DEADLETTER_QUEUE_NAME=minute-transcription-queue-deadletter
LLM_QUEUE_NAME=minute-llm-queue
LLM_DEADLETTER_QUEUE_NAME=minute-llm-queue-deadletter

# === Local Storage ===
STORAGE_SERVICE_NAME=local
LOCAL_STORAGE_PATH=/static

# === Local LLM with Ollama ===
OLLAMA_BASE_URL=http://localhost:11434

FAST_LLM_PROVIDER=ollama
FAST_LLM_MODEL_NAME=${fast_model}

BEST_LLM_PROVIDER=ollama
BEST_LLM_MODEL_NAME=${best_model}

# === Local Transcription with Whisper ===
TRANSCRIPTION_SERVICES=["whisper_local"]
WHISPER_MODEL_SIZE=${whisper_size}
WHISPER_DEVICE=${whisper_device}
WHISPER_COMPUTE_TYPE=${whisper_compute}

# === Speaker Diarization ===
ENABLE_SPEAKER_DIARIZATION=true
DIARIZATION_MIN_SPEAKERS=2
DIARIZATION_MAX_SPEAKERS=10

# === Authentication (Disabled for Local) ===
REPO=minute
AUTH_API_URL=http://localhost:8080
DISABLE_AUTH_SIGNATURE_VERIFICATION=true

# === Azure Speech (Not used in local mode) ===
AZURE_SPEECH_KEY=placeholder
AZURE_SPEECH_REGION=placeholder

# === Telemetry (Disabled) ===
SENTRY_DSN=
POSTHOG_API_KEY=

# === AWS (For LocalStack) ===
AWS_ACCOUNT_ID=000000000000
AWS_REGION=eu-west-2
DATA_S3_BUCKET=minute-data
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_SESSION_TOKEN=test
EOF

    print_success "Created .env.local with ${SELECTED_SIZE} configuration"
}

# =============================================================================
# Main Setup Flow
# =============================================================================

main() {
    print_header
    
    # Step 1: System Detection
    print_step 1 5 "Checking system..."
    
    detect_os
    detect_gpu
    detect_docker
    detect_ollama
    get_total_ram
    
    print_info "OS: ${OS} (${ARCH})"
    
    if [[ "$GPU_TYPE" != "none" ]]; then
        print_success "GPU: ${GPU_NAME} (${GPU_VRAM}GB) - ${GPU_TYPE}"
    else
        print_info "GPU: None detected (will use CPU)"
    fi
    
    print_info "RAM: ${TOTAL_RAM}GB"
    
    # Check Docker
    if [[ "$DOCKER_INSTALLED" == false ]]; then
        print_error "Docker not installed"
        install_docker
    elif [[ "$DOCKER_RUNNING" == false ]]; then
        print_warning "Docker is installed but not running"
        echo ""
        echo -e "      Please start Docker and run this script again."
        if [[ "$OS" == "macos" ]]; then
            echo -e "      ${CYAN}open -a Docker${NC}"
        else
            echo -e "      ${CYAN}sudo systemctl start docker${NC}"
        fi
        exit 1
    else
        print_success "Docker ${DOCKER_VERSION}"
    fi
    
    # Step 2: Ollama Installation
    print_step 2 5 "Setting up Ollama..."
    
    if [[ "$OLLAMA_INSTALLED" == false ]]; then
        print_warning "Ollama not installed"
        install_ollama
    fi
    
    start_ollama
    print_success "Ollama is running"
    
    # Step 3: Configuration Selection
    print_step 3 5 "Selecting configuration..."
    select_configuration
    print_success "Selected: ${SELECTED_SIZE} configuration"
    
    # Step 4: Download Models
    print_step 4 5 "Downloading AI models..."
    
    local fast_model="$SMALL_FAST_MODEL"
    local best_model="$SMALL_BEST_MODEL"
    
    if [[ "$SELECTED_SIZE" == "large" ]]; then
        fast_model="$LARGE_FAST_MODEL"
        best_model="$LARGE_BEST_MODEL"
    fi
    
    pull_model "$fast_model" "Fast LLM"
    
    if [[ "$fast_model" != "$best_model" ]]; then
        pull_model "$best_model" "Best LLM"
    fi
    
    # Step 5: Setup Files and Directories
    print_step 5 5 "Finalizing setup..."
    
    # Create data directory
    mkdir -p "$DATA_DIR"
    print_success "Created .data directory"
    
    # Generate environment file
    generate_env_file
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${BOLD}✨ Setup Complete!${NC}                        ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [[ "$SKIP_DOCKER_START" == true ]]; then
        echo -e "      Run ${CYAN}make local-start${NC} to launch Minute"
        echo -e "      Then open ${CYAN}http://localhost:3000${NC}"
    else
        echo -e "      Starting Minute..."
        echo ""
        
        cd "$SCRIPT_DIR"
        
        # Stop any existing containers first
        if docker compose -f docker-compose.local.yaml ps --quiet 2>/dev/null | grep -q .; then
            print_info "Stopping existing services..."
            docker compose -f docker-compose.local.yaml down --remove-orphans 2>/dev/null || true
            print_success "Existing services stopped"
        fi
        
        # Start Docker containers
        if docker compose -f docker-compose.local.yaml up -d --wait; then
            echo ""
            echo -e "      ${GREEN}✓${NC} Minute is running!"
            echo ""
            echo -e "      ${BOLD}Open in your browser:${NC}"
            echo -e "      ${CYAN}➜  http://localhost:3000${NC}"
            echo ""
            echo -e "      ${BOLD}Useful commands:${NC}"
            echo -e "      ${CYAN}make local-logs${NC}     - View logs"
            echo -e "      ${CYAN}make local-stop${NC}     - Stop services"
            echo -e "      ${CYAN}make local-restart${NC}  - Restart services"
            echo ""
            
            # Try to open browser
            if [[ "$OS" == "macos" ]]; then
                sleep 3
                open "http://localhost:3000" 2>/dev/null || true
            elif command -v xdg-open &> /dev/null; then
                sleep 3
                xdg-open "http://localhost:3000" 2>/dev/null || true
            fi
        else
            echo ""
            print_error "Failed to start Docker containers"
            echo -e "      Check the logs with: ${CYAN}make local-logs${NC}"
            exit 1
        fi
    fi
}

# Run main function
main
