# compiler optimizations

*"faster, faster, until the thrill of speed overcomes the fear of death."* — hunter s. thompson

## overview

six optimizations applied to llama.cpp for gfx1151 (RDNA 3.5) + zen 5 CPU. none of these are ours — credits at the bottom.

## 1. zen 5 AVX-512 flags

full AVX-512 codegen for all CPU paths. strix halo supports F, VL, BW, DQ, VNNI, and BF16.

```bash
-DCMAKE_C_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq"
-DCMAKE_CXX_FLAGS="-march=znver5 -mtune=znver5 -O3 -mavx512f -mavx512vl -mavx512bw -mavx512dq"
```

this matters for:
- CPU-side tensor operations
- prompt tokenization
- KV cache management
- bonsai 1-bit model inference (CPU only)

credit: [paudley/ai-notes](https://github.com/paudley/ai-notes)

## 2. MMQ kernel patch (RDNA 3.5)

the default MMQ parameters in llama.cpp are tuned for NVIDIA. on gfx1151 (wave32), they cause register pressure and spills. reducing them fixes it.

```bash
# in ggml/src/ggml-cuda/mmq.cu
# change:
mmq_x = 64  → mmq_x = 48
mmq_y = 128 → mmq_y = 64
nwarps = 8  → nwarps = 4
```

the upgrade.sh script applies this automatically via sed. if the values have changed in a newer llama.cpp version, check the defaults first.

credit: [llama.cpp #21284](https://github.com/ggml-org/llama.cpp/issues/21284), community investigation

## 3. rocWMMA flash attention

hardware-accelerated matrix multiply for attention computation:

```bash
-DGGML_HIP_ROCWMMA_FATTN=ON
```

requires ROCm with rocWMMA support. gfx1151 has the necessary wave matrix multiply instructions.

credit: [AMD ROCm team](https://github.com/ROCm/TheRock)

## 4. fast math intrinsics

replace safe `expf()` with fast `__expf()` in the flash attention kernels. trades a tiny amount of precision for speed in MoE expert routing and SiLU activation.

```bash
# IMPORTANT: only replace standalone expf, not already-prefixed __expf
# reset first to avoid double-replacement:
git checkout -- ggml/src/ggml-cuda/fattn-common.cuh

# then apply:
sed -i 's/\([^_]\)expf(\([^)]*\))/\1__expf(\2)/g' ggml/src/ggml-cuda/fattn-common.cuh
```

**bug we hit:** the naive sed `s/expf/__expf/g` will turn `__expf` into `____expf` on re-runs. always reset the file first, and use the regex that checks for the underscore prefix.

credit: standard CUDA/HIP optimization technique

## 5. HIPBLASLT

doubles prompt processing throughput:

```bash
export ROCBLAS_USE_HIPBLASLT=1
```

set this in your shell profile or systemd service environment.

credit: AMD math libraries team

## 6. AOTriton

experimental attention optimization:

```bash
export TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1
```

credit: AMD Triton team

## full cmake command

```bash
export PATH=$PATH:/opt/rocm/bin
export HIP_PATH=/opt/rocm
export ROCM_PATH=/opt/rocm

cd ~/llama.cpp
git pull

# apply patches (see above)

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

cmake --build build --config Release -j$(nproc)

# install
sudo cp build/bin/llama-server /usr/local/bin/
sudo cp build/bin/llama-cli /usr/local/bin/
sudo cp build/bin/llama-bench /usr/local/bin/
```

---

*next: [environment variables](Environment-Variables)*
