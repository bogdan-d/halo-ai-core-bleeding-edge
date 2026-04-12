#!/bin/bash
# halo-ai core — system stats JSON for dashboard

# CPU
CPU_PCT=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' 2>/dev/null || echo "0")
CPU_TEMP=$(cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
CPU_TEMP=${CPU_TEMP:-0}
CPU_TEMP=$((CPU_TEMP / 1000))
CPU_NAME=$(lscpu 2>/dev/null | grep "Model name" | sed 's/.*: *//')
CORES=$(nproc)

# Memory
read MEM_TOTAL MEM_AVAIL <<< $(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.0f %.0f", t*1024, a*1024}' /proc/meminfo)
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_TOTAL_GB=$(awk '/MemTotal/{printf "%.1f", $2/1048576}' /proc/meminfo)
MEM_PCT=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1f", (t-a)*100/t}' /proc/meminfo)

# GPU
GPU_TEMP=$(cat /sys/class/drm/card1/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -1)
GPU_TEMP=${GPU_TEMP:-0}
GPU_TEMP=$((GPU_TEMP / 1000))
GPU_BUSY=$(cat /sys/class/drm/card1/device/gpu_busy_percent 2>/dev/null || echo "0")
GPU_VRAM_USED=$(cat /sys/class/drm/card1/device/mem_info_vram_used 2>/dev/null || echo "0")
GPU_VRAM_TOTAL=$(cat /sys/class/drm/card1/device/mem_info_vram_total 2>/dev/null || echo "0")

# Disk
read DISK_TOTAL DISK_USED DISK_PCT <<< $(df / | tail -1 | awk '{printf "%d %d %s", $2*1024, $3*1024, $5}')
DISK_PCT=${DISK_PCT%\%}

# NPU
NPU_ONLINE=$([ -e /dev/accel/accel0 ] || [ -e /dev/accel0 ] && echo "true" || echo "false")

# Uptime
UPTIME=$(awk '{printf "%d", $1}' /proc/uptime)

# Network
RX=$(cat /sys/class/net/*/statistics/rx_bytes 2>/dev/null | awk '{s+=$1}END{print s+0}')
TX=$(cat /sys/class/net/*/statistics/tx_bytes 2>/dev/null | awk '{s+=$1}END{print s+0}')

cat << JSON
{
  "hw": {
    "cpu": "$CPU_NAME",
    "cores": $CORES,
    "ram_total": $MEM_TOTAL,
    "gpu": "Radeon 8060S",
    "vram_total": $GPU_VRAM_TOTAL,
    "npu": "XDNA2 8-col",
    "disk_total": $DISK_TOTAL
  },
  "cpu": {"usage": $CPU_PCT, "temp": $CPU_TEMP},
  "ram": {"total": $MEM_TOTAL, "used": $MEM_USED, "percent": $MEM_PCT},
  "disk": {"total": $DISK_TOTAL, "used": $DISK_USED, "percent": $DISK_PCT},
  "gpu": {"usage": $GPU_BUSY, "temp": $GPU_TEMP, "vram_used": $GPU_VRAM_USED, "vram_total": $GPU_VRAM_TOTAL},
  "npu_online": $NPU_ONLINE,
  "uptime": $UPTIME,
  "net": {"rx": $RX, "tx": $TX}
}
JSON
