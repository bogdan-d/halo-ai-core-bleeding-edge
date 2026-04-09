# credits

*"if I have seen further, it is by standing on the shoulders of giants."* — newton

**none of these optimizations are ours.** every single one was discovered, documented, and shared by someone else. we just assembled the pieces.

## the optimizations

| what | who | where |
|------|-----|-------|
| MMQ kernel fix for RDNA 3.5 | paudley + community | [paudley/ai-notes](https://github.com/paudley/ai-notes), [llama.cpp #21284](https://github.com/ggml-org/llama.cpp/issues/21284) |
| Zen 5 AVX-512 compiler flags | paudley | [paudley/ai-notes](https://github.com/paudley/ai-notes) |
| rocWMMA flash attention | AMD ROCm team | [ROCm/TheRock](https://github.com/ROCm/TheRock) |
| HIPBLASLT acceleration | AMD math libraries | ROCm documentation |
| AOTriton attention kernels | AMD Triton team | ROCm documentation |
| Fast math intrinsics | HIP/CUDA community | standard optimization technique |
| XDNA2 NPU driver | AMD Linux kernel team | kernel 7.0-rc mainline merge |

## the software

| project | who | where |
|---------|-----|-------|
| llama.cpp | Georgi Gerganov + 700 contributors | [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) |
| Lemonade SDK | TurnkeyML / FastFlow FM | [lemonade-sdk/lemonade](https://github.com/lemonade-sdk/lemonade) |
| FastFlowLM | FastFlow FM | [FastFlowLM](https://github.com/FastFlowLM/FastFlowLM) |
| Bonsai models | Prism ML / Mintplex Labs | [huggingface.co/prism-ml](https://huggingface.co/prism-ml) |
| prism-ml llama.cpp fork | Mintplex Labs | [Mintplex-Labs/prism-ml-llama.cpp](https://github.com/Mintplex-Labs/prism-ml-llama.cpp) |
| ROCm | AMD | [ROCm](https://github.com/ROCm) |
| AMD Gaia | AMD | [amd/gaia](https://github.com/amd/gaia) |
| Caddy | Matt Holt | [caddyserver/caddy](https://github.com/caddyserver/caddy) |
| Arch Linux | the community | [archlinux.org](https://archlinux.org) |

## the lighthouse

[Light-Heart-Labs / DreamServer](https://github.com/Light-Heart-Labs/DreamServer) — the project that showed what was possible on AMD hardware. if it wasn't for DreamServer, halo-ai-core wouldn't exist. period.

## the architect

the architecture is ours. the optimizations belong to the community. the architect pointed claude at the right problems. claude orchestrated. the 420 brain asked "what if." that's how it works.

> *"I'm not a programmer. I'm a power engineer who talks to an AI that does what I tell it."*

## how to add your name

find a bug? submit a fix? share a benchmark? open a PR or issue. credit goes where credit is due.

---

*"they get the kingdom. they forge their own keys."*

*stamped by the architect · 2026-04-09*
