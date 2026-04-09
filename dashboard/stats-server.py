#!/usr/bin/env python3
"""Lightweight hardware stats + model catalog API for halo-ai dashboard."""

import json
import os
import time
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

import psutil


def get_hw_info():
    """Static hardware identity — what the machine IS."""
    cpu_name = 'Unknown CPU'
    try:
        with open('/proc/cpuinfo') as f:
            for line in f:
                if line.startswith('model name'):
                    cpu_name = line.split(':')[1].strip()
                    break
    except Exception:
        pass

    gpu_name = 'N/A'
    try:
        name_f = '/sys/class/drm/card1/device/product_name'
        if os.path.exists(name_f):
            gpu_name = open(name_f).read().strip()
        else:
            # Try lspci fallback
            vendor_f = '/sys/class/drm/card1/device/vendor'
            if os.path.exists(vendor_f):
                gpu_name = 'AMD Radeon (integrated)'
    except Exception:
        pass

    vram_total = 0
    try:
        vf = '/sys/class/drm/card1/device/mem_info_vram_total'
        if os.path.exists(vf):
            vram_total = int(open(vf).read().strip())
    except Exception:
        pass

    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')

    return {
        'cpu': cpu_name,
        'cores': psutil.cpu_count(logical=True),
        'ram_total': mem.total,
        'gpu': gpu_name,
        'vram_total': vram_total,
        'npu': 'AMD XDNA' if os.path.exists('/dev/accel/accel0') else 'N/A',
        'disk_total': disk.total,
    }


def get_gpu_stats():
    """Live GPU stats from sysfs."""
    gpu = {'temp': 0, 'usage': 0, 'vram_used': 0, 'vram_total': 0}
    try:
        hwmon_base = '/sys/class/drm/card1/device/hwmon'
        if os.path.isdir(hwmon_base):
            hwmon = os.path.join(hwmon_base, os.listdir(hwmon_base)[0])
            temp_file = os.path.join(hwmon, 'temp1_input')
            if os.path.exists(temp_file):
                gpu['temp'] = int(open(temp_file).read().strip()) // 1000

        busy = '/sys/class/drm/card1/device/gpu_busy_percent'
        if os.path.exists(busy):
            gpu['usage'] = int(open(busy).read().strip())

        vram_used_f = '/sys/class/drm/card1/device/mem_info_vram_used'
        vram_total_f = '/sys/class/drm/card1/device/mem_info_vram_total'
        if os.path.exists(vram_used_f):
            gpu['vram_used'] = int(open(vram_used_f).read().strip())
            gpu['vram_total'] = int(open(vram_total_f).read().strip())
    except Exception:
        pass
    return gpu


def get_live_stats():
    """Live performance stats — what the machine is DOING."""
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    cpu_freq = psutil.cpu_freq()
    temps = {}
    try:
        t = psutil.sensors_temperatures()
        if 'k10temp' in t:
            temps['cpu'] = t['k10temp'][0].current
        elif 'coretemp' in t:
            temps['cpu'] = t['coretemp'][0].current
    except Exception:
        pass

    gpu = get_gpu_stats()
    net = psutil.net_io_counters()
    uptime = time.time() - psutil.boot_time()

    return {
        'cpu': {
            'usage': psutil.cpu_percent(interval=0.5),
            'freq': round(cpu_freq.current) if cpu_freq else 0,
            'temp': round(temps.get('cpu', 0)),
        },
        'ram': {
            'used': mem.used,
            'percent': mem.percent,
        },
        'disk': {
            'used': disk.used,
            'percent': disk.percent,
        },
        'gpu': gpu,
        'npu_online': os.path.exists('/dev/accel/accel0'),
        'net': {
            'sent': net.bytes_sent,
            'recv': net.bytes_recv,
        },
        'uptime': int(uptime),
    }


def get_models():
    """Fetch model catalog from Lemonade."""
    try:
        req = urllib.request.Request('http://127.0.0.1:13305/api/tags', method='GET')
        req.add_header('Accept', 'application/json')
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read())
            models = []
            for m in data.get('models', []):
                family = m.get('details', {}).get('family', 'unknown')
                families = m.get('details', {}).get('families', [])
                backend = 'other'
                if 'flm' in families:
                    backend = 'npu'
                elif 'llamacpp' in families:
                    backend = 'gpu'
                elif 'sd-cpp' in families:
                    backend = 'image'
                elif 'whispercpp' in families:
                    backend = 'audio'
                elif 'kokoro' in families:
                    backend = 'audio'

                models.append({
                    'name': m.get('name', '').replace(':latest', ''),
                    'size': m.get('size', 0),
                    'params': m.get('details', {}).get('parameter_size', ''),
                    'quant': m.get('details', {}).get('quantization_level', ''),
                    'backend': backend,
                    'family': family,
                })
            return models
    except Exception:
        return []


