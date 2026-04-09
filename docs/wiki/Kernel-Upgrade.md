# kernel upgrade — linux 7.0-rc

*"roads? where we're going, we don't need roads."*

## why 7.0-rc

the stock arch kernel (6.19.x) does not include the `amdxdna` driver for the XDNA2 NPU. kernel 7.0-rc merges it into mainline. without 7.0+, the NPU does not exist as far as the OS is concerned.

what 7.0-rc adds:

- `/dev/accel/accel0` — the NPU device node
- `amdxdna` kernel module — driver for XDNA2
- improved GPU memory scheduling for gfx1151
- better HSA runtime performance

what it does NOT break:

- GPU performance (ROCm/Vulkan) — verified identical to 6.19
- all existing services continue working
- no regressions observed in our testing

## install

### snapshot first

```bash
sudo mkdir -p /.snapshots
sudo btrfs subvolume snapshot / /.snapshots/pre-kernel-7.0-$(date +%Y%m%d)
```

this is not optional. see [rollback](Rollback).

### build from AUR

```bash
# install AUR helper if needed
sudo pacman -S --needed base-devel
git clone https://aur.archlinux.org/paru.git /tmp/paru
cd /tmp/paru && makepkg -si --noconfirm

# build kernel (30-60 minutes on strix halo)
paru -S linux-mainline linux-mainline-headers
```

### update bootloader

```bash
# GRUB
sudo grub-mkconfig -o /boot/grub/grub.cfg

# systemd-boot (auto-detects new kernels)
# nothing to do
```

### reboot

```bash
sudo reboot
# select linux-mainline from boot menu
```

## verify

```bash
# kernel version
uname -r
# expected: 7.0.0-rcX-...

# NPU device
ls /dev/accel/
# expected: accel0

# amdxdna driver
lsmod | grep amdxdna
# expected: amdxdna  204800  0

# NPU firmware
cat /sys/bus/pci/drivers/amdxdna/*/fw_version
# expected: 1.1.2.65 or higher

# NPU PCI device
lspci | grep -i neural
# expected: Neural Processing Unit [1022:17f0]

# GPU still works
llama-server --version 2>&1 | head -1
# expected: found 1 ROCm devices (Total VRAM: ~63970 MiB)
```

## what if it breaks

see [rollback](Rollback). you're 30 seconds from stable.

## kernel config notes

the AUR `linux-mainline` package uses upstream defaults. if you need custom config:

```bash
# get the PKGBUILD
paru -G linux-mainline
cd linux-mainline

# edit config
# ensure these are set:
# CONFIG_DRM_ACCEL=y
# CONFIG_DRM_AMDXDNA=m
# CONFIG_AMDXDNA_ACCEL=m

makepkg -si
```

---

*next: [npu setup](NPU-Setup)*
