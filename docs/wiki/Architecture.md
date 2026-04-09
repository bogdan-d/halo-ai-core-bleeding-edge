# architecture — NPU + GPU + CPU

*"the whole is greater than the sum of its parts."*

## the three-lane highway

strix halo has three independent compute paths for AI inference. bleeding edge activates all three simultaneously:

```
┌─────────────────────────────────────────────────────┐
│                  Lemonade SDK (:13305)               │
│              OpenAI-compatible API gateway            │
├─────────────────┬─────────────────┬─────────────────┤
│   NPU (FLM)    │  GPU (ROCm/VK)  │  CPU (AVX-512)  │
│                 │                 │                  │
│  always-on      │  on-demand      │  overflow/1-bit  │
│  zero GPU cost  │  big models     │  bonsai Q1_0     │
│                 │                 │                  │
│  agents         │  coding 32B     │  embeddings      │
│  whisper STT    │  reasoning 32B  │  kokoro TTS      │
│  embeddings     │  vision 32B     │  light tasks     │
│  small chat     │  image gen      │                  │
├─────────────────┼─────────────────┼─────────────────┤
│  XDNA2 8 cols   │ 40 CUs 2.9 GHz │ 16C/32T 5.19GHz │
│  /dev/accel0    │ /dev/dri/card1  │ AVX-512 full    │
│  ~0 VRAM used   │ ~64 GB VRAM    │ ~128 GB RAM     │
└─────────────────┴─────────────────┴─────────────────┘
                 128 GB unified DDR5
```

## why this matters

before bleeding edge (kernel 6.19): only GPU and CPU available. running always-on agents meant keeping a model loaded on the GPU, which blocked other GPU workloads.

after bleeding edge (kernel 7.0-rc): NPU handles the always-on stuff. GPU is free for big on-demand models. CPU handles overflow and 1-bit.

## simultaneous operation

| slot | model | backend | memory |
|------|-------|---------|--------|
| always-on | Gemma3 4B (agents) | NPU (FLM) | 0 GPU |
| always-on | Whisper v3 Turbo (STT) | NPU (FLM) | 0 GPU |
| always-on | Embed-Gemma 300M | NPU (FLM) | 0 GPU |
| always-on | Kokoro TTS | CPU | ~200 MB RAM |
| on-demand | Qwen3-Coder-30B-A3B | GPU (ROCm) | ~18 GB VRAM |
| on-demand | SD 3.5 Medium | GPU (ROCm) | ~5 GB VRAM |
| overflow | Bonsai 8B (1-bit) | CPU (AVX-512) | ~1 GB RAM |

total GPU memory used by always-on: **zero.**
remaining GPU for on-demand: **~64 GB.**

## model routing

lemonade handles routing automatically based on the model name:

- `*-FLM` models → NPU (FLM backend)
- `*-GGUF` models → GPU or CPU (llama.cpp backend, configurable)
- whisper models → CPU or NPU
- SD models → GPU (sd-cpp backend)

## the NPU sweet spot

the NPU excels at small-medium models (< 10B) with constant throughput. it's not going to beat the GPU on raw speed — that's not the point. the point is:

1. **it's free.** zero GPU memory, zero GPU compute.
2. **it's always on.** no loading/unloading models.
3. **it's independent.** GPU can be doing image gen while NPU serves chat.

## scaling with lemonade

```
phone (wireguard) ──→ caddy (:80) ──→ lemonade (:13305) ──→ NPU/GPU/CPU
browser           ──→ caddy (:80) ──→ lemonade (:13305) ──→ NPU/GPU/CPU
open webui        ──→ localhost    ──→ lemonade (:13305) ──→ NPU/GPU/CPU
claude code       ──→ localhost    ──→ lemonade (:13305) ──→ NPU/GPU/CPU
gaia agents       ──→ localhost    ──→ lemonade (:13305) ──→ NPU/GPU/CPU
```

one API endpoint. three compute backends. all local. zero cloud.

---

*next: [troubleshooting](Troubleshooting)*
