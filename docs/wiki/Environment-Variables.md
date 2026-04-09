# environment variables

*"set it and forget it."* — ron popeil

## required for ROCm on gfx1151

```bash
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export ROCBLAS_USE_HIPBLASLT=1
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export PATH=$PATH:/opt/rocm/bin
export HIP_PATH=/opt/rocm
export ROCM_PATH=/opt/rocm
```

## where to set them

### for your shell

add to `~/.bashrc` or `~/.zshrc`:

```bash
# ROCm for gfx1151
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export ROCBLAS_USE_HIPBLASLT=1
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export PATH=$PATH:/opt/rocm/bin
```

### for systemd services

create `/etc/profile.d/rocm.sh`:

```bash
#!/bin/bash
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export ROCBLAS_USE_HIPBLASLT=1
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
export PATH=$PATH:/opt/rocm/bin
```

for the llama-server service specifically:

```bash
sudo mkdir -p /etc/systemd/system/llama-server.service.d
cat << 'EOF' | sudo tee /etc/systemd/system/llama-server.service.d/rocm.conf
[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=11.5.1"
Environment="ROCBLAS_USE_HIPBLASLT=1"
Environment="TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1"
EOF
sudo systemctl daemon-reload
```

## what each variable does

| variable | purpose |
|----------|---------|
| `HSA_OVERRIDE_GFX_VERSION=11.5.1` | tells ROCm to treat gfx1151 as supported (required for strix halo) |
| `ROCBLAS_USE_HIPBLASLT=1` | enables HIPBLASLT for faster matrix multiply — doubles prompt throughput |
| `TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1` | enables AOTriton attention kernels — 19x attention speedup |
| `PATH=$PATH:/opt/rocm/bin` | makes ROCm tools available (hipcc, rocminfo, etc.) |
| `HIP_PATH=/opt/rocm` | build-time only — tells cmake where HIP is |
| `ROCM_PATH=/opt/rocm` | build-time only — tells cmake where ROCm is |

---

*next: [bonsai 1-bit models](Bonsai-Models)*
