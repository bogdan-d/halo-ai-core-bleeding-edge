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


# ── SSH Mesh Manager ──────────────────────────────────────────
import subprocess as _sp_ssh
import shlex as _shlex

SSH_MACHINES = {
    'strixhalo': {'ip': '10.0.0.10', 'user': 'bcloud', 'role': 'AI inference (headless)', 'os': 'Arch'},
    'ryzen':     {'ip': '10.0.0.25', 'user': 'bcloud', 'role': 'Primary workstation', 'os': 'Arch/KDE'},
    'sliger':    {'ip': '10.0.0.20', 'user': 'bcloud', 'role': 'AMP workloads', 'os': 'Arch'},
    'minisforum':{'ip': '10.0.0.30', 'user': 'bcloud', 'role': 'Office/VSS', 'os': 'Windows 11'},
    'pi':        {'ip': '10.0.0.40', 'user': 'bcloud', 'role': 'Storage/SATA', 'os': 'Debian'},
}

def ssh_status():
    results = {}
    for name, info in SSH_MACHINES.items():
        reachable = False
        try:
            r = _sp_ssh.run(
                ['ssh', '-o', 'ConnectTimeout=2', '-o', 'BatchMode=yes',
                 f"{info['user']}@{info['ip']}", 'echo ok'],
                capture_output=True, text=True, timeout=4
            )
            reachable = r.returncode == 0
        except Exception:
            pass
        results[name] = {**info, 'online': reachable}
    return results

def ssh_test(name):
    if name not in SSH_MACHINES:
        return {'error': f'unknown machine: {name}'}
    info = SSH_MACHINES[name]
    try:
        r = _sp_ssh.run(
            ['ssh', '-o', 'ConnectTimeout=3', '-o', 'BatchMode=yes',
             f"{info['user']}@{info['ip']}", 'uname -a && uptime'],
            capture_output=True, text=True, timeout=8
        )
        return {'name': name, 'output': r.stdout.strip(), 'ok': r.returncode == 0}
    except Exception as e:
        return {'name': name, 'output': str(e), 'ok': False}


# ── Snapshot Manager ──────────────────────────────────────────

def snapshot_list():
    try:
        r = _sp_ssh.run(['sudo', 'btrfs', 'subvolume', 'list', '-s', '/'],
                        capture_output=True, text=True, timeout=5)
        snaps = []
        for line in r.stdout.strip().split('\n'):
            if not line.strip():
                continue
            parts = line.split()
            # Extract ID, gen, path
            snap = {'raw': line.strip()}
            for i, p in enumerate(parts):
                if p == 'path':
                    snap['path'] = ' '.join(parts[i+1:])
                elif p == 'ID':
                    snap['id'] = parts[i+1] if i+1 < len(parts) else ''
            snaps.append(snap)
        return {'snapshots': snaps, 'count': len(snaps)}
    except Exception as e:
        return {'snapshots': [], 'error': str(e)}

def snapshot_create(name=''):
    tag = name or f"dashboard-{int(time.time())}"
    try:
        r = _sp_ssh.run(
            ['sudo', 'btrfs', 'subvolume', 'snapshot', '/', f'/.snapshots/{tag}'],
            capture_output=True, text=True, timeout=10
        )
        return {'status': 'created' if r.returncode == 0 else 'failed',
                'name': tag, 'output': r.stdout + r.stderr}
    except Exception as e:
        return {'status': 'error', 'error': str(e)}

def system_update():
    """Dry-run pacman update to show what would change."""
    try:
        r = _sp_ssh.run(['pacman', '-Syu', '--print'], capture_output=True, text=True, timeout=30)
        packages = [l.strip() for l in r.stdout.strip().split('\n') if l.strip() and '://' in l]
        return {'packages': len(packages), 'list': packages[:50], 'preview': True}
    except Exception as e:
        return {'error': str(e)}


# ── Model Manager ──────────────────────────────────────────────

def model_list_detailed():
    """Get models with loaded/unloaded status from Lemonade."""
    try:
        req = urllib.request.Request('http://127.0.0.1:13305/api/v1/models', method='GET')
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
            models = []
            for m in data.get('data', []):
                models.append({
                    'id': m.get('id', ''),
                    'owned_by': m.get('owned_by', 'local'),
                })
            return {'models': models, 'count': len(models)}
    except Exception as e:
        return {'models': [], 'error': str(e)}


# ── Agent Process Controller ──────────────────────────────────
import subprocess as _sp
import signal

AGENT_DIR = '/home/bcloud/discord-agents'
AGENT_VENV = '/home/bcloud/discord-agents-env/bin/python'
AGENT_STATE_FILE = os.path.join(AGENT_DIR, '.agent-state.json')
VALID_AGENTS = ('echo', 'bounty', 'meek', 'amp', 'mechanic', 'muse')

