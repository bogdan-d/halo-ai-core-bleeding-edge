# troubleshooting

*"houston, we've had a problem."*

every bug we hit during the 2026-04-09 bleeding edge session, and how we fixed it.

## build errors

### ____expf: use of undeclared identifier

**error:**
```
fattn-common.cuh:907: error: use of undeclared identifier '____expf'
```

**cause:** the fast math sed replacement ran twice, turning `__expf` → `____expf`.

**fix:**
```bash
cd ~/llama.cpp
git checkout -- ggml/src/ggml-cuda/fattn-common.cuh
# apply correctly (only match non-prefixed expf):
sed -i 's/\([^_]\)expf(\([^)]*\))/\1__expf(\2)/g' ggml/src/ggml-cuda/fattn-common.cuh
```

### llama-server binary not found after build

**error:**
```
cp: cannot stat 'build/bin/llama-server': No such file or directory
```

**cause:** newer llama.cpp versions place binaries in different paths.

**fix:**
```bash
find build -name "llama-server" -type f
# use whatever path it's in
```

## NPU errors

### flm validate: memlock limit too low

**error:**
```
[ERROR] Memlock limit is too low (8MB)
```

**fix:**
```bash
# create limits file
echo "$(whoami) soft memlock unlimited" | sudo tee /etc/security/limits.d/99-npu-memlock.conf
echo "$(whoami) hard memlock unlimited" | sudo tee -a /etc/security/limits.d/99-npu-memlock.conf

# for immediate effect (without re-login):
sudo prlimit --pid $$ --memlock=unlimited:unlimited
```

### mmap failed: Resource temporarily unavailable

**error:**
```
Error: mmap(addr=..., len=67108864, prot=3, flags=8209, offset=...) failed (err=-11)
```

**cause:** the lemonade server's child process (flm serve) doesn't have sufficient memlock limits.

**fix:**
```bash
# systemd override for lemonade-server
sudo mkdir -p /etc/systemd/system/lemonade-server.service.d
echo -e "[Service]\nLimitMEMLOCK=infinity" | sudo tee /etc/systemd/system/lemonade-server.service.d/memlock.conf
sudo systemctl daemon-reload
sudo systemctl restart lemonade-server
```

### /dev/accel0 not found

**cause:** could be `/dev/accel/accel0` (with subdirectory) on some kernel versions.

**fix:**
```bash
ls /dev/accel/accel0    # try this path
ls /dev/accel0          # or this
```

if neither exists:
```bash
uname -r    # must be 7.0+
lsmod | grep amdxdna    # driver loaded?
sudo modprobe amdxdna   # try loading it
lspci | grep -i neural  # hardware present?
```

### flm pull: JSON parse error

**error:**
```
[ERROR] Error building download list: [json.exception.parse_error.101] parse error at line 1, column 1
```

**cause:** FLM download CDN returning HTML instead of JSON manifest. intermittent server-side issue.

**fix:** use `lemonade pull` instead:
```bash
lemonade pull deepseek-r1-0528-8b-FLM
```

or wait and retry `flm pull` later.

### FLM model directory empty after pull

**cause:** lemonade and flm CLI use different cache directories:
- lemonade: `/var/lib/lemonade/.config/flm/models/`
- flm CLI: `/home/bcloud/.config/flm/models/`

the lemonade pull succeeded but flm CLI can't see it.

**fix:** models pulled via lemonade are in the lemonade user's cache. load via `lemonade load`, not `flm run`.

## lemonade server errors

### "Failed to read connection" on model load

**cause:** the flm serve subprocess crashed (usually memlock). the server stays running but the load fails.

**fix:** check logs:
```bash
journalctl -u lemonade-server -n 30
```

look for `exit code: 231` or `mmap failed`. fix memlock (see above).

### lemonade server not starting on boot

**fix:**
```bash
sudo systemctl enable lemonade-server
sudo systemctl start lemonade-server
systemctl status lemonade-server
```

## audio/recording errors

### audio device busy on ryzen

**cause:** stale arecord process from interrupted recording.

**fix:**
```bash
ssh ryzen "killall arecord"
# or
ssh ryzen "fuser /dev/snd/pcmC0D0c"
ssh ryzen "kill <PID>"
```

### arecord: Sample format non available

**cause:** M2 audio interface requires S32_LE at 44100Hz stereo.

**fix:**
```bash
arecord -D hw:0,0 -f S32_LE -r 44100 -c 2 -d 60 -t wav output.wav
```

## general

### how to check if everything is working

```bash
# kernel
uname -r                          # 7.0.0-rcX

# NPU
flm validate                      # all green

# lemonade
lemonade status                   # server running

# GPU
llama-server --version 2>&1       # ROCm devices found

# test inference
lemonade load gemma3-1b-FLM
curl -s http://127.0.0.1:13305/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"gemma3-1b-FLM","messages":[{"role":"user","content":"hello"}],"max_tokens":10}'
```

---

*next: [rollback](Rollback)*
