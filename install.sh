#!/bin/bash
# ============================================================
# Halo AI Core — Install Script
# Designed and built by the architect
#
# "I know kung fu." — Neo, The Matrix
#
# Core services for AMD Strix Halo bare-metal AI platform
# Components: ROCm (GPU drivers), Caddy, Lemonade (lemond), Claude Code
# llama.cpp runs Vulkan only — ROCm/HIP is for vLLM, FLM (NPU), PyTorch
# All services route through lemond's built-in router on :13305
# ============================================================
set -euo pipefail

# Validate HOME has no spaces (systemd units embed it)
if [[ "$HOME" =~ [[:space:]] ]]; then
    echo "ERROR: HOME path contains spaces ($HOME) — not supported"
    exit 1
fi

VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Ensure USER is set (may be unset in containers/systemd)
USER="${USER:-$(whoami)}"
export USER
LOG_DIR="${HOME}/.local/log"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/halo-ai-core-install.log"
touch "$LOG_FILE" && chmod 600 "$LOG_FILE"
trap 'rm -f "${WG_TMP:-}" "${CLIENT_CONF:-}" 2>/dev/null; rm -rf "${YAY_TMPDIR:-}" "${WG_KEY_DIR:-}" 2>/dev/null' EXIT INT TERM
DRY_RUN=false
SKIP_ROCM=false
SKIP_CADDY=false
SKIP_LEMONADE=false
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
    echo "  --skip-lemonade Skip Lemonade Server"
    echo "  --skip-claude   Skip Claude Code"
    echo "  --status        Show current install status"
    echo "  -h, --help      Show this help"
    exit 0
}

