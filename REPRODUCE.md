# reproducing every benchmark in this repo

step-by-step. copy-paste. no magic.

tested 2026-04-09 on AMD Ryzen AI MAX+ 395 (Strix Halo), 128GB unified, Arch Linux.

> *"just follow the yellow brick road."* — Glinda

---

## prerequisites

- [halo-ai-core](https://github.com/stampby/halo-ai-core) installed and running
- arch linux (bare metal, not VM)
- amd strix halo hardware (ryzen ai max+ 395 / gfx1151)
- btrfs root filesystem
- passwordless sudo

verify:

```bash
/usr/local/bin/llama-server --version   # should show ROCm devices
btrfs filesystem show /                 # should show btrfs
uname -r                                # note your current kernel
```

---

## step 0: snapshot (non-negotiable)

```bash
sudo mkdir -p /.snapshots
sudo btrfs subvolume snapshot / /.snapshots/pre-bleeding-edge-$(date +%Y%m%d)
```

if anything breaks, rollback:

```bash
sudo mount /dev/nvme0n1p2 -o subvolid=5 /mnt
sudo mv /mnt/@ /mnt/@.broken
sudo btrfs subvolume snapshot /mnt/.snapshots/pre-bleeding-edge-YYYYMMDD /mnt/@
sudo umount /mnt && sudo reboot
```

---

## step 1: kernel 7.0-rc (skip if already on 7.0+)

```bash
# install AUR helper if you don't have one
sudo pacman -S --needed base-devel
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si --noconfirm

# build kernel 7.0-rc from AUR (takes 30-60 min)
paru -S linux-mainline linux-mainline-headers

# update bootloader
sudo grub-mkconfig -o /boot/grub/grub.cfg  # if GRUB
# or systemd-boot will auto-detect

# reboot into new kernel
sudo reboot
# select linux-mainline from boot menu
```

verify after reboot:

```bash
uname -r                              # should show 7.0.0-rcX
ls /dev/accel/                        # should show accel0
lsmod | grep amdxdna                  # should show amdxdna module
cat /sys/bus/pci/drivers/amdxdna/*/fw_version  # should show 1.1.x.x
```

---

## step 2: rebuild llama.cpp with zen 5 + rocWMMA

```bash
cd ~/llama.cpp
git pull

# apply fast math intrinsics (replace expf with __expf for MoE/SiLU)
# IMPORTANT: only replace standalone expf, not already-prefixed __expf
sed -i 's/\([^_]\)expf(\([^)]*\))/\1__expf(\2)/g' ggml/src/ggml-cuda/fattn-common.cuh

# set ROCm environment
export PATH=$PATH:/opt/rocm/bin
export HIP_PATH=/opt/rocm
export ROCM_PATH=/opt/rocm

# clean and configure
rm -rf build
cmake -B build \
    -DGGML_HIP=ON \
    -DGGML_VULKAN=ON \
    -DGGML_HIP_ROCWMMA_FATTN=ON \
    -DAMDGPU_TARGETS=gfx1151 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_HIP_COMPILER=/opt/rocm/bin/amdclang++ \
    -DCMAKE_C_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq" \
    -DCMAKE_CXX_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq"

# build (uses all cores)
cmake --build build --config Release -j$(nproc)

# install
sudo systemctl stop llama-server.service 2>/dev/null
sudo cp build/bin/llama-server /usr/local/bin/
sudo cp build/bin/llama-cli /usr/local/bin/
sudo cp build/bin/llama-bench /usr/local/bin/
```

verify:

```bash
llama-server --version
# should show: found 1 ROCm devices (Total VRAM: ~63970 MiB)
```

---

## step 3: install lemonade SDK + FLM NPU backend

```bash
# install packages
sudo pacman -S xrt-plugin-amdxdna fastflowlm

# fix memlock limits (NPU requires unlimited)
sudo mkdir -p /etc/security/limits.d
echo -e "$(whoami) soft memlock unlimited\n$(whoami) hard memlock unlimited" | \
    sudo tee /etc/security/limits.d/99-npu-memlock.conf

# also fix for the lemonade service user
echo -e "lemonade soft memlock unlimited\nlemonade hard memlock unlimited" | \
    sudo tee -a /etc/security/limits.d/99-npu-memlock.conf

# set memlock in systemd service
sudo mkdir -p /etc/systemd/system/lemonade-server.service.d
echo -e "[Service]\nLimitMEMLOCK=infinity" | \
    sudo tee /etc/systemd/system/lemonade-server.service.d/memlock.conf

# reload and start
sudo systemctl daemon-reload
sudo systemctl enable --now lemonade-server

# verify FLM NPU backend
flm validate
# expected output:
#   Kernel: 7.0.0-rcX
#   NPU: /dev/accel/accel0 with 8 columns
#   NPU FW Version: 1.1.x.x
#   amdxdna version: 0.6
#   Memlock Limit: infinity

# verify lemonade sees FLM
lemonade backends | grep flm
# should show: flm  npu  installed  v0.9.38
```

---

## step 4: download models

### GPU models (for llama-bench)

```bash
mkdir -p ~/models

# qwen3-coder-30B-A3B — the MoE benchmark model
# download from huggingface (or use lemonade pull)
lemonade pull Qwen3-30B-A3B-GGUF
# or manually:
# huggingface-cli download bartowski/Qwen3-30B-A3B-GGUF --include "Qwen3-30B-A3B-Q4_K_M.gguf" --local-dir ~/models/
```

### NPU models (FLM format)

```bash
# pull via lemonade (downloads to lemonade cache)
lemonade pull deepseek-r1-0528-8b-FLM
lemonade pull deepseek-r1-8b-FLM
lemonade pull gemma3-1b-FLM
lemonade pull gemma3-4b-FLM
lemonade pull embed-gemma-300m-FLM
```

### 1-bit bonsai models

```bash
mkdir -p ~/models/bonsai

curl -L -o ~/models/bonsai/Bonsai-8B.gguf \
    "https://huggingface.co/prism-ml/Bonsai-8B-gguf/resolve/main/Bonsai-8B.gguf"

curl -L -o ~/models/bonsai/Bonsai-4B.gguf \
    "https://huggingface.co/prism-ml/Bonsai-4B-gguf/resolve/main/Bonsai-4B.gguf"

curl -L -o ~/models/bonsai/Bonsai-1.7B.gguf \
    "https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B.gguf"
```

verify sizes:

```
Bonsai-8B.gguf    1.1 GB
Bonsai-4B.gguf    546 MB
Bonsai-1.7B.gguf  237 MB
```

---

## step 5: build prism-ml llama.cpp (for bonsai)

standard llama.cpp does not have Q1_0 kernels. you need the prism-ml fork:

```bash
git clone https://github.com/Mintplex-Labs/prism-ml-llama.cpp.git
cd prism-ml-llama.cpp
cmake -B build \
    -DGGML_AVX512=ON \
    -DGGML_AVX512_VNNI=ON \
    -DGGML_AVX512_BF16=ON \
    -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

---

## step 6: run benchmarks

### GPU benchmark (ROCm + Vulkan)

```bash
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export ROCBLAS_USE_HIPBLASLT=1

llama-bench \
    -m ~/models/Qwen3-Coder-30B-A3B-Q4_K_M.gguf \
    -ngl 99 \
    -p 64,512 \
    -n 128,512
```

expected output:

```
| model                          |  size  |  params | backend     | ngl | test  |     t/s |
| qwen3moe 30B.A3B Q4_K - Medium | 17.28G |  30.53B | ROCm,Vulkan |  99 | pp64  |   459.9 |
| qwen3moe 30B.A3B Q4_K - Medium | 17.28G |  30.53B | ROCm,Vulkan |  99 | pp512 | 1,071.2 |
| qwen3moe 30B.A3B Q4_K - Medium | 17.28G |  30.53B | ROCm,Vulkan |  99 | tg128 |    64.3 |
| qwen3moe 30B.A3B Q4_K - Medium | 17.28G |  30.53B | ROCm,Vulkan |  99 | tg512 |    61.6 |
```

### NPU benchmark (FLM via Lemonade)

```bash
# load model on NPU
lemonade load deepseek-r1-0528-8b-FLM --ctx-size 4096

# benchmark via OpenAI-compatible API
# short generation (128 tokens)
time curl -s http://127.0.0.1:13305/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "deepseek-r1-0528-8b-FLM",
        "messages": [{"role":"user","content":"Explain how a steam boiler safety valve works in detail."}],
        "max_tokens": 128
    }' | python3 -c "
