#!/bin/bash
# ============================================================
# bench-kernel — Kernel Benchmark for halo-ai core
# Designed and built by the architect
#
# "Roads? Where we're going, we don't need roads."
#   — Doc Brown, Back to the Future
#
# Runs thorough LLM benchmarks tied to current kernel version.
# Uses llama.cpp native timings — no guesswork.
# ============================================================
set -euo pipefail

API_URL="http://localhost:13305/v1/chat/completions"
MODELS_URL="http://localhost:13305/v1/models"
KERNEL=$(uname -r)
TIMESTAMP=$(date -Iseconds)
OUTPUT_DIR="$(cd "$(dirname "$0")" && pwd)/bench-results"
mkdir -p "$OUTPUT_DIR"
RESULT_FILE="${OUTPUT_DIR}/kernel-${KERNEL}-$(date +%Y%m%d-%H%M%S).json"

G='\033[0;32m'; B='\033[0;34m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  halo-ai core — Kernel Benchmark Suite       ║${NC}"
echo -e "${BOLD}║  \"Frankly my dear, I don't give a damn.\"     ║${NC}"
echo -e "${BOLD}║  ...but I do give you numbers.               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

# ── System Info ──
echo -e "${C}═══ SYSTEM INFO ═══${NC}"
CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
GPU_MODEL=$(rocm-smi --showproductname 2>/dev/null | grep 'Card Series' | head -1 | awk -F: '{print $NF}' | xargs)
ROCM_VER=$(cat /opt/rocm/.info/version 2>/dev/null || echo 'n/a')
GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'n/a')
LEMONADE_VER=$(lemonade --version 2>/dev/null)
RAM=$(free -h | awk '/Mem:/{print $2}')

echo -e "  Kernel:    ${BOLD}${KERNEL}${NC}"
echo -e "  CPU:       ${CPU_MODEL}"
echo -e "  Cores:     $(nproc)"
echo -e "  RAM:       ${RAM}"
echo -e "  GPU:       ${GPU_MODEL}"
echo -e "  ROCm:      ${ROCM_VER}"
echo -e "  Governor:  ${GOVERNOR}"
echo -e "  Lemonade:  ${LEMONADE_VER}"
echo -e "  Timestamp: ${TIMESTAMP}"
echo ""

# ── Check model ──
MODEL=$(curl -s "$MODELS_URL" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null)
if [ -z "$MODEL" ]; then
    echo -e "${Y}ERROR: No model loaded. Run: lemonade run <model>${NC}"
    exit 1
fi
echo -e "  Model:     ${BOLD}${MODEL}${NC}"
echo ""

# Init JSON
python3 -c "
import json
data = {
    'kernel': '${KERNEL}', 'timestamp': '${TIMESTAMP}', 'model': '${MODEL}',
    'system': {
        'cpu': '${CPU_MODEL}', 'cores': $(nproc), 'ram': '${RAM}',
        'gpu': '${GPU_MODEL}', 'rocm': '${ROCM_VER}', 'governor': '${GOVERNOR}',
        'lemonade': '${LEMONADE_VER}'
    },
    'benchmarks': []
}
with open('${RESULT_FILE}', 'w') as f: json.dump(data, f, indent=2)
"