# Step count calculated dynamically based on skip flags
CURRENT_STEP=0
calculate_steps() {
    TOTAL_STEPS=4  # base + python + wireguard + dashboard (always run)
    $SKIP_ROCM     || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    $SKIP_CADDY    || TOTAL_STEPS=$((TOTAL_STEPS + 1))
    $SKIP_LEMONADE || TOTAL_STEPS=$((TOTAL_STEPS + 1))
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

    # Lemonade (lemond)
    if command -v lemonade &>/dev/null; then
        VER=$(lemonade --version 2>/dev/null || echo "installed")
        echo -e "  Lemonade: ${GREEN}installed${NC} — $VER"
        if systemctl is-active lemonade-server &>/dev/null; then
            echo -e "            ${GREEN}lemond running${NC} on :13305"
            # Show loaded models
            lemonade list 2>/dev/null | head -10 || true
        else
            echo -e "            ${YELLOW}lemond not running${NC}"
        fi
    else
        echo -e "  Lemonade: ${RED}not installed${NC}"
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
    for svc in caddy sshd lemonade-server halo-autoload; do
        STATUS=$(systemctl is-enabled "$svc" 2>/dev/null || true); STATUS=${STATUS:-missing}
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
        --skip-lemonade) SKIP_LEMONADE=true; shift ;;
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
echo "║   Halo AI Core v${VERSION} — Installer   ║"
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
BASE_PKGS="base-devel git openssh networkmanager curl wget htop nano nodejs npm uv"

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
# 3. CADDY (dashboard only — lemond handles all API routing)
# ============================================================
if ! $SKIP_CADDY; then
    step "Caddy (Dashboard)"

    if $DRY_RUN; then
        info "Would install: caddy (dashboard on :80 only)"
    else
        sudo pacman -S --needed --noconfirm caddy >> "$LOG_FILE" 2>&1

        # Clean stale configs from previous installs
        sudo rm -f /etc/caddy/conf.d/*.caddy 2>/dev/null
        sudo mkdir -p /etc/caddy/conf.d

        # Caddy serves the dashboard on :80 — all API routing goes through lemond on :13305
        if [ -f "$SCRIPT_DIR/dashboard/Caddyfile" ]; then
            sudo cp "$SCRIPT_DIR/dashboard/Caddyfile" /etc/caddy/Caddyfile
        else
            sudo tee /etc/caddy/Caddyfile > /dev/null << 'CADDYFILE'
# Halo AI Core — Caddy
# "There is no spoon." — Neo
# Dashboard on :80 — all API routing through lemond :13305

{
    admin "unix//run/caddy/admin.socket"
}

:80 {
    @local remote_ip 127.0.0.1 10.0.0.0/24 10.100.0.0/24

    # Stats JSON (static file, updated every 5s)
    handle /stats.json {
        root * /srv/halo-dashboard
        file_server
        header Cache-Control "no-cache"
    }

    # Dashboard (static files)
    root * /srv/halo-dashboard
    file_server
}

import /etc/caddy/conf.d/*.caddy
CADDYFILE
        fi

        sudo systemctl enable --now caddy >> "$LOG_FILE" 2>&1
        log "Caddy installed — dashboard on :80"
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

# ============================================================
# 5. LEMONADE SERVER (lemond — the core, all services route through here)
# ============================================================
if ! $SKIP_LEMONADE; then
    step "Lemonade Server (lemond)"

    if $DRY_RUN; then
        info "Would install lemonade-server from AUR"
        info "Would install backends: llamacpp:vulkan, whispercpp:vulkan, kokoro:cpu"
        info "All API routing handled by lemond's built-in router on :13305"
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
                (cd "$YAY_TMPDIR" && git clone https://aur.archlinux.org/yay.git yay >> "$LOG_FILE" 2>&1 && cd yay && makepkg -si --noconfirm >> "$LOG_FILE" 2>&1)
                rm -rf "$YAY_TMPDIR"
                AUR_HELPER="yay"
            fi

            $AUR_HELPER -S --needed --noconfirm lemonade-server >> "$LOG_FILE" 2>&1 &
            spinner $! "Building lemonade-server from AUR (C++ native — this takes a minute)..."
        fi

        # Fix libwebsockets soname mismatch (Arch updates .so.20 → .so.21, breaks lemond)
        for SO_NEW in /usr/lib/libwebsockets.so.*; do
            [ -f "$SO_NEW" ] || continue
            SO_VER=$(basename "$SO_NEW" | grep -oP '\.\d+$' | tr -d '.')
            if [ -n "$SO_VER" ] && [ ! -f /usr/lib/libwebsockets.so.20 ]; then
                sudo ln -sf "$SO_NEW" /usr/lib/libwebsockets.so.20
                log "Fixed libwebsockets soname: $(basename "$SO_NEW") → libwebsockets.so.20"
                break
            fi
        done

        # Enable and start the daemon
        sudo systemctl daemon-reload
        sudo systemctl enable --now lemonade-server >> "$LOG_FILE" 2>&1 || true

        # Wait for lemond to be ready
        log "Waiting for lemond to start..."
        for i in $(seq 1 30); do
            if lemonade status --json > /dev/null 2>&1; then break; fi
            sleep 1
        done

        # Install backends through lemond's built-in router
        if lemonade status --json > /dev/null 2>&1; then
            log "Installing backends through lemond..."

            lemonade backends install llamacpp:vulkan >> "$LOG_FILE" 2>&1 &
            spinner $! "Installing llamacpp:vulkan backend..."

            lemonade backends install kokoro:cpu >> "$LOG_FILE" 2>&1 &
            spinner $! "Installing Kokoro TTS backend..."

            lemonade backends install whispercpp:vulkan >> "$LOG_FILE" 2>&1 &
            spinner $! "Installing Whisper STT backend (Vulkan)..."

            # Pull voice models
            lemonade pull kokoro-v1 >> "$LOG_FILE" 2>&1 &
            spinner $! "Downloading Kokoro TTS model..."

            lemonade pull Whisper-Large-v3-Turbo >> "$LOG_FILE" 2>&1 &
            spinner $! "Downloading Whisper Large v3 Turbo (1.5 GB)..."

            # Pull default NPU model (optional, non-fatal)
            (lemonade pull gemma3-4b-FLM >> "$LOG_FILE" 2>&1 || \
             lemonade pull user.gemma3-4b-FLM >> "$LOG_FILE" 2>&1 || true) &
            spinner $! "Downloading Gemma3 4B for NPU (optional)..."

            # Set default context size
            lemonade config set ctx_size=32768 >> "$LOG_FILE" 2>&1

            log "Backends installed — all routing through lemond on :13305"
        else
            warn "lemond not responding — backends will need manual install after reboot"
            warn "Run: lemonade backends install llamacpp:vulkan && lemonade backends install kokoro:cpu && lemonade backends install whispercpp:vulkan"
        fi

        VER=$(lemonade --version 2>/dev/null || echo "installed")
        log "Lemonade Server $VER"
        log "Built-in router on :13305 — OpenAI, Anthropic, Ollama compatible"
        log "Web UI:        http://localhost:13305"
        log "OpenAI API:    http://localhost:13305/v1/chat/completions"
        log "Anthropic API: http://localhost:13305/v1/messages"
    fi
else
    warn "Skipping Lemonade Server"
fi

# ============================================================
# 6. CLAUDE CODE (via Lemonade)
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
            log "Launch with: lemonade launch claude -m <model-name>"
        else
            warn "Lemonade CLI not found — install Lemonade Server first"
        fi
    fi
else
    warn "Skipping Claude Code"
fi

# ============================================================
# 7. WIREGUARD — Remote Access via QR Code
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
            # Use LAN IP for WireGuard endpoint (no external IP lookups — privacy first)
            LAN_IP=$(ip -o -4 addr show "$SERVER_IFACE" | awk '{print $4}' | cut -d/ -f1 | head -1)
            SERVER_IP="$LAN_IP"
            warn "WireGuard Endpoint set to LAN IP ($LAN_IP)"
            warn "For remote access, update Endpoint in /etc/wireguard/client1.conf with your public IP or DDNS"

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

            sudo sysctl -w net.ipv4.ip_forward=1 >> "$LOG_FILE" 2>&1 || true
            echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-wireguard.conf >> "$LOG_FILE" 2>&1
            sudo systemctl enable --now wg-quick@wg0 >> "$LOG_FILE" 2>&1 || true

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
# 8. DASHBOARD & AUTO-LOAD
# ============================================================
step "Dashboard & Auto-load"
if $DRY_RUN; then
    info "Would deploy dashboard on :80"
    info "Would create auto-load service for voice + NPU models on boot"
else
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
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now halo-stats.service >> "$LOG_FILE" 2>&1 || true
    log "Stats server installed on :5090"

    # Reload Caddy with dashboard config
    sudo systemctl reload caddy >> "$LOG_FILE" 2>&1 || sudo systemctl restart caddy >> "$LOG_FILE" 2>&1 || true
    log "Dashboard deployed on :80"

    # Create auto-load script (loads voice + NPU models through lemond on boot)
    sudo tee /usr/local/bin/halo-autoload.sh > /dev/null << 'AUTOLOAD'
#!/bin/bash
# halo-ai core — auto-load default models on boot (all through lemond)
# "i'll be back." — the terminator

LOG="$HOME/.local/log/halo-autoload.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOG"; }

log "Auto-loading default models through lemond..."

# Wait for lemond to be ready
for i in $(seq 1 30); do
    if lemonade status --json 2>/dev/null | grep -q '"version"'; then
        break
    fi
    sleep 2
done

# Load whisper (STT) through lemond
log "Loading Whisper Large v3 Turbo..."
lemonade load Whisper-Large-v3-Turbo --whispercpp vulkan >> "$LOG" 2>&1 || \
    log "Whisper load failed (non-critical)"

# Load kokoro (TTS) through lemond
log "Loading Kokoro v1..."
lemonade load kokoro-v1 >> "$LOG" 2>&1 || \
    log "Kokoro load failed (non-critical)"

# Load default LLM on NPU (agents) through lemond
log "Loading Gemma3 4B on NPU..."
lemonade load gemma3-4b-FLM --ctx-size 32768 >> "$LOG" 2>&1 || \
  lemonade load user.gemma3-4b-FLM --ctx-size 32768 >> "$LOG" 2>&1 || \
    log "NPU model load failed (non-critical)"

log "Auto-load complete."
AUTOLOAD
    sudo chmod +x /usr/local/bin/halo-autoload.sh

    # Create auto-load systemd service
    sudo tee /usr/lib/systemd/system/halo-autoload.service > /dev/null << SVCUNIT
[Unit]
Description=Halo AI Core — Auto-load default models through lemond
After=lemonade-server.service
Wants=lemonade-server.service

[Service]
Type=oneshot
User=${USER}
RemainAfterExit=yes
ExecStartPre=/bin/sleep 5
ExecStart=/usr/local/bin/halo-autoload.sh

[Install]
WantedBy=multi-user.target
SVCUNIT
    sudo systemctl daemon-reload
    sudo systemctl enable halo-autoload >> "$LOG_FILE" 2>&1
    log "Auto-load service enabled — voice + NPU models load through lemond on every boot"
fi

# ============================================================
# CLEANUP — remove stale services from previous installs
# ============================================================
if ! $DRY_RUN; then
    # Remove old services that are now handled by lemond
    for old_svc in vllm-server lemonade lemonade-ui gaia gaia-ui; do
        if systemctl is-enabled "$old_svc" &>/dev/null; then
            sudo systemctl disable --now "$old_svc" >> "$LOG_FILE" 2>&1 || true
            log "Disabled stale service: $old_svc (now handled by lemond)"
        fi
        sudo rm -f "/usr/lib/systemd/system/${old_svc}.service" 2>/dev/null
    done
    # Remove old Caddy conf.d proxies (lemond handles routing)
    sudo rm -f /etc/caddy/conf.d/llm-api.caddy 2>/dev/null
    sudo rm -f /etc/caddy/conf.d/lemonade-ui.caddy 2>/dev/null
    sudo rm -f /etc/caddy/conf.d/gaia-ui.caddy 2>/dev/null
    sudo rm -f /etc/caddy/conf.d/gaia-api.caddy 2>/dev/null
    sudo rm -f /etc/caddy/conf.d/llama.caddy 2>/dev/null
    sudo systemctl daemon-reload
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
echo "  ── EVERYTHING RUNS THROUGH LEMOND ──────────────"
echo ""
echo "  Lemonade (web UI + all APIs):"
echo "    http://localhost:13305"
echo "    SSH: ssh -L 13305:localhost:13305 $HOSTNAME"
echo ""
echo "  Built-in router on :13305 serves:"
echo "    OpenAI API:    /v1/chat/completions"
echo "    Anthropic API: /v1/messages"
echo "    Ollama API:    /api/chat"
echo "    Web UI:        / (browser)"
echo ""
echo "  Claude Code (local AI coding agent):"
echo "    lemonade launch claude -m <model-name>"
echo ""
echo "  Dashboard:"
echo "    http://localhost:80"
echo ""

if [ -f /etc/wireguard/wg0.conf ]; then
echo "  ── REMOTE ACCESS (WireGuard VPN) ───────────────"
echo ""
echo "  Phone VPN IP: 10.100.0.2"
echo "  Lemonade:     http://10.100.0.1:13305"
echo "  Dashboard:    http://10.100.0.1"
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
echo "  1. Open http://localhost:13305 — load a model, start chatting"
echo "  2. Launch Claude Code with local models:"
echo "     lemonade launch claude -m <model-name>"
echo "  3. Check status:"
echo "     ./install.sh --status"
echo ""

log "Installation complete."
log "Full log: $LOG_FILE"
echo ""
