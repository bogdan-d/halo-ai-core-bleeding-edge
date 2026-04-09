# benchmarks

*"show me the numbers."* — jerry maguire, kind of

all numbers captured 2026-04-09 on AMD Ryzen AI MAX+ 395 (Strix Halo), 128GB unified, Arch Linux, kernel 7.0.0-rc7.

## before — stable kernel 6.19.11

| model | test | prompt t/s | gen t/s |
|-------|------|-----------|---------|
| Qwen3-30B-A3B Q4_K_M | short (13→256) | 251.7 | 73.0 |
| Qwen3-30B-A3B Q4_K_M | medium (75→512) | 494.3 | 72.5 |
| Qwen3-30B-A3B Q4_K_M | long (39→1024) | 385.9 | 71.9 |
| Qwen3-30B-A3B Q4_K_M | sustained (54→2048) | 437.0 | 70.5 |

no NPU. no FLM. kernel 6.19 lacks XDNA2 driver.

## after — bleeding edge kernel 7.0-rc7

### GPU — ROCm + Vulkan

```bash
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export ROCBLAS_USE_HIPBLASLT=1
llama-bench -m Qwen3-Coder-30B-A3B-Q4_K_M.gguf -ngl 99 -p 64,512 -n 128,512
```

| model | test | t/s |
|-------|------|-----|
| Qwen3-Coder-30B-A3B Q4_K_M | pp64 (prompt) | **459.9** |
| Qwen3-Coder-30B-A3B Q4_K_M | pp512 (prompt) | **1,071.2** |
| Qwen3-Coder-30B-A3B Q4_K_M | tg128 (gen) | **64.3** |
| Qwen3-Coder-30B-A3B Q4_K_M | tg512 (gen) | **61.6** |

17.3 GB model. MoE with 3B active per token. 64 GB VRAM available. rock solid generation with zero degradation over 512 tokens.

### NPU — FLM via Lemonade SDK

```bash
lemonade load deepseek-r1-0528-8b-FLM --ctx-size 4096
curl -s http://127.0.0.1:13305/v1/chat/completions -H "Content-Type: application/json" \
    -d '{"model":"deepseek-r1-0528-8b-FLM","messages":[{"role":"user","content":"test"}],"max_tokens":256}'
```

| model | size | gen t/s |
|-------|------|---------|
| Gemma3 1B FLM | 1.2 GB | **34.9** |
| Gemma3 4B FLM | 3.6 GB | **17.0** |
| DeepSeek R1 8B FLM | 5.4 GB | **10.5** |
| DeepSeek R1-0528 8B FLM | 5.6 GB | **10.5** |

zero GPU memory used. NPU runs independently.

### Bonsai 1-bit — CPU (AVX-512)

```bash
~/prism-ml-llama.cpp/build/bin/llama-bench -m ~/models/bonsai/Bonsai-8B.gguf -t 16 -n 128 -p 64
```

| model | size | prompt (pp64) t/s | gen (tg128) t/s |
|-------|------|-------------------|-----------------|
| Bonsai-1.7B Q1_0 | 231 MB | 17.9 | **13.4** |
| Bonsai-4B Q1_0 | 540 MB | 6.8 | **5.7** |
| Bonsai-8B Q1_0 | 1.07 GB | 3.6 | **3.1** |

16 threads optimal. hyperthreading hurts 1-bit.

### system

| test | tool | result |
|------|------|--------|
| CPU (32 threads) | sysbench prime 50000 | 10,328 events/sec |
| memory bandwidth (16 threads) | sysbench | 87,088 MiB/sec |
| NVMe 4K random read | fio io_uring | 569K IOPS, 2,224 MiB/s |
| NVMe 4K random write | fio io_uring | 569K IOPS, 2,223 MiB/s |
| NVMe p99 latency | fio | 5 μs |
| Vulkan | vulkaninfo | 1.4.335, RADV Mesa 26.0.4 |
| OpenCL | clinfo | 20 CUs, 2.9 GHz, 53 GB max alloc |

## ryzen reference (same stack, kernel 6.19)

for comparison — same halo-ai-core on ryzen with ROCm/Vulkan GPU:

| model | prompt t/s | gen t/s |
|-------|-----------|---------|
| Qwen3-30B-A3B Q4_K_M | 209.7 | 88.7 |
| Bonsai-8B (1-bit, GPU) | 330.1 | 103.7 |
| Bonsai-4B (1-bit, GPU) | 524.5 | 148.3 |
| Bonsai-1.7B (1-bit, GPU) | 1,044.1 | 260.0 |
| FLUX Schnell 1024x1024 | — | 1.0s |
| DreamShaper 8 512x512 | — | 6.0s |
| LTX-Video 2B 512x320 | — | 20.6s |

## the takeaway

- GPU performance on 7.0-rc7 matches stable 6.19 — **no regression**
- NPU is now online — 4 models tested, 34 available
- NPU + GPU + CPU can all serve simultaneously
- the GPU is free for big models while NPU handles always-on agents

---

*next: [architecture](Architecture)*
