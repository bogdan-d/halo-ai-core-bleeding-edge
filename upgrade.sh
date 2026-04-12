#!/bin/bash
# ============================================================
# Halo AI Core — Bleeding Edge Upgrade
# Designed and built by the architect
#
# "One does not simply walk into Mordor." — Boromir
#
# Upgrades a stable halo-ai-core install with:
#   - Linux 7.0-rc kernel (NPU/XDNA2 support)
#   - Zen 5 AVX-512 + Polly compiler optimizations
#   - llama.cpp Vulkan rebuild with Zen 5 flags (h/t u/Look_0ver_There)
#   - Speculative decoding config
#
# REQUIRES: a working halo-ai-core install + btrfs
# ============================================================
set -e

VERSION="0.1.0"
LOG_FILE="$(mktemp /tmp/halo-bleeding-edge-XXXXXX.log)"
DRY_RUN=false
SKIP_KERNEL=false
SKIP_REBUILD=false
SKIP_NPU=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_STEPS=5
CURRENT_STEP=0

progress_bar() {
    local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((pct / 5))
    local empty=$((20 - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "${RED}  [${bar}] ${pct}% — Step ${CURRENT_STEP}/${TOTAL_STEPS}${NC}"
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  ▸ Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
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
        printf "\r  ${RED}${spin:i++%${#spin}:1}${NC} %s" "$msg"
        sleep 0.1
    done
    printf "\r  ${GREEN}✓${NC} %s\n" "$msg"
}

log() { echo -e "  ${GREEN}✓${NC} $1"; echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; echo "[$(date '+%H:%M:%S')] WARN: $1" >> "$LOG_FILE"; }
err() { echo -e "  ${RED}✗${NC} $1"; echo "[$(date '+%H:%M:%S')] ERROR: $1" >> "$LOG_FILE"; }
info() { echo -e "  ${BLUE}→${NC} $1"; }

usage() {
    echo "Halo AI Core — Bleeding Edge Upgrade v${VERSION}"
    echo ""
    echo "Usage: ./upgrade.sh [options]"
    echo ""
    echo "Options:"
    echo "  --dry-run         Show what would happen"
    echo "  --skip-kernel     Skip kernel 7.0-rc install"
    echo "  --skip-rebuild    Skip llama.cpp rebuild"
    echo "  --skip-npu        Skip NPU configuration"
    echo "  -h, --help        Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --skip-kernel) SKIP_KERNEL=true; shift ;;
        --skip-rebuild) SKIP_REBUILD=true; shift ;;
        --skip-npu) SKIP_NPU=true; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown: $1"; usage ;;
    esac
done

echo ""
echo -e "${RED}╔══════════════════════════════════════════╗${NC}"
echo -e "${RED}║  Halo AI Core — BLEEDING EDGE v${VERSION}     ║${NC}"
echo -e "${RED}║  ⚠  You have been warned.                ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════╝${NC}"
echo ""

if $DRY_RUN; then
    warn "DRY RUN — nothing will be modified"
    echo ""
fi

# ============================================================
# PRE-FLIGHT CHECKS
# ============================================================
if [ ! -f /usr/local/bin/llama-server ]; then
    err "halo-ai-core not detected. Install stable first:"
    echo "  https://github.com/stampby/halo-ai-core"
    exit 1
fi

if ! command -v btrfs &>/dev/null; then
    err "btrfs not found. Bleeding edge requires btrfs for snapshots."
    exit 1
fi

FILESYSTEM=$(df -T / | tail -1 | awk '{print $2}')
if [ "$FILESYSTEM" != "btrfs" ]; then
    err "Root filesystem is $FILESYSTEM, not btrfs. Cannot snapshot."
    exit 1
fi

log "Pre-flight passed — stable install detected, btrfs confirmed"

# ============================================================
# 1. SNAPSHOT
# ============================================================
step "Snapshot (safety net)"

SNAP_NAME="pre-bleeding-edge-$(date +%Y-%m-%d-%H%M)"

if $DRY_RUN; then
    info "Would create snapshot: /.snapshots/$SNAP_NAME"
else
    sudo mkdir -p /.snapshots
    sudo btrfs subvolume snapshot / "/.snapshots/$SNAP_NAME"
    log "Snapshot saved: /.snapshots/$SNAP_NAME"
    echo ""
    echo "  To rollback if anything breaks:"
    echo "    sudo mount /dev/nvme0n1p2 -o subvolid=5 /mnt"
    echo "    sudo mv /mnt/@ /mnt/@.broken"
    echo "    sudo btrfs subvolume snapshot /mnt/.snapshots/$SNAP_NAME /mnt/@"
    echo "    sudo umount /mnt && sudo reboot"
    echo ""
fi

# ============================================================
# 2. KERNEL 7.0-RC
# ============================================================
if ! $SKIP_KERNEL; then
    step "Linux 7.0-rc Kernel (XDNA2 / NPU)"

    if $DRY_RUN; then
        info "Would install linux-mainline from AUR"
    else
        # Need an AUR helper
        if ! command -v paru &>/dev/null && ! command -v yay &>/dev/null; then
            log "Installing paru (AUR helper)..."
            sudo pacman -S --needed --noconfirm base-devel 2>&1 | sudo tee -a "$LOG_FILE" >/dev/null
            PARU_BUILD=$(mktemp -d /tmp/paru-build-XXXXXX)
            git clone https://aur.archlinux.org/paru.git "$PARU_BUILD" >> "$LOG_FILE" 2>&1
            cd "$PARU_BUILD" && makepkg -si --noconfirm >> "$LOG_FILE" 2>&1
            cd - >/dev/null
            rm -rf "$PARU_BUILD"
        fi

        AUR_HELPER="$(command -v paru || command -v yay)"

        log "Building linux-mainline (this will take a while)..."
        "$AUR_HELPER" -S --noconfirm linux-mainline linux-mainline-headers >> "$LOG_FILE" 2>&1 &
        spinner $! "Compiling kernel 7.0-rc (go make dinner)..."

        # Update GRUB/systemd-boot
        if [ -f /boot/grub/grub.cfg ]; then
            sudo grub-mkconfig -o /boot/grub/grub.cfg >> "$LOG_FILE" 2>&1
            log "GRUB updated — linux-mainline added to boot menu"
        elif [ -d /boot/loader ]; then
            log "systemd-boot detected — kernel should auto-appear"
        fi

        log "Kernel 7.0-rc installed — reboot to activate"
        warn "After reboot, select linux-mainline from boot menu"
    fi
else
    warn "Skipping kernel upgrade"
fi

# ============================================================
# 3. REBUILD LLAMA.CPP WITH ZEN 5 FLAGS
# ============================================================
if ! $SKIP_REBUILD; then
    step "Rebuild llama.cpp (Vulkan + Zen 5 AVX-512)"

    if $DRY_RUN; then
        info "Would rebuild llama.cpp Vulkan only with Zen 5 optimizations"
        info "(h/t u/Look_0ver_There — Vulkan only, no HIP)"
    else
        cd "$HOME/llama.cpp"
        git pull >> "$LOG_FILE" 2>&1

        rm -rf build
        cmake -B build \
            -DGGML_VULKAN=ON \
            -DGGML_HIP=OFF \
            -DGGML_CUDA=OFF \
            -DCMAKE_BUILD_TYPE=Release \
            -DLLAMA_CURL=ON \
            -DCMAKE_C_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq" \
            -DCMAKE_CXX_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq" \
            >> "$LOG_FILE" 2>&1

        cmake --build build --config Release -j"$(nproc)" >> "$LOG_FILE" 2>&1 &
        spinner $! "Compiling llama.cpp with Zen 5 flags (the big one)..."

        sudo systemctl stop llama-server.service 2>/dev/null || true

        # binary location varies by llama.cpp version
        BIN_DIR="build/bin"
        if [ ! -f "$BIN_DIR/llama-server" ]; then
            # newer versions may place binaries in build/tools/
            BIN_DIR=$(dirname "$(find build -name 'llama-server' -type f 2>/dev/null | head -1)" 2>/dev/null)
        fi
        if [ -z "$BIN_DIR" ] || [ "$BIN_DIR" = "." ] || [ ! -f "$BIN_DIR/llama-server" ]; then
            err "llama-server binary not found after build — check $LOG_FILE"
            exit 1
        fi
        log "Binaries found in: $BIN_DIR"

        sudo cp "$BIN_DIR/llama-server" /usr/local/bin/
        sudo cp "$BIN_DIR/llama-cli" /usr/local/bin/ 2>/dev/null || true
        sudo cp "$BIN_DIR/llama-bench" /usr/local/bin/ 2>/dev/null || \
            sudo cp "$(find build -name 'llama-bench' -type f 2>/dev/null | head -1)" /usr/local/bin/ 2>/dev/null || true

        log "llama.cpp rebuilt — Vulkan only + Zen 5 AVX-512 (h/t u/Look_0ver_There)"
    fi
else
    warn "Skipping llama.cpp rebuild"
fi

# ============================================================
# 4. NPU CONFIGURATION
# ============================================================
if ! $SKIP_NPU; then
    step "NPU Configuration (XDNA2)"

    if $DRY_RUN; then
        info "Would configure NPU access and verify /dev/accel0"
    else
        KERNEL_VER=$(uname -r)
        KERNEL_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)

        if [ "$KERNEL_MAJOR" -lt 7 ]; then
            warn "Kernel $KERNEL_VER detected — NPU requires 7.0+"
            warn "Reboot into linux-mainline first, then re-run with --skip-kernel --skip-rebuild"
            info "NPU configuration will be applied after kernel upgrade"
        else
            if [ -c /dev/accel/accel0 ] || [ -c /dev/accel0 ]; then
                log "NPU device found: $(ls /dev/accel/accel0 /dev/accel0 2>/dev/null | head -1)"

                # Add user to render group for NPU access
                sudo usermod -aG render "$USER"

                # Verify amdxdna driver
                if lsmod | grep -q amdxdna; then
                    log "amdxdna driver loaded"
                else
                    warn "amdxdna driver not loaded — may need firmware"
                    sudo modprobe amdxdna 2>/dev/null || warn "modprobe amdxdna failed"
                fi

                log "NPU configured — ready for offload testing"
            else
                warn "NPU device not found at /dev/accel/accel0 or /dev/accel0"
                info "Check: ls /dev/accel/ && lsmod | grep amdxdna"
            fi
        fi
    fi
