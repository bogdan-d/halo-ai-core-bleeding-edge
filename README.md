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
- **npu acceleration** — offload workloads to the neural processing unit
- **experimental compiler flags** — zen 5 avx-512, polly optimizations
- **bleeding edge rocm** — nightly builds, flash attention, aotriton
- **speculative decoding** — draft model acceleration

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
./upgrade.sh
```

## what changes

### 1. linux 7.0-rc kernel

the stock arch kernel (6.19.x) doesn't support XDNA2 for the NPU. kernel 7.0-rc adds:

- `/dev/accel0` NPU device with working SVA bind
- improved GPU memory scheduling for gfx1151
- better HSA runtime performance

```bash
# built from AUR
paru -S linux-mainline
```

### 2. zen 5 compiler optimizations

rebuild llama.cpp with stolen flags from paudley/ai-notes:

```
-march=znver5 -mtune=znver5 -mavx512f -mavx512vl -mavx512bw
-mllvm -polly -mllvm -polly-vectorizer=stripmine
```

### 3. npu offload

once kernel 7.0+ is running and `/dev/accel0` is available:

```bash
# verify NPU
ls /dev/accel0 && echo "NPU ready"

# benchmark with NPU offload
HSA_OVERRIDE_GFX_VERSION=11.5.1 llama-bench -m model.gguf -ngl 99 --npu-layers 4
```

### 4. speculative decoding

use a small draft model to accelerate generation:

```bash
llama-server \
  --model Qwen3-30B-A3B-Q4_K_M.gguf \
  --model-draft Qwen3-0.6B-Q8_0.gguf \
  --draft-max 3 --draft-min 3 \
  --n-gpu-layers 999
```

## benchmarks

### stable (halo-ai-core, kernel 6.19.11)

| model | prompt (pp512) | generation (tg128) |
|-------|----------------|-------------------|
| qwen3-30B-A3B Q4_K_M | 1,113 t/s | 66.6 t/s |

### bleeding edge (this repo, kernel 7.0-rc + zen5 flags)

| model | prompt (pp512) | generation (tg128) |
|-------|----------------|-------------------|
| qwen3-30B-A3B Q4_K_M | TBD | TBD |

*benchmarks will be run and published once kernel 7.0-rc is stable on strix halo.*

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

## warnings

- **kernel panics are possible** — rc kernels are release candidates, not stable
- **npu drivers are experimental** — XDNA2 support is early
- **do not run this in production** — this is for testing and benchmarking
- **always snapshot before upgrading** — no snapshot, no sympathy

> *"one does not simply walk into mordor."* — but we're going anyway.

---

*designed and built by the architect*
*stable: [halo-ai-core](https://github.com/stampby/halo-ai-core) · bleeding edge: you are here*
