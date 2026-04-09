# lemonade SDK

*"all those moments will be lost in time, like tears in rain."* — not if they're served on localhost:13305.

## what it is

[lemonade SDK](https://github.com/lemonade-sdk/lemonade) (by TurnkeyML / FastFlow FM) is the unified inference server. it wraps llama.cpp, FLM (NPU), whisper.cpp, kokoro TTS, and stable diffusion behind one OpenAI-compatible API. everything goes through lemonade. that's the rule.

## version

```
lemonade 10.2.0
lemond (server daemon) on port 13305
websocket on port 9000
```

## backends

```bash
lemonade backends
```

| recipe | backend | status |
|--------|---------|--------|
| flm | npu | **installed** (v0.9.38) |
| llamacpp | cpu | installed |
| llamacpp | rocm | installed |
| llamacpp | vulkan | installed |
| kokoro | cpu | installable |
| whispercpp | cpu | installable |
| whispercpp | vulkan | installable |
| sd-cpp | cpu | installable |
| sd-cpp | rocm | installable |

## systemd service

```bash
# enable on boot
sudo systemctl enable lemonade-server

# start
sudo systemctl start lemonade-server

# check
systemctl status lemonade-server

# logs
journalctl -u lemonade-server -f
```

**memlock override required** — see [NPU setup](NPU-Setup):

```bash
sudo mkdir -p /etc/systemd/system/lemonade-server.service.d
echo -e "[Service]\nLimitMEMLOCK=infinity" | \
    sudo tee /etc/systemd/system/lemonade-server.service.d/memlock.conf
sudo systemctl daemon-reload
```

## model management

```bash
# list all models
lemonade list

# list downloaded only
lemonade list --downloaded

# pull a model
lemonade pull deepseek-r1-0528-8b-FLM

# load onto NPU
lemonade load deepseek-r1-0528-8b-FLM --ctx-size 4096

# check what's loaded
lemonade status

# unload
lemonade unload

# delete
lemonade delete deepseek-r1-0528-8b-FLM
```

## OpenAI-compatible API

once a model is loaded, hit it like any OpenAI API:

```bash
curl http://127.0.0.1:13305/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{
        "model": "deepseek-r1-0528-8b-FLM",
        "messages": [{"role":"user","content":"hello"}],
        "max_tokens": 128
    }'
```

works with:
- open webui
- claude code (as provider)
- any OpenAI SDK client
- curl
- python `openai` library with `base_url="http://127.0.0.1:13305/v1"`

## FLM-specific options

```bash
# load with custom FLM args
lemonade load deepseek-r1-0528-8b-FLM --flm-args "--pmode turbo"

# power modes: powersaver, balanced, performance, turbo
```

## llama.cpp backend options

```bash
# force a specific llama.cpp backend
lemonade load Qwen3-30B-A3B-GGUF --llamacpp rocm

# backends: cpu, rocm, vulkan
```

## configuration

```bash
# view config
lemonade config

# set default llama.cpp backend
lemonade config set llamacpp.backend=rocm

# set default port
lemonade config set port=13305
```

## cache location

- models: `/var/lib/lemonade/.cache/lemonade/`
- FLM models: `/var/lib/lemonade/.config/flm/models/`
- config: `/var/lib/lemonade/.config/lemonade/`
- llama.cpp binaries: `/var/lib/lemonade/.cache/lemonade/bin/llamacpp/`

## known issue: FLM CDN download errors

as of 2026-04-09, `flm pull` returns JSON parse errors for some models. the download CDN occasionally returns HTML instead of JSON manifest.

workaround: use `lemonade pull` instead of `flm pull` — lemonade handles its own download path. if a model shows as pulled in lemonade but empty in flm, the CDN was down during that pull. wait and retry.

---

*next: [compiler optimizations](Compiler-Optimizations)*
