#!/bin/bash
# ============================================================
# Halo AI Core — Install Script
# Designed and built by the architect
#
# "I know kung fu." — Neo, The Matrix
#
# Core services for AMD Strix Halo bare-metal AI platform
# Components: ROCm, Caddy, vLLM ROCm, Lemonade SDK, Gaia SDK, Claude Code
# ============================================================
set -euo pipefail

# Validate HOME has no spaces (systemd units embed it)
if [[ "$HOME" =~ [[:space:]] ]]; then
    echo "ERROR: HOME path contains spaces ($HOME) — not supported"
    exit 1
fi

VERSION="0.9.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${HOME}/.local/log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/halo-ai-core-install.log"
touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
trap 'rm -f "${WG_TMP:-}" "${CLIENT_CONF:-}" 2>/dev/null' EXIT INT TERM
DRY_RUN=false
SKIP_ROCM=false
SKIP_CADDY=false
SKIP_LLAMA=false
SKIP_LEMONADE=false
SKIP_GAIA=false
SKIP_CLAUDE=false
PYTHON_VERSION="3.13.12"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Halo AI Core v${VERSION} — Install Script"
    echo ""
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run       Show what would be installed without doing it"
    echo "  --yes-all       Skip all confirmation prompts"
    echo "  --skip-rocm     Skip ROCm installation"
    echo "  --skip-caddy    Skip Caddy installation"
    echo "  --skip-llama    Skip vLLM ROCm download"
    echo "  --skip-lemonade Skip Lemonade SDK"
    echo "  --skip-gaia     Skip Gaia SDK"
    echo "  --skip-claude   Skip Claude Code"
    echo "  --status        Show current install status"
    echo "  -h, --help      Show this help"
    exit 0
}

# Step count calculated dynamically based on skip flags
CURRENT_STEP=0
calculate_steps() {
    TOTAL_STEPS=4  # base + python + web UIs + wireguard (always run)
    $SKIP_ROCM     || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    $SKIP_CADDY    || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    $SKIP_LLAMA    || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    $SKIP_LEMONADE || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    $SKIP_GAIA     || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    $SKIP_CLAUDE   || TOTAL_STEPS=$((TOTAL_STEPS + 1))
}

progress_bar() {
    local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((pct / 5))
    local empty=$((20 - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "${BLUE}  [${bar}] ${pct}% — Step ${CURRENT_STEP}/${TOTAL_STEPS}${NC}"
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  ▸ Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    progress_bar
    echo ""
    echo "[$(date '+%H:%M:%S')] Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1" >> "$LOG_FILE"
}

spinner() {
    local pid=$1
    local msg=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${BLUE}${spin:i++%${#spin}:1}${NC} %s" "$msg"
        sleep 0.1
    done
    if wait "$pid"; then
        printf "\r  ${GREEN}✓${NC} %s\n" "$msg"
    else
        printf "\r  ${RED}✗${NC} %s\n" "$msg"
        err "$msg — failed (check $LOG_FILE)"
        exit 1
    fi
}

log() {
    echo -e "  ${GREEN}✓${NC} $1"
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    echo "[$(date '+%H:%M:%S')] WARN: $1" >> "$LOG_FILE"
}

err() {
    echo -e "  ${RED}✗${NC} $1"
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

info() {
    echo -e "  ${BLUE}→${NC} $1"
}

check_status() {
    echo ""
    echo "╔══════════════════════════════════════╗"
    echo "║       Halo AI Core — Status          ║"
    echo "╚══════════════════════════════════════╝"
    echo ""

    # ROCm
    if command -v rocminfo &>/dev/null || [ -f /opt/rocm/bin/rocminfo ]; then
        GPU=$(/opt/rocm/bin/rocminfo 2>/dev/null | grep "Marketing Name" | grep -v CPU | head -1 | sed 's/.*: *//')
        echo -e "  ROCm:     ${GREEN}installed${NC} — $GPU"
    else
        echo -e "  ROCm:     ${RED}not installed${NC}"
    fi

    # Caddy
    if systemctl is-active caddy &>/dev/null; then
        echo -e "  Caddy:    ${GREEN}running${NC} — $(caddy version 2>/dev/null)"
    elif command -v caddy &>/dev/null; then
        echo -e "  Caddy:    ${YELLOW}installed but not running${NC}"
    else
        echo -e "  Caddy:    ${RED}not installed${NC}"
    fi

    # vLLM ROCm
    if [ -f "$HOME/vllm-rocm/bin/python3" ]; then
        VER=$("$HOME/vllm-rocm/bin/python3" -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo "unknown")
        echo -e "  vLLM ROCm: ${GREEN}installed${NC} — v$VER"
    else
        echo -e "  vLLM ROCm: ${RED}not installed${NC}"
    fi

    # Lemonade
    if command -v lemonade &>/dev/null; then
        VER=$(lemonade --version 2>/dev/null || echo "installed")
        echo -e "  Lemonade: ${GREEN}installed${NC} — $VER"
    else
        echo -e "  Lemonade: ${RED}not installed${NC}"
    fi

    # Gaia
    if command -v gaia &>/dev/null || [ -f ""$HOME/gaia-env/bin/gaia"" ]; then
        VER=$(gaia --version 2>/dev/null || "$HOME/gaia-env/bin/gaia" --version 2>/dev/null || echo "installed")
        echo -e "  Gaia:     ${GREEN}installed${NC} — v$VER"
    else
        echo -e "  Gaia:     ${RED}not installed${NC}"
    fi

    # Claude Code
    if command -v claude &>/dev/null; then
        echo -e "  Claude:   ${GREEN}installed${NC}"
    else
        echo -e "  Claude:   ${RED}not installed${NC}"
    fi

    # Services
    echo ""
    echo "  Services:"
    for svc in caddy sshd vllm-server lemonade-server gaia-ui gaia; do
        STATUS=$(systemctl is-enabled "$svc" 2>/dev/null || echo "missing")
        ACTIVE=$(systemctl is-active "$svc" 2>/dev/null || true); ACTIVE=${ACTIVE:-inactive}
        if [ "$STATUS" = "enabled" ]; then
            echo -e "    $svc: ${GREEN}$STATUS${NC} ($ACTIVE)"
        else
            echo -e "    $svc: ${YELLOW}$STATUS${NC} ($ACTIVE)"
        fi
    done
    echo ""
    exit 0
}

# Parse args
YES_ALL=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)     DRY_RUN=true; shift ;;
        --yes-all)     YES_ALL=true; shift ;;
        --skip-rocm)   SKIP_ROCM=true; shift ;;
        --skip-caddy)  SKIP_CADDY=true; shift ;;
        --skip-llama)  SKIP_LLAMA=true; shift ;;
        --skip-lemonade) SKIP_LEMONADE=true; shift ;;
        --skip-gaia)   SKIP_GAIA=true; shift ;;
        --skip-claude) SKIP_CLAUDE=true; shift ;;
        --status)      check_status ;;
        -h|--help)     usage ;;
        *)             err "Unknown option: $1"; usage ;;
    esac
