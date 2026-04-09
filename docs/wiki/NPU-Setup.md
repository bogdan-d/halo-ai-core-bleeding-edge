# NPU setup — XDNA2

*"the power of the sun, in the palm of my hand."*

## what the NPU is

the XDNA2 is AMD's neural processing unit — a dedicated AI accelerator built into the strix halo die. it has 8 compute columns and runs independently from the GPU. the whole point: run always-on AI workloads (agents, whisper, embeddings) on the NPU while the GPU handles big models.

## hardware details

| spec | value |
|------|-------|
| architecture | XDNA2 |
| columns | 8 |
| PCI ID | 1022:17f0 |
| device node | /dev/accel/accel0 |
| driver | amdxdna v0.6 |
| firmware | amdnpu/17f0_11/npu_7.sbin |
| firmware version | 1.1.2.65 |

## install required packages

```bash
# XRT plugin (runtime for NPU) and FastFlowLM (inference engine)
sudo pacman -S xrt-plugin-amdxdna fastflowlm
```

## fix memlock limits

the NPU requires large memory-mapped regions. default memlock (8 MB) is too low.

```bash
# create limits file
sudo mkdir -p /etc/security/limits.d

# set unlimited for your user
echo "$(whoami) soft memlock unlimited" | sudo tee /etc/security/limits.d/99-npu-memlock.conf
echo "$(whoami) hard memlock unlimited" | sudo tee -a /etc/security/limits.d/99-npu-memlock.conf

# also for the lemonade service user
echo "lemonade soft memlock unlimited" | sudo tee -a /etc/security/limits.d/99-npu-memlock.conf
echo "lemonade hard memlock unlimited" | sudo tee -a /etc/security/limits.d/99-npu-memlock.conf
```

**important:** limits.d changes require a fresh login session. to apply immediately:

```bash
# for current shell
sudo prlimit --pid $$ --memlock=unlimited:unlimited

# for running lemonade server
sudo prlimit --pid $(pgrep lemond) --memlock=unlimited:unlimited
```

## set systemd service memlock

even with limits.d, the systemd service needs its own override:

```bash
sudo mkdir -p /etc/systemd/system/lemonade-server.service.d
echo -e "[Service]\nLimitMEMLOCK=infinity" | \
    sudo tee /etc/systemd/system/lemonade-server.service.d/memlock.conf

sudo systemctl daemon-reload
```

## add user to render group

```bash
sudo usermod -aG render $(whoami)
```

## validate

```bash
flm validate
```

expected output:

```
[Linux]  Kernel: 7.0.0-rc7-strixhalo
[Linux]  NPU: /dev/accel/accel0 with 8 columns  ✓
[Linux]  NPU FW Version: 1.1.2.65               ✓
[Linux]  amdxdna version: 0.6                    ✓
[Linux]  Memlock Limit: infinity                 ✓
```

all four checks must pass. if memlock fails, see the fix above.

## available FLM models

34 models optimized for the XDNA2 NPU in q4nx format:

```bash
flm list
```

key models:

| model | size | our gen t/s |
|-------|------|-------------|
| gemma3:1b | 1.2 GB | 34.9 |
| gemma3:4b | 3.6 GB | 17.0 |
| deepseek-r1:8b | 5.4 GB | 10.5 |
| deepseek-r1-0528:8b | 5.6 GB | 10.5 |
| qwen3:8b | — | untested |
| qwen3.5:9b | — | untested |
| gpt-oss:20b | — | untested |
| whisper-v3:turbo | — | NPU whisper |

## firmware files

located at `/lib/firmware/amdnpu/17f0_11/`:

```
npu_7.sbin.zst
npu.sbin.1.0.0.166.zst
npu.sbin.1.1.2.65.zst
npu.sbin.zst
```

if firmware is missing, install the `linux-firmware` package:

```bash
sudo pacman -S linux-firmware
```

---

*next: [lemonade sdk](Lemonade-SDK)*