# ── Benchmark Function ──
bench() {
    local name="$1"
    local prompt="$2"
    local max_tokens="$3"
    local runs="${4:-3}"

    local sum_prompt_tps=0 sum_gen_tps=0 sum_ttft=0 sum_total=0
    local last_prompt_tok=0 last_gen_tok=0

    for ((r=1; r<=runs; r++)); do
        local response
        response=$(curl -s "$API_URL" \
            -H "Content-Type: application/json" \
            -d "{
                \"model\": \"${MODEL}\",
                \"messages\": [{\"role\": \"user\", \"content\": $(python3 -c "import json; print(json.dumps('${prompt}'))")}],
                \"max_tokens\": ${max_tokens},
                \"temperature\": 0.1,
                \"chat_template_kwargs\": {\"enable_thinking\": false}
            }" 2>/dev/null)

        # Extract native llama.cpp timings
        local timings
        timings=$(echo "$response" | python3 -c "
import sys, json
d = json.load(sys.stdin)
t = d.get('timings', {})
u = d.get('usage', {})
print(f\"{t.get('prompt_per_second',0)},{t.get('predicted_per_second',0)},{t.get('prompt_ms',0)},{t.get('predicted_ms',0)},{u.get('prompt_tokens',0)},{u.get('completion_tokens',0)}\")
" 2>/dev/null)

        IFS=',' read -r p_tps g_tps p_ms g_ms p_tok g_tok <<< "$timings"

        sum_prompt_tps=$(python3 -c "print(${sum_prompt_tps} + ${p_tps})")
        sum_gen_tps=$(python3 -c "print(${sum_gen_tps} + ${g_tps})")
        sum_ttft=$(python3 -c "print(${sum_ttft} + ${p_ms})")
        sum_total=$(python3 -c "print(${sum_total} + ${p_ms} + ${g_ms})")
        last_prompt_tok=$p_tok
        last_gen_tok=$g_tok
    done

    local avg_prompt_tps=$(python3 -c "print(round(${sum_prompt_tps}/${runs}, 1))")
    local avg_gen_tps=$(python3 -c "print(round(${sum_gen_tps}/${runs}, 1))")
    local avg_ttft=$(python3 -c "print(round(${sum_ttft}/${runs}))")
    local avg_total=$(python3 -c "print(round(${sum_total}/${runs}))")

    echo -e "  ${G}✓${NC} ${BOLD}${name}${NC}"
    echo -e "    Prompt: ${B}${avg_prompt_tps} tok/s${NC} | Gen: ${B}${avg_gen_tps} tok/s${NC} | TTFT: ${avg_ttft}ms | Total: ${avg_total}ms"
    echo -e "    (${last_prompt_tok} prompt → ${last_gen_tok} generated, ${runs} runs averaged)"

    python3 -c "
import json
with open('${RESULT_FILE}') as f: data = json.load(f)
data['benchmarks'].append({
    'name': '${name}',
    'prompt_tps': ${avg_prompt_tps}, 'gen_tps': ${avg_gen_tps},
    'ttft_ms': ${avg_ttft}, 'total_ms': ${avg_total},
    'prompt_tokens': ${last_prompt_tok}, 'gen_tokens': ${last_gen_tok},
    'runs': ${runs}
})
with open('${RESULT_FILE}', 'w') as f: json.dump(data, f, indent=2)
"
}

# ── Run Benchmarks ──

echo -e "${C}═══ BENCHMARK 1: SHORT BURST ═══${NC}"
echo -e "  ${B}\"I'll be back.\" — and fast.${NC}"
bench "Short Burst" "What is 2+2? Answer in one word." 32 3

echo ""
echo -e "${C}═══ BENCHMARK 2: MEDIUM RESPONSE ═══${NC}"
echo -e "  ${B}\"Here's looking at you, kid.\"${NC}"
bench "Medium Response" "Explain how a CPU cache works in 3 sentences." 256 3

echo ""
echo -e "${C}═══ BENCHMARK 3: LONG GENERATION ═══${NC}"
echo -e "  ${B}\"After all, tomorrow is another day.\"${NC}"
bench "Long Generation" "Write a detailed technical overview of how GPU compute shaders work, covering thread groups, shared memory, synchronization, and practical applications." 512 3

echo ""
echo -e "${C}═══ BENCHMARK 4: SUSTAINED 2K ═══${NC}"
echo -e "  ${B}\"May the Force be with you.\" — for 2048 tokens.${NC}"
bench "Sustained 2K" "Write a comprehensive guide to building a home server for AI inference, covering hardware selection, operating system choice, driver installation, model formats, serving frameworks, and optimization techniques. Be thorough and specific." 2048 2

echo ""
echo -e "${C}═══ BENCHMARK 5: CODE GENERATION ═══${NC}"
echo -e "  ${B}\"I'm gonna make him an offer he can't refuse.\" — in Python.${NC}"
bench "Code Gen" "Write a Python async HTTP server with rate limiting per IP, JSON responses, error handling, and logging. Complete working code." 1024 2

echo ""
echo -e "${C}═══ BENCHMARK 6: REASONING ═══${NC}"
echo -e "  ${B}\"Elementary, my dear Watson.\"${NC}"
bench "Reasoning" "A farmer has 17 sheep. All but 9 run away. How many does the farmer have left? Explain step by step." 256 3

echo ""
echo -e "${C}═══ BENCHMARK 7: LONG CONTEXT ═══${NC}"
echo -e "  ${B}\"You can't handle the truth!\"${NC}"
bench "Long Context" "Given the following detailed technical specification: The AMD Ryzen AI MAX+ 395 processor features 16 Zen 5 cores with 32 threads, a base clock of 2.5 GHz boosting to 5.1 GHz, 80MB total cache (64MB L3 plus 16MB L2), integrated Radeon 8060S graphics with RDNA 3.5 architecture featuring 40 compute units, XDNA 2 NPU with 50 TOPS INT8 performance, support for LPDDR5X-8000 memory up to 128GB in a unified memory architecture shared between CPU and GPU, PCIe 4.0 with 20 lanes, USB4 support, and a configurable TDP of 120W. The processor targets mobile workstation and AI development use cases. What are the three most important architectural advantages this chip has for local AI inference compared to discrete GPU solutions? Be specific about memory bandwidth, cache hierarchy, and compute capabilities." 512 2

# ── GPU Memory ──
echo ""
echo -e "${C}═══ GPU MEMORY ═══${NC}"
rocm-smi --showmeminfo vram 2>/dev/null | grep -E "Used|Total" | head -4

# ── Summary ──
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Benchmark Complete                          ║${NC}"
echo -e "${BOLD}║  \"That'll do, pig. That'll do.\" — Babe       ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Results: ${RESULT_FILE}"
echo -e "  Kernel:  ${KERNEL}"
echo -e "  Model:   ${MODEL}"
echo ""

# Print summary table
python3 -c "
import json
with open('${RESULT_FILE}') as f: data = json.load(f)
print('  ┌─────────────────────┬────────────┬───────────┬─────────┬──────────┐')
print('  │ Test                │ Prompt t/s │ Gen t/s   │ TTFT ms │ Total ms │')
print('  ├─────────────────────┼────────────┼───────────┼─────────┼──────────┤')
for b in data['benchmarks']:
    print(f\"  │ {b['name']:<19} │ {b['prompt_tps']:>10} │ {b['gen_tps']:>9} │ {b['ttft_ms']:>7} │ {b['total_ms']:>8} │\")
print('  └─────────────────────┴────────────┴───────────┴─────────┴──────────┘')
"
echo ""
echo -e "  ${B}\"Designed and built by the architect.\"${NC}"
echo ""

# ── Rotate old results (keep 5 days) ──
echo -e "${C}═══ CLEANUP ═══${NC}"
CUTOFF=$(date -d "5 days ago" +%Y%m%d 2>/dev/null || date -v-5d +%Y%m%d 2>/dev/null || echo "")
if [ -n "$CUTOFF" ]; then
    DELETED=0
    for OLD in "${OUTPUT_DIR}"/kernel-*.json; do
        [ -f "$OLD" ] || continue
        FILE_DATE=$(basename "$OLD" | grep -oP '\d{8}' | head -1)
        if [ -n "$FILE_DATE" ] && [ "$FILE_DATE" -lt "$CUTOFF" ]; then
            rm -f "$OLD"
            DELETED=$((DELETED + 1))
        fi
    done
    for OLD in "${OUTPUT_DIR}"/real-world-*.json; do
        [ -f "$OLD" ] || continue
        FILE_DATE=$(stat -c %Y "$OLD" 2>/dev/null)
        CUTOFF_TS=$(date -d "5 days ago" +%s 2>/dev/null || echo 0)
        if [ "$FILE_DATE" -lt "$CUTOFF_TS" ] 2>/dev/null; then
            rm -f "$OLD"
            DELETED=$((DELETED + 1))
        fi
    done
    if [ "$DELETED" -gt 0 ]; then
        echo -e "  ${G}✓${NC} Rotated $DELETED old benchmark files (>5 days)"
    else
        echo -e "  ${G}✓${NC} No old benchmarks to rotate"
    fi
fi

# ── Update wiki Benchmarks.md with latest results ──
WIKI_FILE="$(cd "$(dirname "$0")" && pwd)/docs/wiki/Benchmarks.md"
if [ -f "$WIKI_FILE" ]; then
    python3 << 'WIKI_UPDATE'
import json, os, glob, datetime

script_dir = os.path.dirname(os.path.abspath("${RESULT_FILE}"))
result_file = "${RESULT_FILE}"
wiki_file = os.path.join(os.path.dirname(script_dir), "docs", "wiki", "Benchmarks.md")

if not os.path.exists(wiki_file) or not os.path.exists(result_file):
    exit(0)

with open(result_file) as f:
    data = json.load(f)

kernel = data.get("kernel", "unknown")
model = data.get("model", "unknown")
ts = data.get("timestamp", "")[:10]
sys_info = data.get("system", {})

# Build the new dated section
lines = []
lines.append(f"### {ts}: Kernel {kernel}, Lemonade {sys_info.get('lemonade', '10.2.0')}")
lines.append("")
lines.append(f"**Model:** {model} | **Governor:** {sys_info.get('governor', 'performance')} | **GPU:** {sys_info.get('gpu', 'Radeon 8060S')}")
lines.append("")
lines.append("| Test | Prompt t/s | Gen t/s | TTFT | Total |")
lines.append("|------|-----------|---------|------|-------|")
for b in data.get("benchmarks", []):
    lines.append(f"| {b['name']} | {b['prompt_tps']} | **{b['gen_tps']}** | {b['ttft_ms']}ms | {b['total_ms']}ms |")
lines.append("")
new_section = "\n".join(lines)

# Read existing wiki
with open(wiki_file) as f:
    wiki = f.read()

# Find the marker and insert after it
marker = "## The Numbers"
if marker in wiki:
    parts = wiki.split(marker, 1)
    # Find the next --- or ## after the marker section
    rest = parts[1]
    # Insert new dated section right after the marker line
    insert_pos = rest.find("\n---")
    if insert_pos == -1:
        insert_pos = rest.find("\n## ", 1)
    if insert_pos > 0:
        updated = parts[0] + marker + rest[:insert_pos] + "\n\n" + new_section + rest[insert_pos:]
    else:
        updated = parts[0] + marker + "\n\n" + new_section + rest
else:
    # No marker — prepend after first heading
    updated = wiki + "\n\n" + new_section

# Rotate: keep only last 5 dated sections (### YYYY-MM-DD:)
import re
dated_pattern = r'### \d{4}-\d{2}-\d{2}:.*?(?=### \d{4}-\d{2}-\d{2}:|---|\Z)'
dated_sections = list(re.finditer(dated_pattern, updated, re.DOTALL))
if len(dated_sections) > 5:
    # Remove oldest (they appear in order, newest should be last inserted)
    to_remove = dated_sections[:-5]
    for match in reversed(to_remove):
        updated = updated[:match.start()] + updated[match.end():]

with open(wiki_file, "w") as f:
    f.write(updated)
WIKI_UPDATE
    echo -e "  ${G}✓${NC} Wiki Benchmarks.md updated with latest results"
fi

echo ""