done

# ============================================================
calculate_steps
echo ""
echo "╔══════════════════════════════════════╗"
echo "║   Halo AI Core v${VERSION} — Installer    ║"
echo "║   Designed and built by the architect║"
echo "╚══════════════════════════════════════╝"
echo ""

if $DRY_RUN; then
    warn "DRY RUN — nothing will be installed"
    echo ""
fi

# Pre-flight checks
if [ "$(id -u)" -eq 0 ]; then
    err "Do not run as root. Run as your user with sudo access."
    exit 1
fi

if ! command -v pacman &>/dev/null; then
    if $DRY_RUN; then
        warn "pacman not found — dry-run will show planned actions only"
    else
        err "This script requires Arch Linux (pacman not found)"
        exit 1
    fi
fi

if ! sudo -n true 2>/dev/null; then
    if $DRY_RUN; then
        warn "sudo not available — dry-run will show planned actions only"
    else
        err "Passwordless sudo required. Run: echo '$USER ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/$USER"
        exit 1
    fi
fi

# Confirm
if ! $YES_ALL && ! $DRY_RUN; then
    info "This will install Halo AI Core services on $(cat /proc/sys/kernel/hostname)"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0
fi

# ============================================================
# 1. BASE PACKAGES
# ============================================================
step "Base Packages"
BASE_PKGS="base-devel git openssh networkmanager curl wget htop nano nodejs npm github-cli"

if $DRY_RUN; then
    info "Would install: $BASE_PKGS"
else
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm ${BASE_PKGS} >> "$LOG_FILE" 2>&1 &
    spinner $! "Installing base packages..."
    sudo systemctl enable --now NetworkManager sshd >> "$LOG_FILE" 2>&1
    log "Base packages installed"
fi

# ============================================================
# 2. ROCm
# ============================================================
if ! $SKIP_ROCM; then
    step "ROCm GPU Stack"
    ROCM_PKGS="rocm-hip-sdk rocm-opencl-sdk hip-runtime-amd rocminfo rocwmma vulkan-headers vulkan-icd-loader vulkan-radeon shaderc glslang"

    if $DRY_RUN; then
        info "Would install: $ROCM_PKGS"
    else
        # shellcheck disable=SC2086
        sudo pacman -S --needed --noconfirm ${ROCM_PKGS} >> "$LOG_FILE" 2>&1 &
        spinner $! "Installing ROCm packages (this takes a few minutes)..."

        # ROCm PATH and env
        sudo tee /etc/profile.d/rocm.sh > /dev/null << 'ROCM_ENV'
export PATH=$PATH:/opt/rocm/bin
export ROCBLAS_USE_HIPBLASLT=1
export PYTORCH_ROCM_ARCH=gfx1151
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export IOMMU=pt
ROCM_ENV

        # Add user to video/render
        sudo usermod -aG video,render "$USER"

        # Set CPU governor to performance for max throughput
        if command -v cpupower &>/dev/null; then
            sudo cpupower frequency-set -g performance >> "$LOG_FILE" 2>&1 || true
            # Persist across reboots
            echo "governor='performance'" | sudo tee /etc/default/cpupower > /dev/null
            sudo systemctl enable cpupower >> "$LOG_FILE" 2>&1 || true
            log "CPU governor set to performance"
        fi

        # Source it now
        export PATH=$PATH:/opt/rocm/bin

        log "ROCm installed — $(/opt/rocm/bin/rocminfo 2>/dev/null | grep 'Marketing Name' | grep -v CPU | head -1 | sed 's/.*: *//')"
    fi