_agent_procs: dict = {}  # name -> subprocess.Popen


def _load_agent_state():
    try:
        with open(AGENT_STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _save_agent_state():
    state = {name: True for name in _agent_procs if _is_agent_alive(name)}
    with open(AGENT_STATE_FILE, 'w') as f:
        json.dump(state, f)


def _is_agent_alive(name):
    proc = _agent_procs.get(name)
    return proc is not None and proc.poll() is None


def agent_start(name):
    if name not in VALID_AGENTS:
        return {'error': f'unknown agent: {name}'}
    # Kill any orphan processes for this agent before starting
    try:
        import subprocess
        subprocess.run(['pkill', '-f', f'discord-agents/{name}/bot.py'], capture_output=True, timeout=3)
    except Exception:
        pass
    if _is_agent_alive(name):
        return {'status': 'already_running', 'agent': name, 'pid': _agent_procs[name].pid}
    bot_path = os.path.join(AGENT_DIR, name, 'bot.py')
    if not os.path.exists(bot_path):
        return {'error': f'bot not found: {bot_path}'}
    proc = _sp.Popen(
        [AGENT_VENV, '-u', bot_path],
        cwd=AGENT_DIR,
        stdout=_sp.DEVNULL, stderr=_sp.DEVNULL,
        start_new_session=True,
    )
    _agent_procs[name] = proc
    _save_agent_state()
    return {'status': 'started', 'agent': name, 'pid': proc.pid}


def agent_stop(name):
    if name not in VALID_AGENTS:
        return {'error': f'unknown agent: {name}'}
    if not _is_agent_alive(name):
        _agent_procs.pop(name, None)
        _save_agent_state()
        return {'status': 'not_running', 'agent': name}
    proc = _agent_procs[name]
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except Exception:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    _agent_procs.pop(name, None)
    _save_agent_state()
    return {'status': 'stopped', 'agent': name}


def agent_status_all():
    result = {}
    for name in VALID_AGENTS:
        result[name] = {'running': _is_agent_alive(name)}
        if _is_agent_alive(name):
            result[name]['pid'] = _agent_procs[name].pid
    return result


def _autostart_agents():
    """Restore agents that were running before shutdown."""
    state = _load_agent_state()
    for name, was_running in state.items():
        if was_running and name in VALID_AGENTS:
            agent_start(name)
            print(f'[AUTOSTART] {name}')


# Cache hardware info (doesn't change)
HW_INFO = get_hw_info()


class StatsHandler(BaseHTTPRequestHandler):
    def _respond(self, data):
        payload = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == '/stats':
            data = get_live_stats()
            data['hw'] = HW_INFO
            self._respond(data)
        elif self.path == '/models':
            self._respond(get_models())
        elif self.path == '/gaia':
            self._respond(get_gaia())
        elif self.path == '/logs':
            self._respond(get_logs())
        elif self.path == '/api/agents':
            self._respond(agent_status_all())
        elif self.path == '/api/ssh':
            self._respond(ssh_status())
        elif self.path.startswith('/api/ssh/test/'):
            name = self.path.split('/')[-1]
            self._respond(ssh_test(name))
        elif self.path == '/api/snapshots':
            self._respond(snapshot_list())
        elif self.path == '/api/update/preview':
            self._respond(system_update())
        elif self.path == '/api/models/detailed':
            self._respond(model_list_detailed())
        elif self.path.startswith('/exec'):
            import urllib.parse
            qs = urllib.parse.urlparse(self.path).query
            params = urllib.parse.parse_qs(qs)
            cmd = params.get('cmd', [''])[0]
            self._respond(run_safe_cmd(cmd))
        else:
            self.send_response(404)
            self.end_headers()
            return

    def do_POST(self):
        import urllib.parse
        parts = urllib.parse.urlparse(self.path)
        path = parts.path

        if path == '/api/snapshots/create':
            length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(length)) if length else {}
            self._respond(snapshot_create(body.get('name', '')))
        elif path.startswith('/api/agents/') and path.endswith('/start'):
            name = path.split('/')[3]
            self._respond(agent_start(name))
        elif path.startswith('/api/agents/') and path.endswith('/stop'):
            name = path.split('/')[3]
            self._respond(agent_stop(name))
        else:
            self.send_response(404)
            self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def log_message(self, format, *args):
        pass


if __name__ == '__main__':
    _autostart_agents()
    server = HTTPServer(('127.0.0.1', 5090), StatsHandler)
    print('Stats server on :5090')
    server.serve_forever()
