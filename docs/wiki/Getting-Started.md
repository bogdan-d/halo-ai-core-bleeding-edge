# getting started

*"you take the red pill, you stay in wonderland, and I show you how deep the rabbit hole goes."*

## what you need

| requirement | why |
|-------------|-----|
| [halo-ai-core](https://github.com/stampby/halo-ai-core) installed | bleeding edge builds on top of stable |
| arch linux (bare metal) | no VMs, no WSL, no containers |
| amd strix halo hardware | ryzen ai max+ 395, gfx1151 |
| btrfs root filesystem | snapshots = rollback safety net |
| passwordless sudo | the scripts need it |
| comfort with breakage | rc kernels can panic. that's the deal. |

## verify prerequisites

```bash
# stable install present?
/usr/local/bin/llama-server --version

# btrfs?
df -T / | grep btrfs

# strix halo?
lscpu | grep "Ryzen AI MAX"

# sudo?
sudo whoami
```

if any of those fail, go install [halo-ai-core](https://github.com/stampby/halo-ai-core) first.

## what you're getting into

bleeding edge adds:

1. **kernel 7.0-rc** — rc means release candidate. it can crash. that's why we snapshot.
2. **NPU acceleration** — the XDNA2 neural processing unit becomes available for inference.
3. **compiler optimizations** — zen 5 AVX-512 flags, MMQ kernel patches, flash attention.
4. **lemonade SDK + FLM** — purpose-built NPU inference backend with 34 models.
5. **1-bit model support** — bonsai Q1_0 true ternary weight models.

## the quick version

```bash
git clone https://github.com/stampby/halo-ai-core-bleeding-edge.git
cd halo-ai-core-bleeding-edge
./upgrade.sh --dry-run    # look before you leap
./upgrade.sh              # leap
```

## the careful version

read every page of this wiki first. then run the upgrade. that's what the wiki is for.

---

*next: [kernel upgrade](Kernel-Upgrade)*