def get_logs():
    """Get recent system logs relevant to halo-ai services."""
    import subprocess
    lines = []
    try:
        # Recent journal entries for halo services
        result = subprocess.run(
            ['journalctl', '--user', '-n', '50', '--no-pager', '-o', 'short-iso',
             '-u', 'lemonade*', '-u', 'halo-*', '-u', 'gaia*', '-u', 'caddy*', '-u', 'kokoro*'],
            capture_output=True, text=True, timeout=5
        )
        lines = result.stdout.strip().split('\n') if result.stdout.strip() else []
    except Exception:
        pass

    if not lines:
        try:
            result = subprocess.run(
                ['journalctl', '-n', '50', '--no-pager', '-o', 'short-iso'],
                capture_output=True, text=True, timeout=5
            )
            lines = result.stdout.strip().split('\n') if result.stdout.strip() else []
        except Exception:
            lines = ['[no journal access]']

    return {'lines': lines[-50:]}


def run_safe_cmd(cmd):
    """Run read-only safe commands for the terminal."""
    import subprocess
    import shlex

    # Whitelist of safe commands
    safe_prefixes = [
        'systemctl --user status', 'systemctl --user list-units',
        'systemctl status', 'journalctl',
        'uname', 'uptime', 'free', 'df', 'lscpu', 'lspci',
        'ip addr', 'ip link', 'ss -tlnp',
        'pacman -Q', 'pyenv versions',
        'lemonade status', 'lemonade list', 'lemonade backends',
        'cat /proc/cpuinfo', 'cat /proc/meminfo',
        'ls', 'pwd', 'whoami', 'hostname', 'date',
        'rocminfo', 'rocm-smi',
        'neofetch', 'fastfetch',
    ]

    if not cmd or not any(cmd.startswith(p) for p in safe_prefixes):
        return {'output': f'blocked: {cmd}\nonly read-only system commands allowed', 'exit': 1}

    try:
        result = subprocess.run(
            shlex.split(cmd), capture_output=True, text=True, timeout=10
        )
        output = result.stdout + result.stderr
        return {'output': output[-4000:], 'exit': result.returncode}
    except Exception as e:
        return {'output': str(e), 'exit': 1}


def get_gaia():
    """Fetch Gaia health + agent profiles."""
    result = {'status': 'offline', 'sessions': 0, 'messages': 0, 'agents': []}
    try:
        req = urllib.request.Request('http://127.0.0.1:4200/api/health', method='GET')
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read())
            result['status'] = data.get('status', 'unknown')
            stats = data.get('stats', {})
            result['sessions'] = stats.get('sessions', 0)
            result['messages'] = stats.get('messages', 0)
    except Exception:
        pass

    # Static agent profiles (from Gaia source)
    result['agents'] = [
        {'name': 'chat', 'display': 'Chat Agent', 'desc': 'RAG + vision', 'ctx': '32K'},
        {'name': 'code', 'display': 'Code Agent', 'desc': 'Autonomous coding', 'ctx': '32K'},
        {'name': 'talk', 'display': 'Talk Agent', 'desc': 'Voice-enabled chat', 'ctx': '32K'},
        {'name': 'rag', 'display': 'RAG System', 'desc': 'Document Q&A', 'ctx': '32K'},
        {'name': 'blender', 'display': 'Blender Agent', 'desc': '3D content gen', 'ctx': '32K'},
        {'name': 'jira', 'display': 'Jira Agent', 'desc': 'Issue management', 'ctx': '32K'},
        {'name': 'docker', 'display': 'Docker Agent', 'desc': 'Container mgmt', 'ctx': '32K'},
        {'name': 'vlm', 'display': 'Vision Agent', 'desc': 'Image understanding', 'ctx': '8K'},
        {'name': 'minimal', 'display': 'Minimal', 'desc': 'Fast responses', 'ctx': '4K'},
        {'name': 'mcp', 'display': 'MCP Bridge', 'desc': 'Tool integration', 'ctx': '32K'},
    ]
    return result


# Cache hardware info (doesn't change)
HW_INFO = get_hw_info()


class StatsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/stats':
            data = get_live_stats()
            data['hw'] = HW_INFO
            payload = json.dumps(data).encode()
        elif self.path == '/models':
            payload = json.dumps(get_models()).encode()
        elif self.path == '/gaia':
            payload = json.dumps(get_gaia()).encode()
        elif self.path == '/logs':
            payload = json.dumps(get_logs()).encode()
        elif self.path.startswith('/exec'):
            # Run safe read-only commands
            import urllib.parse
            qs = urllib.parse.urlparse(self.path).query
            params = urllib.parse.parse_qs(qs)
            cmd = params.get('cmd', [''])[0]
            payload = json.dumps(run_safe_cmd(cmd)).encode()
        else:
            self.send_response(404)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 5090), StatsHandler)
    print('Stats server on :5090')
    server.serve_forever()