else
    warn "Skipping NPU configuration"
fi

# ============================================================
# 5. BENCHMARKS
# ============================================================
step "Benchmark (prove it)"

if $DRY_RUN; then
    info "Would run llama-bench with optimized binary"
else
    source /etc/profile.d/rocm.sh 2>/dev/null || true
    export HSA_OVERRIDE_GFX_VERSION=11.5.1
    export ROCBLAS_USE_HIPBLASLT=1

    # Find the first available model
    MODEL=$(find ~/models -name "*.gguf" -size +1G 2>/dev/null | head -1)

    if [ -n "$MODEL" ]; then
        echo ""
        log "Running benchmark with: $(basename "$MODEL")"
        echo ""
        llama-bench -m "$MODEL" -ngl 99 -p 512 -n 128
        echo ""
        log "Benchmark complete — compare these to your stable numbers"
    else
        warn "No models found in ~/models/ — download one and run:"
        echo "  llama-bench -m ~/models/YOUR_MODEL.gguf -ngl 99 -p 512 -n 128"
    fi
fi

# ============================================================
# DONE
# ============================================================
echo ""
echo -e "${RED}╔══════════════════════════════════════════╗${NC}"
echo -e "${RED}║   Bleeding Edge — Upgrade Complete       ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  what changed:"
echo "    → llama.cpp rebuilt — Vulkan only + Zen 5 AVX-512 (h/t u/Look_0ver_There)"
echo "    → kernel 7.0-rc for NPU/XDNA2 support"
echo "    → NPU configured for FLM offload"
echo ""

KERNEL_VER=$(uname -r)
KERNEL_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
if [ "$KERNEL_MAJOR" -lt 7 ] && ! $SKIP_KERNEL; then
    echo -e "  ${YELLOW}⚠ REBOOT REQUIRED${NC}"
    echo "    select linux-mainline from your boot menu"
    echo "    then re-run: ./upgrade.sh --skip-kernel --skip-rebuild"
    echo "    to configure the NPU"
    echo ""
fi

echo "  rollback:"
echo "    snapshot: /.snapshots/$SNAP_NAME"
echo ""
echo "  \"not all those who wander are lost.\" — Tolkien"
echo ""
log "Bleeding edge upgrade complete."
log "Full log: $LOG_FILE"