import sys, json
d = json.load(sys.stdin)
tokens = d['usage']['completion_tokens']
print(f'Tokens: {tokens}')
"

# unload and test next model
lemonade unload
lemonade load gemma3-1b-FLM --ctx-size 4096
# repeat benchmark...
```

expected NPU results:

```
gemma3-1b-FLM:             ~34.9 t/s generation
gemma3-4b-FLM:             ~17.0 t/s generation
deepseek-r1-8b-FLM:        ~10.5 t/s generation
deepseek-r1-0528-8b-FLM:   ~10.5 t/s generation
```

### bonsai 1-bit benchmark (CPU, AVX-512)

```bash
# use the prism-ml fork, not standard llama.cpp
cd ~/prism-ml-llama.cpp

./build/bin/llama-bench \
    -m ~/models/bonsai/Bonsai-1.7B.gguf \
    -t 16,32 -n 128 -p 64

./build/bin/llama-bench \
    -m ~/models/bonsai/Bonsai-4B.gguf \
    -t 16,32 -n 128 -p 64

./build/bin/llama-bench \
    -m ~/models/bonsai/Bonsai-8B.gguf \
    -t 16,32 -n 128 -p 64
```

expected bonsai results (16 threads is optimal):

```
| model           |  size   | threads | pp64 t/s | tg128 t/s |
| bonsai-1.7B Q1_0 | 231 MB |      16 |    17.9  |     13.4  |
| bonsai-4B Q1_0   | 540 MB |      16 |     6.8  |      5.7  |
| bonsai-8B Q1_0   | 1.07 GB |     16 |     3.6  |      3.1  |
```

note: 16 threads beats 32 on bonsai. hyperthreading hurts 1-bit inference.

### system benchmarks

```bash
# CPU
sudo pacman -S --needed sysbench stress-ng fio
sysbench cpu --cpu-max-prime=50000 --threads=32 run

