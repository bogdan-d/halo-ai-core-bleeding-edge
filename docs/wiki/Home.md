# halo-ai core — bleeding edge wiki

linux 7.0-rc · npu acceleration · experimental optimizations · *"one does not simply walk into mordor."*

## contents

- [getting started](Getting-Started) — prerequisites, first steps, what you're getting into
- [kernel upgrade](Kernel-Upgrade) — linux 7.0-rc from AUR, boot config, verification
- [npu setup](NPU-Setup) — XDNA2 driver, firmware, memlock, FLM backend
- [lemonade sdk](Lemonade-SDK) — server config, FLM models, OpenAI API, systemd
- [compiler optimizations](Compiler-Optimizations) — zen 5 flags, MMQ patch, rocWMMA, fast math
- [environment variables](Environment-Variables) — ROCm, HIPBLASLT, AOTriton, HSA
- [bonsai 1-bit models](Bonsai-Models) — prism-ml fork, Q1_0, download, benchmark
- [benchmarks](Benchmarks) — verified numbers from 2026-04-09, before/after
- [architecture](Architecture) — NPU + GPU + CPU simultaneous operation
- [troubleshooting](Troubleshooting) — every bug we hit and how we fixed it
- [rollback](Rollback) — btrfs snapshots, 30-second recovery
- [credits](Credits) — the people who actually built this

---

> this wiki documents everything done during the bleeding edge upgrade on 2026-04-09. every step is reproducible. every number is real. every bug we hit is logged with the fix.

> **stable first.** if you haven't installed [halo-ai-core](https://github.com/stampby/halo-ai-core) yet, start there. this repo builds on top of a working stable install.

---

*"smoke a lot of weed and ask what if...claude responds i can do that."* — the architect
