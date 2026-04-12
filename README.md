<div align="center">

<picture>
  <img src="https://raw.githubusercontent.com/stampby/halo-ai-core/main/assets/halo-ai.svg" alt="halo ai core" width="200">
</picture>

# halo-ai core — bleeding edge

### linux 7.0-rc · npu acceleration · experimental optimizations

**if you're here, you know what you're doing.**

[![Bleeding Edge](https://img.shields.io/badge/⚠_Bleeding_Edge-ff4444?style=flat&logoColor=white)](https://github.com/stampby/halo-ai-core-bleeding-edge)
[![Stable Version](https://img.shields.io/badge/Stable-halo--ai--core-00d4ff?style=flat)](https://github.com/stampby/halo-ai-core)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?style=flat&logo=archlinux&logoColor=white)](https://archlinux.org)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

---

> **stable first.** if you haven't installed [halo-ai-core](https://github.com/stampby/halo-ai-core) yet, start there. this repo builds on top of a working stable install. do not start here.

---

## what this is

this repo takes a stable halo-ai-core install and pushes it to the limit:

- **linux 7.0-rc kernel** — XDNA2 driver support for the NPU
- **npu acceleration** — offload workloads to the neural processing unit via Lemonade SDK + FLM
- **experimental compiler flags** — zen 5 avx-512, polly optimizations
- **llama.cpp vulkan only** — zen 5 avx-512 optimized rebuild *(h/t u/Look_0ver_There)*
- **speculative decoding** — draft model acceleration
- **1-bit model support** — bonsai Q1_0 models via prism-ml llama.cpp fork

these are the optimizations that produced the highest numbers we've ever seen on strix halo. but they come with risk. kernels can panic. drivers can crash. that's why this is separate from core.

## requirements

- a working [halo-ai-core](https://github.com/stampby/halo-ai-core) install
- btrfs snapshots enabled (so you can roll back)
- comfort with kernel compilation and troubleshooting
- an amd strix halo machine (ryzen ai max+ 395, gfx1151)

## install

```bash
# TAKE A SNAPSHOT FIRST — seriously
sudo btrfs subvolume snapshot / /.snapshots/pre-bleeding-edge

# then
git clone https://github.com/stampby/halo-ai-core-bleeding-edge.git
cd halo-ai-core-bleeding-edge
./upgrade.sh --dry-run    # see what happens first
./upgrade.sh --skip-kernel # if you're already on 7.0-rc
./upgrade.sh              # full upgrade including kernel
```

## benchmarks — verified 2026-04-09

all numbers captured live on strix halo hardware. no cherry-picking. no tricks. reproducible by anyone with the same hardware following the steps in [REPRODUCE.md](REPRODUCE.md).

### stable (halo-ai-core, kernel 6.19.11)

| model | test | prompt t/s | gen t/s |
|-------|------|-----------|---------|
| qwen3-30B-A3B Q4_K_M | short (13→256) | 251.7 | 73.0 |
| qwen3-30B-A3B Q4_K_M | medium (75→512) | 494.3 | 72.5 |
| qwen3-30B-A3B Q4_K_M | long (39→1024) | 385.9 | 71.9 |
| qwen3-30B-A3B Q4_K_M | sustained (54→2048) | 437.0 | 70.5 |

NPU: not available. FLM: not available. kernel 6.19 lacks XDNA2 driver.

### bleeding edge (this repo, kernel 7.0-rc7 + zen5 flags)

**GPU — Vulkan only (h/t u/Look_0ver_There)**

| model | test | t/s |
|-------|------|-----|
| qwen3-coder-30B-A3B Q4_K_M | pp64 (prompt) | **459.9** |
| qwen3-coder-30B-A3B Q4_K_M | pp512 (prompt) | **1,071.2** |
| qwen3-coder-30B-A3B Q4_K_M | tg128 (gen) | **64.3** |
| qwen3-coder-30B-A3B Q4_K_M | tg512 (gen) | **61.6** |

17.3 GB model, MoE with 3B active per token. rock solid 61-64 t/s with zero degradation over 512 tokens.

**NPU — FLM via Lemonade SDK (NEW — only possible on 7.0-rc)**

| model | size | gen t/s |
|-------|------|---------|
| gemma3-1b-FLM | 1.2 GB | **34.9** |
| gemma3-4b-FLM | 3.6 GB | **17.0** |
| deepseek-r1-8b-FLM | 5.4 GB | **10.5** |
| deepseek-r1-0528-8b-FLM | 5.6 GB | **10.5** |

NPU runs independently from GPU. zero GPU memory used. the whole point is running always-on agents on NPU while GPU handles big models.

**1-bit models — Bonsai Q1_0 (CPU, AVX-512)**

| model | size | prompt t/s | gen t/s |
|-------|------|-----------|---------|
| bonsai-1.7B | 231 MB | 17.9 | **13.4** |
| bonsai-4B | 540 MB | 6.8 | **5.7** |
| bonsai-8B | 1.07 GB | 3.6 | **3.1** |

CPU only via [prism-ml llama.cpp fork](https://github.com/Mintplex-Labs/prism-ml-llama.cpp). on ROCm GPU these same models hit 103-260 t/s (see [ryzen reference benchmarks](#ryzen-reference)).

**system benchmarks**

| test | result |
|------|--------|
| CPU (sysbench 32t, prime 50000) | 10,328 events/sec |
| memory bandwidth (sysbench 16t) | 87,088 MiB/sec |
| NVMe read (fio 4K random) | 569K IOPS, 2,224 MiB/s |
| NVMe write (fio 4K random) | 569K IOPS, 2,223 MiB/s |
| NVMe p99 latency | 5 μs |

### ryzen reference

same halo-ai-core stack on ryzen with ROCm/Vulkan GPU. included for comparison.

| model | prompt t/s | gen t/s |
|-------|-----------|---------|
| qwen3-30B-A3B Q4_K_M | 209.7 | 88.7 |
| bonsai-8B (1-bit, GPU) | 330.1 | 103.7 |
| bonsai-4B (1-bit, GPU) | 524.5 | 148.3 |
| bonsai-1.7B (1-bit, GPU) | 1,044.1 | 260.0 |
| FLUX schnell 1024x1024 | — | 1.0s (4 steps) |
| dreamshaper 8 512x512 | — | 6.0s (25 steps) |
| LTX-Video 2B 512x320 | — | 20.6s (25f/20 steps) |

## what changes

### 1. linux 7.0-rc kernel

the stock arch kernel (6.19.x) doesn't support XDNA2 for the NPU. kernel 7.0-rc adds:

- `/dev/accel/accel0` NPU device with 8 XDNA2 columns
- `amdxdna` driver v0.6 with firmware 1.1.2.65
- improved GPU memory scheduling for gfx1151

```bash
# built from AUR
paru -S linux-mainline linux-mainline-headers
# reboot and select linux-mainline from boot menu
```

### 2. zen 5 compiler optimizations

rebuild llama.cpp Vulkan only with Zen 5 flags *(h/t u/Look_0ver_There — no HIP, no ROCm for llama.cpp)*:

```bash
cmake -B build \
    -DGGML_VULKAN=ON \
    -DGGML_HIP=OFF \
    -DGGML_CUDA=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLAMA_CURL=ON \
    -DCMAKE_C_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq" \
    -DCMAKE_CXX_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq"
```

ROCm/HIP stays installed for vLLM, FLM (NPU), PyTorch — just not for llama.cpp inference.

### 7. lemonade SDK + FLM NPU backend

purpose-built NPU inference via [Lemonade SDK](https://github.com/lemonade-sdk/lemonade):

```bash
# install (arch linux)
sudo pacman -S xrt-plugin-amdxdna fastflowlm

# fix memlock for NPU (required)
echo "bcloud soft memlock unlimited" | sudo tee -a /etc/security/limits.d/99-npu-memlock.conf
echo "bcloud hard memlock unlimited" | sudo tee -a /etc/security/limits.d/99-npu-memlock.conf

# systemd service memlock
sudo mkdir -p /etc/systemd/system/lemonade-server.service.d
echo -e "[Service]\nLimitMEMLOCK=infinity" | sudo tee /etc/systemd/system/lemonade-server.service.d/memlock.conf
sudo systemctl daemon-reload

# enable and start
sudo systemctl enable --now lemonade-server

# verify NPU
flm validate
# should show: NPU with 8 columns, firmware 1.1.0.0+, memlock unlimited

# load a model on NPU
lemonade load deepseek-r1-0528-8b-FLM --ctx-size 4096
```

### 8. bonsai 1-bit models

true ternary weight (Q1_0) models from [Prism ML](https://huggingface.co/prism-ml):

```bash
# clone the prism-ml fork (standard llama.cpp lacks Q1_0 kernels)
git clone https://github.com/Mintplex-Labs/prism-ml-llama.cpp.git
cd prism-ml-llama.cpp
cmake -B build -DGGML_AVX512=ON -DGGML_AVX512_VNNI=ON -DGGML_AVX512_BF16=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# download models
mkdir -p ~/models/bonsai
curl -L -o ~/models/bonsai/Bonsai-8B.gguf \
  https://huggingface.co/prism-ml/Bonsai-8B-gguf/resolve/main/Bonsai-8B.gguf
curl -L -o ~/models/bonsai/Bonsai-4B.gguf \
  https://huggingface.co/prism-ml/Bonsai-4B-gguf/resolve/main/Bonsai-4B.gguf
curl -L -o ~/models/bonsai/Bonsai-1.7B.gguf \
  https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B.gguf

# benchmark
./build/bin/llama-bench -m ~/models/bonsai/Bonsai-8B.gguf -t 16 -n 128 -p 64
```

### 9. speculative decoding

use a small draft model to accelerate generation:

```bash
llama-server \
  --model Qwen3-30B-A3B-Q4_K_M.gguf \
  --model-draft Qwen3-0.6B-Q8_0.gguf \
  --draft-max 3 --draft-min 3 \
  --n-gpu-layers 999
```

## rollback

if anything breaks:

```bash
# reboot into snapshot
sudo mount /dev/nvme0n1p2 -o subvolid=5 /mnt
sudo mv /mnt/@ /mnt/@.broken
sudo btrfs subvolume snapshot /mnt/.snapshots/pre-bleeding-edge /mnt/@
sudo umount /mnt
sudo reboot
```

you're back to stable in 30 seconds. that's why we snapshot first.

## credits

**none of these optimizations are ours.** they belong to the people who found them:

| optimization | credit |
|-------------|--------|
| Vulkan-only for llama.cpp (community catch) | u/Look_0ver_There |
| Zen 5 AVX-512 compiler flags | [paudley/ai-notes](https://github.com/paudley/ai-notes) |
| Strix Halo toolboxes + 150 benchmarks | [kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes) |
| XDNA2 NPU driver (amdxdna) | AMD Linux kernel team |
| Lemonade SDK + FLM backend | [TurnkeyML / FastFlow FM](https://github.com/lemonade-sdk/lemonade) |
| Bonsai 1-bit models | [Prism ML / Mintplex Labs](https://huggingface.co/prism-ml) |
| llama.cpp | [Georgi Gerganov](https://github.com/ggerganov/llama.cpp) + 700 contributors |
| The lighthouse | [Light-Heart-Labs / DreamServer](https://github.com/Light-Heart-Labs/DreamServer) |

the architecture is ours. the optimizations belong to the community. claude just orchestrates a 420 brain.

## warnings

- **kernel panics are possible** — rc kernels are release candidates, not stable
- **npu drivers are experimental** — XDNA2 support is early
- **do not run this in production** — this is for testing and benchmarking
- **always snapshot before upgrading** — no snapshot, no sympathy

> *"one does not simply walk into mordor."* — but we're going anyway.

## full reproduction guide

see [REPRODUCE.md](REPRODUCE.md) for the complete step-by-step to reproduce every number in this document.

---

*designed and built by the architect*
*stable: [halo-ai-core](https://github.com/stampby/halo-ai-core) · bleeding edge: you are here*