else
    warn "Skipping ROCm"
fi

# ============================================================
# 3. CADDY
# ============================================================
if ! $SKIP_CADDY; then
    step "Caddy Reverse Proxy"

    if $DRY_RUN; then
        info "Would install: caddy"
    else
        sudo pacman -S --needed --noconfirm caddy >> "$LOG_FILE" 2>&1
        sudo mkdir -p /etc/caddy/conf.d
        # Clean stale configs from previous installs to prevent duplicates
        sudo rm -f /etc/caddy/conf.d/*.caddy 2>/dev/null

        sudo tee /etc/caddy/Caddyfile > /dev/null << 'CADDYFILE'
# Halo AI Core — Caddy Reverse Proxy
# "There is no spoon." — Neo
# Drop configs in /etc/caddy/conf.d/*.caddy

:80 {
    header Content-Type "text/html; charset=utf-8"
    respond `<!DOCTYPE html>
<html><head><title>halo-ai core</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0a0a0a;color:#e0e0e0;font-family:monospace;display:flex;align-items:center;justify-content:center;min-height:100vh}
.box{text-align:center;max-width:600px;padding:2em}
h1{font-size:2em;margin-bottom:0.3em;color:#00d4ff}
.sub{margin-bottom:2em;color:#555;font-size:0.9em}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:0.8em;margin-bottom:1.5em}
.btn{display:block;padding:1em 1.5em;background:#111;border:1px solid #333;border-radius:8px;color:#00d4ff;text-decoration:none;font-size:1.1em;font-family:monospace;transition:all 0.2s}
.btn:hover{background:#1a1a1a;border-color:#00d4ff}
.btn small{display:block;color:#555;font-size:0.75em;margin-top:0.3em}
.full{grid-column:1/-1}
small{display:block;margin-top:1.5em;color:#333}
</style></head><body><div class="box">
<h1>halo-ai core</h1>
<p class="sub">lemonade + gaia + vllm — fully integrated</p>
<div class="grid">
<a class="btn" target="_blank" href="http://{http.request.host}:13306">lemonade<small>chat with llms — :13306</small></a>
<a class="btn" target="_blank" href="http://{http.request.host}:4201">gaia agents<small>manage ai agents — :4201</small></a>
<a class="btn" target="_blank" href="http://{http.request.host}:8081/v1/models">llama api<small>openai-compatible — :8081</small></a>
<a class="btn" target="_blank" href="http://{http.request.host}:5001/docs">gaia api<small>agent api — :5001 → :5050</small></a>
</div>
<small>designed and built by the architect</small>
</div></body></html>`
}

import /etc/caddy/conf.d/*.caddy
CADDYFILE

        sudo systemctl enable --now caddy >> "$LOG_FILE" 2>&1
        log "Caddy installed and running"
    fi
else
    warn "Skipping Caddy"
fi

# ============================================================
# 4. PYTHON (via pyenv for 3.13 compatibility)
# ============================================================
step "Python ${PYTHON_VERSION}"

if $DRY_RUN; then
    info "Would install Python ${PYTHON_VERSION} via pyenv"
else
    if [ ! -f "$HOME/.pyenv/versions/${PYTHON_VERSION}/bin/python3" ]; then
        sudo pacman -S --needed --noconfirm tk sqlite openssl xz bzip2 libffi readline ncurses >> "$LOG_FILE" 2>&1

        # Remove old/broken pyenv installs (detached HEAD, shallow clones)
        if [ -d "$HOME/.pyenv" ]; then
            if ! (cd "$HOME/.pyenv" && git symbolic-ref HEAD > /dev/null 2>&1); then
                log "Removing broken pyenv (detached HEAD)..."
                rm -rf "$HOME/.pyenv"
            fi
        fi

        if [ ! -d "$HOME/.pyenv" ]; then
            log "Installing pyenv..."
            git clone https://github.com/pyenv/pyenv.git "$HOME/.pyenv" >> "$LOG_FILE" 2>&1
            git clone https://github.com/pyenv/pyenv-virtualenv.git "$HOME/.pyenv/plugins/pyenv-virtualenv" >> "$LOG_FILE" 2>&1
        else
            log "Updating pyenv..."
            (cd "$HOME/.pyenv" && git pull >> "$LOG_FILE" 2>&1)
        fi

        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        # shellcheck disable=SC1090
        source <("$PYENV_ROOT/bin/pyenv" init -)

        pyenv install -s "${PYTHON_VERSION}" >> "$LOG_FILE" 2>&1
        log "Python ${PYTHON_VERSION} installed via pyenv"
    else
        log "Python ${PYTHON_VERSION} already installed"
    fi
fi

PYTHON_BIN="$HOME/.pyenv/versions/${PYTHON_VERSION}/bin/python3"

# ============================================================
# 5. VLLM-ROCM (portable — pre-built for AMD GPUs, no compile)
# ============================================================
if ! $SKIP_LLAMA; then
    step "vLLM ROCm (pre-built)"

    if $DRY_RUN; then
        info "Would download portable vLLM + ROCm for this GPU"
    else
        VLLM_DIR="$HOME/vllm-rocm"

        if [ -f "$VLLM_DIR/bin/python3" ]; then
            log "vLLM ROCm already installed at $VLLM_DIR"
        else
            # Detect GPU architecture
            GPU_ARCH="gfx1151"  # default: Strix Halo
            if command -v rocminfo > /dev/null 2>&1; then
                DETECTED=$(rocminfo 2>/dev/null | grep -oP 'gfx\d+' | head -1)
                if [ -n "$DETECTED" ]; then
                    GPU_ARCH="$DETECTED"
                fi
            fi
            log "Detected GPU architecture: $GPU_ARCH"

            # Map architecture to release tag
            case "$GPU_ARCH" in
                gfx1151) VLLM_TAG="vllm0.19.0-rocm7.12.0-gfx1151" ;;
                gfx1150) VLLM_TAG="vllm0.19.0-rocm7.12.0-gfx1150" ;;
                gfx1100|gfx1101|gfx1102|gfx1103) VLLM_TAG="vllm0.19.0-rocm7.12.0-gfx110X" ;;
                gfx1200|gfx1201) VLLM_TAG="vllm0.19.0-rocm7.12.0-gfx120X" ;;
                *)
                    warn "No pre-built vLLM for $GPU_ARCH — falling back to gfx1151"
                    VLLM_TAG="vllm0.19.0-rocm7.12.0-gfx1151"
                    ;;
            esac

            log "Downloading vLLM ROCm ($VLLM_TAG)..."
            VLLM_TMP=$(mktemp -d)
            gh release download "$VLLM_TAG" \
                -R lemonade-sdk/vllm-rocm \
                -D "$VLLM_TMP" >> "$LOG_FILE" 2>&1 &
            spinner $! "Downloading vLLM ROCm ($VLLM_TAG — this is ~3 GB)..."

            log "Extracting vLLM ROCm..."
            mkdir -p "$VLLM_DIR"
            cat "$VLLM_TMP"/*.tar.gz | tar xzf - -C "$VLLM_DIR" 2>&1 &
            spinner $! "Extracting vLLM ROCm..."
            rm -rf "$VLLM_TMP"

            # Fix permissions on bundled binaries
            chmod +x "$VLLM_DIR/bin/python3" 2>/dev/null || true
            chmod +x "$VLLM_DIR/bin/vllm" 2>/dev/null || true
            chmod +x "$VLLM_DIR/bin/vllm-server" 2>/dev/null || true

            log "vLLM ROCm installed — $($VLLM_DIR/bin/python3 -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo 'unknown version')"
        fi

        # Systemd service for vLLM (optional — Lemonade is primary)
        sudo tee /usr/lib/systemd/system/vllm-server.service > /dev/null << VLLM_SVC
[Unit]
Description=vLLM Inference Server (ROCm — optional, Lemonade is primary)
After=network.target

[Service]
Type=simple
User=${USER}
Environment=HSA_OVERRIDE_GFX_VERSION=11.5.1
ExecStart=${VLLM_DIR}/bin/python3 -m vllm.entrypoints.openai.api_server \\
    --host 127.0.0.1 \\
    --port 8080 \\
    --dtype auto \\
    --max-model-len 32768
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
VLLM_SVC

        # Caddy routes — external-facing ports proxy to Lemonade (primary LLM backend)
        sudo tee /etc/caddy/conf.d/llm-api.caddy > /dev/null << 'LLM_API_CADDY'
:8081 {
    @local remote_ip 127.0.0.1 10.0.0.0/24 10.100.0.0/24
    handle @local {
        reverse_proxy 127.0.0.1:13305
    }
    respond 403
}
LLM_API_CADDY
        # Clean up old misnamed config
        sudo rm -f /etc/caddy/conf.d/llama.caddy 2>/dev/null

        sudo tee /etc/caddy/conf.d/lemonade-ui.caddy > /dev/null << 'LEM_CADDY'
:13306 {
    @local remote_ip 127.0.0.1 10.0.0.0/24 10.100.0.0/24
    handle @local {
        reverse_proxy localhost:13305
    }
    respond 403
}
LEM_CADDY

        sudo tee /etc/caddy/conf.d/gaia-ui.caddy > /dev/null << 'GAIA_UI_CADDY'
:4201 {
    @local remote_ip 127.0.0.1 10.0.0.0/24 10.100.0.0/24
    handle @local {
        reverse_proxy localhost:4200
    }
    respond 403
}
GAIA_UI_CADDY

        sudo tee /etc/caddy/conf.d/gaia-api.caddy > /dev/null << 'GAIA_API_CADDY'
:5001 {
    @local remote_ip 127.0.0.1 10.0.0.0/24 10.100.0.0/24
    handle @local {
        reverse_proxy localhost:5050
    }
    respond 403
}
GAIA_API_CADDY

        sudo systemctl daemon-reload
        sudo systemctl reload caddy >> "$LOG_FILE" 2>&1 || warn "Caddy reload failed — check /etc/caddy/conf.d/ for duplicates"

        log "vLLM ROCm ready — start with: sudo systemctl start vllm-server"
    fi
else
    warn "Skipping vLLM ROCm"
fi

# ============================================================
# 6. LEMONADE SERVER (native AUR package)
# ============================================================
if ! $SKIP_LEMONADE; then
    step "Lemonade Server"

    if $DRY_RUN; then
        info "Would install lemonade-server from AUR"
    else
        if command -v lemonade &>/dev/null; then
            log "Lemonade already installed — $(lemonade --version 2>/dev/null || echo 'installed')"
        else
            # Need an AUR helper (paru > yay > install yay)
            AUR_HELPER=""
            if command -v paru &>/dev/null; then
                AUR_HELPER="paru"
            elif command -v yay &>/dev/null; then
                AUR_HELPER="yay"
            else
                info "Installing yay (AUR helper)..."
                YAY_TMPDIR=$(mktemp -d)
                git clone https://aur.archlinux.org/yay.git "$YAY_TMPDIR/yay" >> "$LOG_FILE" 2>&1
                cd "$YAY_TMPDIR/yay" && makepkg -si --noconfirm >> "$LOG_FILE" 2>&1
                cd "$HOME"
                rm -rf "$YAY_TMPDIR"
                AUR_HELPER="yay"
            fi

            $AUR_HELPER -S --needed --noconfirm lemonade-server >> "$LOG_FILE" 2>&1 &
            spinner $! "Building lemonade-server from AUR (C++ native — this takes a minute)..."
        fi

        # Enable and start the daemon
        sudo systemctl daemon-reload
        sudo systemctl enable --now lemond >> "$LOG_FILE" 2>&1 || \
            sudo systemctl enable --now lemonade-server >> "$LOG_FILE" 2>&1 || true
        # Wait for server to be ready
        log "Waiting for Lemonade server to start..."
        for i in $(seq 1 30); do
            if lemonade status --json > /dev/null 2>&1; then break; fi
            sleep 1
        done

        VER=$(lemonade --version 2>/dev/null || echo "installed")
        log "Lemonade Server $VER — binaries: lemonade (CLI), lemond (daemon)"
        log "Anthropic API: http://localhost:13305/v1/messages"
        log "OpenAI API:    http://localhost:13305/api/v1/chat/completions"
        log "Ollama API:    http://localhost:13305/api/chat"
    fi
else
    warn "Skipping Lemonade Server"
fi

# ============================================================
# 7. GAIA SDK
# ============================================================
if ! $SKIP_GAIA; then
    step "Gaia SDK"

    if $DRY_RUN; then
        info "Would install amd-gaia in ~/gaia-env"
    else
        if [ ! -d "$HOME/gaia" ]; then
            git clone --depth 1 https://github.com/amd/gaia.git "$HOME/gaia" >> "$LOG_FILE" 2>&1
        fi

        if [ ! -d "$HOME/gaia-env" ]; then
            "$PYTHON_BIN" -m venv "$HOME/gaia-env"
        fi

        "$HOME/gaia-env/bin/pip" install --upgrade pip >> "$LOG_FILE" 2>&1
        cd "$HOME/gaia"
        "$HOME/gaia-env/bin/pip" install -e . >> "$LOG_FILE" 2>&1 &
        spinner $! "Installing Gaia SDK (includes PyTorch — grab a coffee)..."

        # Gaia .env — wire to Lemonade as primary backend
        install -m 600 /dev/null "$HOME/gaia/.env"
        cat > "$HOME/gaia/.env" << GAIA_ENV
# Halo AI Core — Gaia Integration
# Primary: Lemonade server (manages models, llamacpp backend)
LEMONADE_BASE_URL=http://localhost:13305/api/v1

# MCP Server
GAIA_MCP_HOST=localhost
GAIA_MCP_PORT=8765

# Agent routing model (loaded via Lemonade)
AGENT_ROUTING_MODEL=Qwen3-Coder-30B-A3B-Instruct-GGUF
GAIA_ENV

        # Systemd service — Gaia API (OpenAI-compatible endpoint)
        sudo tee /usr/lib/systemd/system/gaia.service > /dev/null << GAIA_SVC
[Unit]
Description=Gaia AI Agent Framework
After=network.target lemonade-server.service
Wants=lemonade-server.service

[Service]
Type=simple
User=${USER}
Environment=PATH=${HOME}/gaia-env/bin:/usr/local/bin:/opt/rocm/bin:/usr/bin
Environment=ROCBLAS_USE_HIPBLASLT=1
Environment=HSA_OVERRIDE_GFX_VERSION=11.5.1
Environment=LEMONADE_BASE_URL=http://localhost:13305/api/v1
WorkingDirectory=${HOME}/gaia
ExecStart=${HOME}/gaia-env/bin/gaia api start --host 127.0.0.1 --port 5050 --no-lemonade-check
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
GAIA_SVC

        sudo systemctl daemon-reload
        sudo systemctl enable gaia >> "$LOG_FILE" 2>&1

        VER=$(""$HOME/gaia-env/bin/gaia"" --version 2>/dev/null || echo "unknown")
        log "Gaia SDK v$VER installed"
        log "Gaia .env created — LEMONADE_BASE_URL=http://localhost:13305/api/v1"
    fi
else
    warn "Skipping Gaia SDK"
fi

# ============================================================
# 8. WEB UIs
# ============================================================
step "Web UIs"

if $DRY_RUN; then
    info "Would configure Lemonade UI (port 13305) and Gaia Agent UI (port 4200)"
else
    # Lemonade UI is handled by lemond (native AUR package)
    # Clean up old venv-based services from previous installs
    sudo systemctl disable lemonade lemonade-ui >> "$LOG_FILE" 2>&1 || true
    sudo rm -f /usr/lib/systemd/system/lemonade.service 2>/dev/null
    sudo rm -f /usr/lib/systemd/system/lemonade-ui.service 2>/dev/null

    # Gaia Agent UI
    npm install -g --ignore-scripts --prefix "$HOME/.local" @amd-gaia/agent-ui@latest >> "$LOG_FILE" 2>&1

    # Find gaia-ui binary — npm global bin location varies
    GAIA_UI_BIN=$(command -v gaia-ui 2>/dev/null || npm root -g 2>/dev/null | sed 's|/lib/node_modules|/bin/gaia-ui|' || echo "/usr/local/bin/gaia-ui")

    sudo tee /usr/lib/systemd/system/gaia-ui.service > /dev/null << GAIA_UI_SVC
[Unit]
Description=Gaia Agent Web UI
After=network.target lemonade-server.service
Wants=lemonade-server.service

[Service]
Type=simple
User=${USER}
Environment=PATH=${HOME}/gaia-env/bin:/usr/local/bin:/opt/rocm/bin:/usr/bin:/usr/lib/node_modules/.bin
Environment=NODE_PATH=/usr/lib/node_modules
Environment=ROCBLAS_USE_HIPBLASLT=1
Environment=HSA_OVERRIDE_GFX_VERSION=11.5.1
Environment=LEMONADE_BASE_URL=http://localhost:13305/api/v1
WorkingDirectory=${HOME}/gaia
ExecStart=${GAIA_UI_BIN} --port 4200
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
GAIA_UI_SVC

    sudo systemctl daemon-reload
    sudo systemctl enable gaia-ui >> "$LOG_FILE" 2>&1
    sudo systemctl reload caddy >> "$LOG_FILE" 2>&1 || warn "Caddy reload failed — check /etc/caddy/conf.d/ for duplicates"

    # Install the LLM backend switch script
    sudo cp "$SCRIPT_DIR/halo-llm-switch.sh" /usr/local/bin/halo-llm-switch
    sudo chmod +x /usr/local/bin/halo-llm-switch

    log "Lemonade UI on :13305 — managed by lemond (native service)"
    log "Gaia Agent UI on :4200 — Agent management"
    log "Switch backends: halo-llm-switch [lemonade|llama|status]"
fi

# ============================================================
# 9. CLAUDE CODE
# ============================================================
if ! $SKIP_CLAUDE; then
    step "Claude Code (via Lemonade)"

    if $DRY_RUN; then
        info "Would install Claude Code CLI and configure for Lemonade"
    else
        # Install Claude Code
        if command -v claude &>/dev/null; then
            log "Claude Code already installed — $(claude --version 2>/dev/null || echo 'installed')"
        else
            if command -v npm &>/dev/null; then
                npm install -g --ignore-scripts --prefix "$HOME/.local" @anthropic-ai/claude-code >> "$LOG_FILE" 2>&1 &
                spinner $! "Installing Claude Code..."
                log "Claude Code installed via npm"
            else
                err "npm not found — cannot install Claude Code"
            fi
        fi

        # Verify lemonade launch claude is available
        if command -v lemonade &>/dev/null; then
            log "Claude Code can be launched via: lemonade launch claude"
            log "Or with a model: lemonade launch claude -m <model-name>"
        else
            warn "Lemonade CLI not found — install Lemonade Server first for local model routing"
        fi
    fi
else
    warn "Skipping Claude Code"
fi

# ============================================================
# WIREGUARD — Remote Access via QR Code
# ============================================================
step "WireGuard VPN"

if $DRY_RUN; then
    info "Would install wireguard-tools, qrencode, nftables and generate VPN config"
else
    sudo pacman -S --needed --noconfirm wireguard-tools qrencode nftables >> "$LOG_FILE" 2>&1

    WG_DIR="/etc/wireguard"
    WG_CONF="$WG_DIR/wg0.conf"

    if [ ! -f "$WG_CONF" ]; then
        WG_KEY_DIR=$(mktemp -d)
        chmod 700 "$WG_KEY_DIR"
        wg genkey | tee "$WG_KEY_DIR/server.key" | wg pubkey > "$WG_KEY_DIR/server.pub"
        wg genkey | tee "$WG_KEY_DIR/client.key" | wg pubkey > "$WG_KEY_DIR/client.pub"
        chmod 600 "$WG_KEY_DIR"/*.key
        SERVER_PRIV=$(cat "$WG_KEY_DIR/server.key")
        SERVER_PUB=$(cat "$WG_KEY_DIR/server.pub")
        CLIENT_PRIV=$(cat "$WG_KEY_DIR/client.key")
        CLIENT_PUB=$(cat "$WG_KEY_DIR/client.pub")
        SERVER_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
        if [[ -z "$SERVER_IFACE" || ! "$SERVER_IFACE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            warn "Could not detect default network interface — skipping WireGuard"
            warn "Set up WireGuard manually: https://wiki.archlinux.org/title/WireGuard"
        else
        # Try public IP first (for remote VPN access), fall back to LAN IP
        LAN_IP=$(ip -o -4 addr show "$SERVER_IFACE" | awk '{print $4}' | cut -d/ -f1 | head -1)
        SERVER_IP=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
        # Validate IPv4 format — fall back to LAN if garbage
        if ! [[ "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            SERVER_IP="$LAN_IP"
        fi
        if [ "$SERVER_IP" = "$LAN_IP" ]; then
            warn "Could not detect public IP — WireGuard Endpoint set to LAN IP ($LAN_IP)"
            warn "For remote access, update Endpoint in /etc/wireguard/client1.conf with your public IP or DDNS"
        fi

        WG_TMP=$(mktemp)
        chmod 600 "$WG_TMP"
        cat > "$WG_TMP" << WG_SRV
[Interface]
Address = 10.100.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIV
PostUp = nft add table inet wg-nat; nft add chain inet wg-nat forward '{type filter hook forward priority 0; policy accept;}'; nft add rule inet wg-nat forward iifname wg0 accept; nft add chain inet wg-nat postrouting '{type nat hook postrouting priority 100;}'; nft add rule inet wg-nat postrouting oifname "$SERVER_IFACE" masquerade
PostDown = nft delete table inet wg-nat

[Peer]
PublicKey = $CLIENT_PUB
AllowedIPs = 10.100.0.2/32
WG_SRV
        sudo install -m 600 "$WG_TMP" "$WG_CONF"
        rm -f "$WG_TMP"

        CLIENT_CONF=$(mktemp)
        chmod 600 "$CLIENT_CONF"
        cat > "$CLIENT_CONF" << WG_CLIENT
[Interface]
PrivateKey = $CLIENT_PRIV
Address = 10.100.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $SERVER_IP:51820
AllowedIPs = 10.100.0.0/24
PersistentKeepalive = 25
WG_CLIENT

        sudo sysctl -w net.ipv4.ip_forward=1 >> "$LOG_FILE" 2>&1
        echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-wireguard.conf >> "$LOG_FILE" 2>&1
        sudo systemctl enable --now wg-quick@wg0 >> "$LOG_FILE" 2>&1

        sudo install -m 600 "$CLIENT_CONF" /etc/wireguard/client1.conf
        rm -f "$CLIENT_CONF"
        rm -rf "$WG_KEY_DIR"
        log "WireGuard VPN configured on 10.100.0.1:51820"
        fi  # SERVER_IFACE validation
    else
        log "WireGuard already configured at $WG_CONF"
    fi
fi

# ============================================================
# 11. VOICE BACKENDS + DASHBOARD + AUTO-LOAD
# ============================================================
if ! $DRY_RUN; then
    step "Voice, Dashboard & Auto-load"

    # Check if Lemonade server is running
    if lemonade status --json > /dev/null 2>&1; then
        # Install voice backends
        log "Installing voice backends..."
        lemonade backends install kokoro:cpu >> "$LOG_FILE" 2>&1 &
        spinner $! "Installing Kokoro TTS..."
        lemonade backends install whispercpp:vulkan >> "$LOG_FILE" 2>&1 &
        spinner $! "Installing Whisper STT (Vulkan)..."

        # Pull voice models
        log "Downloading voice models..."
        lemonade pull kokoro-v1 >> "$LOG_FILE" 2>&1 &
        spinner $! "Downloading Kokoro TTS model..."
        lemonade pull Whisper-Large-v3-Turbo >> "$LOG_FILE" 2>&1 &
        spinner $! "Downloading Whisper Large v3 Turbo (1.5 GB)..."

        # Pull default NPU model for agents
        lemonade pull gemma3-4b-FLM >> "$LOG_FILE" 2>&1 &
        spinner $! "Downloading Gemma3 4B for NPU..."

        # Set default context size to 32768 (Gaia requires it)
        lemonade config set ctx_size=32768 >> "$LOG_FILE" 2>&1
    else
        warn "Lemonade server not running — skipping voice backends & model downloads"
        warn "Run these manually after reboot: lemonade backends install kokoro:cpu && lemonade backends install whispercpp:vulkan"
    fi
    log "Default context size set to 32768"

    log "Voice backends installed: Kokoro TTS + Whisper STT"

    # Install dashboard
    log "Installing dashboard..."
    sudo mkdir -p /srv/halo-dashboard
    if [ -f "$SCRIPT_DIR/dashboard/index.html" ]; then
        sudo cp "$SCRIPT_DIR/dashboard/index.html" /srv/halo-dashboard/index.html
    fi

    # Install dashboard stats server
    log "Installing dashboard stats server..."
    sudo pacman -S --noconfirm --needed python-psutil >> "$LOG_FILE" 2>&1 || true
    STATS_DIR="$HOME/.local/share/halo-dashboard"
    mkdir -p "$STATS_DIR"
    if [ -f "$SCRIPT_DIR/dashboard/stats-server.py" ]; then
        cp "$SCRIPT_DIR/dashboard/stats-server.py" "$STATS_DIR/stats-server.py"
    fi

    # Create stats server systemd user service
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/halo-stats.service" << STATSVC
[Unit]
Description=halo-ai dashboard stats API
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${STATS_DIR}/stats-server.py
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
STATSVC
    systemctl --user daemon-reload
    systemctl --user enable --now halo-stats.service >> "$LOG_FILE" 2>&1 || true
    log "Stats server installed on :5090"

    # Configure Caddy with reverse proxies
    if [ -f "$SCRIPT_DIR/dashboard/Caddyfile" ]; then
        sudo cp "$SCRIPT_DIR/dashboard/Caddyfile" /etc/caddy/Caddyfile
    else
        sudo tee /etc/caddy/Caddyfile > /dev/null << 'CADDY'
{
	admin "unix//run/caddy/admin.socket"
}

:80 {
	handle /api/* {
		reverse_proxy 127.0.0.1:5090
		uri strip_prefix /api
	}
	root * /srv/halo-dashboard
	file_server
}

:13306 {
	reverse_proxy 127.0.0.1:13305
}

:4201 {
	reverse_proxy 127.0.0.1:4200
}
CADDY
    fi
    sudo systemctl restart caddy >> "$LOG_FILE" 2>&1
    log "Dashboard deployed on :80 — Stats :5090 — Lemonade :13306 — Gaia :4201"

    # Create auto-load script
    sudo tee /usr/local/bin/halo-autoload.sh > /dev/null << 'AUTOLOAD'
#!/bin/bash
# halo-ai core — auto-load default models on boot
# "i'll be back." — the terminator

LOG="$HOME/.local/log/halo-autoload.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG"; }

log "Auto-loading default models..."

# Wait for lemonade to be ready
for i in $(seq 1 30); do
    if lemonade status --json 2>/dev/null | grep -q '"version"'; then
        break
    fi
    sleep 2
done

# Load whisper (STT)
log "Loading Whisper Large v3 Turbo..."
lemonade load Whisper-Large-v3-Turbo --whispercpp vulkan >> "$LOG" 2>&1 || \
    log "Whisper load failed (non-critical)"

# Load kokoro (TTS)
log "Loading Kokoro v1..."
lemonade load kokoro-v1 >> "$LOG" 2>&1 || \
    log "Kokoro load failed (non-critical)"

# Load default LLM on NPU (agents)
log "Loading Gemma3 4B on NPU..."
lemonade load gemma3-4b-FLM --ctx-size 32768 >> "$LOG" 2>&1 || \
    log "NPU model load failed (non-critical)"

log "Auto-load complete."
AUTOLOAD
    sudo chmod +x /usr/local/bin/halo-autoload.sh

    # Create auto-load systemd service
    sudo tee /usr/lib/systemd/system/halo-autoload.service > /dev/null << 'SVCUNIT'
[Unit]
Description=Halo AI Core — Auto-load default models
After=lemonade-server.service
Wants=lemonade-server.service

[Service]
Type=oneshot
User=bcloud
RemainAfterExit=yes
ExecStartPre=/bin/sleep 5
ExecStart=/usr/local/bin/halo-autoload.sh

[Install]
WantedBy=multi-user.target
SVCUNIT
    sudo systemctl daemon-reload
    sudo systemctl enable halo-autoload >> "$LOG_FILE" 2>&1
    log "Auto-load service enabled — voice + NPU models load on every boot"
else
    info "Would install voice backends (Kokoro TTS + Whisper STT)"
    info "Would deploy dashboard on :80 with Caddy reverse proxies"
    info "Would create auto-load service for default models on boot"
fi

# ============================================================
# DONE
# ============================================================
HOSTNAME=$(cat /proc/sys/kernel/hostname)
echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Halo AI Core — Install Done      ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  \"There is no spoon.\" — The Matrix"
echo ""
echo "  ── YOUR UIs ──────────────────────────────────"
echo ""
echo "  Lemonade (chat with LLMs):"
echo "    Local:  http://localhost:13305"
echo "    SSH:    ssh -L 13305:localhost:13305 $HOSTNAME"
echo "            then open http://localhost:13305"
echo ""
echo "  Gaia (manage agents):"
echo "    Local:  http://localhost:4200"
echo "    SSH:    ssh -L 4200:localhost:4200 $HOSTNAME"
echo "            then open http://localhost:4200"
echo ""
echo "  Claude Code (local AI coding agent):"
echo "    lemonade launch claude -m <model-name>"
echo ""

if [ -f /etc/wireguard/wg0.conf ]; then
echo "  ── REMOTE ACCESS (WireGuard VPN) ───────────────"
echo ""
echo "  Phone VPN IP: 10.100.0.2"
echo "  Lemonade:     http://10.100.0.1:13305"
echo "  Gaia:         http://10.100.0.1:4200"
echo "  Show QR:      qrencode -t ansiutf8 < /etc/wireguard/client1.conf"
echo ""
fi

echo "  ── IMPORTANT ─────────────────────────────────"
echo ""
echo "  Reboot your machine to start all services:"
echo ""
echo "    sudo reboot"
echo ""
echo "  Services are enabled and will start automatically on boot."
echo "  They will NOT run until you reboot."
echo ""
echo "  ── NEXT STEPS (after reboot) ──────────────────"
echo ""
echo "  1. Load a model in Lemonade UI"
echo "  2. Start chatting"
echo "  3. Launch Claude Code with local models:"
echo "     lemonade launch claude -m <model-name>"
echo "  4. Deploy core agents (optional):"
echo "     https://github.com/stampby/halo-ai-core/blob/main/docs/wiki/Core-Agents.md"
echo ""
echo "  ── VERIFY ────────────────────────────────────"
echo ""
echo "  ./install.sh --status"
echo ""

log "Installation complete."
log "Full log: $LOG_FILE"
echo ""
