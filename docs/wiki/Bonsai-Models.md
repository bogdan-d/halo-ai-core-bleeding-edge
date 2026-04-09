# bonsai 1-bit models

*"one bit to rule them all."*

## what they are

[bonsai](https://huggingface.co/prism-ml) models by Prism ML (Mintplex Labs) are true 1-bit (ternary weight, Q1_0) LLMs. each weight is -1, 0, or +1. an 8B parameter model fits in 1.07 GB. for comparison, a standard Q4_K_M 8B model is ~5 GB.

## available models

| model | params | size | huggingface |
|-------|--------|------|-------------|
| Bonsai-8B | 8.19B | 1.07 GB | [prism-ml/Bonsai-8B-gguf](https://huggingface.co/prism-ml/Bonsai-8B-gguf) |
| Bonsai-4B | 4.02B | 540 MB | [prism-ml/Bonsai-4B-gguf](https://huggingface.co/prism-ml/Bonsai-4B-gguf) |
| Bonsai-1.7B | 1.72B | 231 MB | [prism-ml/Bonsai-1.7B-gguf](https://huggingface.co/prism-ml/Bonsai-1.7B-gguf) |

all three are based on Qwen3 architecture with ternary weight training.

## other 1-bit models that exist

| model | source | format | notes |
|-------|--------|--------|-------|
| Microsoft BitNet b1.58-2B-4T | [microsoft](https://huggingface.co/microsoft/bitnet-b1.58-2B-4T-gguf) | GGUF | needs bitnet.cpp fork |
| 1bitLLM bitnet_b1_58-3B | [1bitLLM](https://huggingface.co/1bitLLM/bitnet_b1_58-3B) | safetensors | research only |

bonsai is the only production-ready 1-bit family with proper GGUF support.

## requirements

**standard llama.cpp does NOT have Q1_0 kernels.** you need the prism-ml fork:

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

this builds a CPU-only binary with full AVX-512 support.

## download models

```bash
mkdir -p ~/models/bonsai

curl -L -o ~/models/bonsai/Bonsai-8B.gguf \
    "https://huggingface.co/prism-ml/Bonsai-8B-gguf/resolve/main/Bonsai-8B.gguf"

curl -L -o ~/models/bonsai/Bonsai-4B.gguf \
    "https://huggingface.co/prism-ml/Bonsai-4B-gguf/resolve/main/Bonsai-4B.gguf"

curl -L -o ~/models/bonsai/Bonsai-1.7B.gguf \
    "https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B.gguf"
```

## benchmark

```bash
cd ~/prism-ml-llama.cpp

# 16 threads is optimal — hyperthreading hurts 1-bit
./build/bin/llama-bench -m ~/models/bonsai/Bonsai-8B.gguf -t 16 -n 128 -p 64
./build/bin/llama-bench -m ~/models/bonsai/Bonsai-4B.gguf -t 16 -n 128 -p 64
./build/bin/llama-bench -m ~/models/bonsai/Bonsai-1.7B.gguf -t 16 -n 128 -p 64
```

## our results (CPU, AVX-512, strix halo)

| model | size | prompt (pp64) t/s | generation (tg128) t/s |
|-------|------|-------------------|----------------------|
| Bonsai-1.7B | 231 MB | 17.9 | 13.4 |
| Bonsai-4B | 540 MB | 6.8 | 5.7 |
| Bonsai-8B | 1.07 GB | 3.6 | 3.1 |

## important notes

- **16 threads beats 32.** hyperthreading hurts 1-bit inference. the Q1_0 kernels don't benefit from SMT.
- **CPU only.** the prism-ml fork does not have GPU (ROCm/CUDA) Q1_0 kernels. inference is CPU-bound.
- **on ROCm GPU** (tested on ryzen with Vulkan), bonsai-8B hits 103.7 t/s. that's the ROCm build of standard llama.cpp loading the model in a higher quant — not the same as true Q1_0 CPU inference.
- **memory bandwidth bound.** 1-bit models are tiny in memory but the computation per bit is expensive. speed scales with memory bandwidth, not core count.

## running interactively

```bash
./build/bin/llama-cli \
    -m ~/models/bonsai/Bonsai-8B.gguf \
    -t 16 \
    -n 512 \
    -p "You are a helpful assistant." \
    --interactive-first
```

---

*next: [benchmarks](Benchmarks)*