# memory
sysbench memory --memory-block-size=1G --memory-total-size=20G --threads=16 run

# storage (NVMe)
fio --name=randmixed --ioengine=io_uring --rw=randrw --bs=4k \
    --numjobs=4 --size=1G --runtime=15 --time_based \
    --group_reporting --direct=1 --directory=/tmp
```

---

## troubleshooting

### FLM NPU won't load models

```bash
# check memlock
ulimit -l
# if not "unlimited", re-login or:
sudo prlimit --pid $(pgrep lemond) --memlock=unlimited:unlimited
sudo systemctl restart lemonade-server
```

### flm validate shows memlock error

```bash
# the limits.d file requires a fresh login session to take effect
# for immediate fix:
sudo prlimit --pid $$ --memlock=unlimited:unlimited
```

### llama.cpp build fails with ____expf

the fast math sed replacement doubled up. fix:

```bash
git checkout -- ggml/src/ggml-cuda/fattn-common.cuh
# re-apply correctly (only replace non-prefixed expf):
sed -i 's/\([^_]\)expf(\([^)]*\))/\1__expf(\2)/g' ggml/src/ggml-cuda/fattn-common.cuh
```

### NPU device not found

```bash
# verify kernel
uname -r  # must be 7.0+

# check driver
lsmod | grep amdxdna
# if missing:
sudo modprobe amdxdna

# check PCI
lspci | grep -i "signal processing\|neural"
# should show: [1022:17f0] Neural Processing Unit
```

### GPU not detected by llama.cpp

```bash
# verify ROCm
/opt/rocm/bin/rocminfo | grep gfx
# should show gfx1151

# set environment
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export PATH=$PATH:/opt/rocm/bin
```

---

## hardware tested

| component | spec |
|-----------|------|
| CPU | AMD Ryzen AI MAX+ 395, 16C/32T, 5.19 GHz boost |
| GPU | Radeon 8060S, RDNA 3.5, 40 CUs, 2.9 GHz |
| NPU | XDNA2, 8 columns, amdxdna v0.6 |
| RAM | 128 GB DDR5 unified |
| Storage | Yangtze Memory PC41Q NVMe |
| Kernel | 7.0.0-rc7-strixhalo |
| ROCm | gfx1151 via /opt/rocm |
| Vulkan | 1.4.335, RADV Mesa 26.0.4 |
| Lemonade | 10.2.0 |
| FastFlowLM | 0.9.38 |
| llama.cpp | build c8ac02fa1 (8736) |
| prism-ml llama.cpp | build 520d93d8a (8656) |

---

*designed and built by the architect · 2026-04-09*
*the optimizations belong to the community. claude orchestrates a 420 brain.*
