# Title: Midlife crisis in the middle of the night with bong rips

---

I'm a 54-year-old power engineer. Last time I posted benchmarks, u/Hector_Rvkp told me I don't need to spell out hardware specs because "people know what a Strix Halo is." Fair point. So:

# Hardware

*You already know what this is.* — u/Hector_Rvkp

# Software Stack

    Kernel:      7.0.0-rc7-mainline (-march=znver5 -O3)
    NPU Driver:  amdxdna 0.6 (built from source)
    XRT:         v2.23.0 (built from source)
    FastFlowLM:  v0.9.38 (built from source)
    GPU Backend: llama.cpp Vulkan (h/t u/Look_0ver_There)
    Image Gen:   stable-diffusion.cpp ROCm (built from source)
    TTS:         Kokoro v1
    STT:         whisper.cpp Vulkan
    Orchestrator: Lemonade SDK
    Services:    36 active

Everything built from source. No pip install and pray.

---

# GPU Models (llama.cpp / Vulkan)

All tests: 500 tokens generated

    Qwen3-0.6B              0.6B          4.8s     104.8 tok/s
    Qwen3-VL-4B             4B           11.6s      43.0 tok/s
    Qwen3.5-35B-A3B         35B (3B)      9.5s      52.5 tok/s
    Qwen3-Coder-30B-A3B     30B (3B)     13.1s      38.0 tok/s
    ThinkingCoder (custom)   35B (3B)     23.9s      20.9 tok/s

ThinkingCoder is a custom modelfile with extended reasoning enabled — slower because it actually thinks before it speaks. Unlike me at 2am.

# NPU Models (AMD XDNA2 / FastFlowLM)

All tests: 500 tokens generated

    Gemma3 1B               1B           25.3s      19.8 tok/s
    Gemma3 4B               4B           40.8s      12.3 tok/s
    DeepSeek-R1 8B          8B           58.4s       8.6 tok/s
    DeepSeek-R1-0528 8B     8B           59.8s       8.4 tok/s

NPU running simultaneously with GPU — zero interference, separate silicon.

# Image Generation (stable-diffusion.cpp / ROCm)

    SD-Turbo             512x512     4 steps       2.7s
    SDXL-Turbo           512x512     4 steps       7.7s
    Flux-2-Klein-4B      1024x1024   4 steps      41.1s

# Audio

    Whisper-Large-v3-Turbo    45s audio transcribed in 0.65s    69x realtime
    Kokoro v1 TTS             262 chars synthesized in 1.13s    23x realtime

Yes, Whisper transcribes 45 seconds of audio in 650 milliseconds. No that's not a typo.

# What's Running Right Now

17 models downloaded. 5 loaded simultaneously. GPU at 58C. Fans silent. It's 2am and I should probably go to bed but here we are.

All of this runs on one chip. GPU inference, NPU inference, image generation, voice synthesis, speech recognition — all at the same time, all local, no cloud, no API keys.

https://github.com/stampby/halo-ai-core

---

*Last time someone said my formatting "looked like shit." I took that personally.*

    did    i    fix    it
    yes    i    did    .

*Stamped by the architect.*
