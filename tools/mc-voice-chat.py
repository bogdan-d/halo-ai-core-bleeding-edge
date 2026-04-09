#!/usr/bin/env python3
"""
mc-voice-chat — Voice-to-Minecraft chat pipeline
"I'm sorry, Dave. I'm afraid I can't do that." — HAL 9000

Records audio → Whisper ASR → text → RCON → Minecraft server chat.
Runs continuously. Press Ctrl+C to stop.

Usage:
    python3 mc-voice-chat.py [--server HOST] [--rcon-port PORT] [--rcon-pass PASS]
                             [--whisper URL] [--mic-device DEVICE] [--name NAME]
                             [--duration SECS] [--push-to-talk]
"""

import argparse
import io
import json
import os
import struct
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import wave


# ── RCON Protocol ──

RCON_AUTH = 3
RCON_CMD = 2
RCON_AUTH_RESPONSE = 2
RCON_RESPONSE = 0


def rcon_packet(req_id, ptype, payload):
    """Build an RCON packet."""
    data = struct.pack('<ii', req_id, ptype) + payload.encode('ascii') + b'\x00\x00'
    return struct.pack('<i', len(data)) + data


def rcon_recv(sock):
    """Receive an RCON response."""
    raw_len = sock.recv(4)
    if len(raw_len) < 4:
        return -1, -1, ''
    length = struct.unpack('<i', raw_len)[0]
    data = b''
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            break
        data += chunk
    req_id, ptype = struct.unpack('<ii', data[:8])
    payload = data[8:-2].decode('utf-8', errors='replace')
    return req_id, ptype, payload


def rcon_connect(host, port, password):
    """Connect and authenticate to RCON."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect((host, port))

    # Authenticate
    sock.sendall(rcon_packet(1, RCON_AUTH, password))
    req_id, ptype, _ = rcon_recv(sock)
    if req_id == -1:
        raise ConnectionError('RCON auth failed — bad password or server rejected')
    return sock


def rcon_command(sock, command):
    """Send an RCON command and get response."""
    sock.sendall(rcon_packet(2, RCON_CMD, command))
    _, _, payload = rcon_recv(sock)
    return payload


# ── Audio Recording ──

def record_audio(duration=5, device='default'):
    """Record audio using arecord, return WAV bytes."""
    tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    tmp.close()
    try:
        cmd = [
            'arecord', '-D', device, '-f', 'S16_LE',
            '-r', '16000', '-c', '1', '-t', 'wav',
            '-d', str(duration), tmp.name
        ]
        subprocess.run(cmd, capture_output=True, timeout=duration + 5)
        with open(tmp.name, 'rb') as f:
            return f.read()
    finally:
        os.unlink(tmp.name)


def record_audio_ssh(host, duration=5, device='default'):
    """Record audio from a remote host via SSH."""
    cmd = [
        'ssh', '-o', 'StrictHostKeyChecking=no', host,
        f'arecord -D {device} -f S16_LE -r 16000 -c 1 -t wav -d {duration} /tmp/mc-voice.wav && cat /tmp/mc-voice.wav && rm /tmp/mc-voice.wav'
    ]
    result = subprocess.run(cmd, capture_output=True, timeout=duration + 15)
    return result.stdout


# ── Whisper ASR ──

def transcribe(audio_bytes, whisper_url='http://127.0.0.1:8082/transcribe'):
    """Send audio to Whisper ASR and get text back."""
    boundary = b'----VoiceBoundary'
    body = b'--' + boundary + b'\r\n'
    body += b'Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n'
    body += b'Content-Type: audio/wav\r\n\r\n'
    body += audio_bytes + b'\r\n'
    body += b'--' + boundary + b'--\r\n'

    req = urllib.request.Request(
        whisper_url,
        data=body,
        headers={'Content-Type': f'multipart/form-data; boundary={boundary.decode()}'},
        method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result.get('text', '').strip()
    except Exception as e:
        print(f'  [whisper error] {e}', file=sys.stderr)
        return ''


def transcribe_lemonade(audio_bytes, lemonade_url='http://127.0.0.1:13305'):
    """Send audio to Lemonade's Whisper endpoint."""
    boundary = b'----VoiceBoundary'
    body = b'--' + boundary + b'\r\n'
    body += b'Content-Disposition: form-data; name="file"; filename="audio.wav"\r\n'
    body += b'Content-Type: audio/wav\r\n\r\n'
    body += audio_bytes + b'\r\n'
    body += b'--' + boundary + b'\r\n'
    body += b'Content-Disposition: form-data; name="model"\r\n\r\n'
    body += b'Whisper-Large-v3-Turbo\r\n'
    body += b'--' + boundary + b'--\r\n'

    req = urllib.request.Request(
        f'{lemonade_url}/v1/audio/transcriptions',
        data=body,
        headers={'Content-Type': f'multipart/form-data; boundary={boundary.decode()}'},
        method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result.get('text', '').strip()
    except Exception as e:
        print(f'  [lemonade whisper error] {e}', file=sys.stderr)
        return ''


# ── Main Loop ──

def main():
    parser = argparse.ArgumentParser(description='Voice-to-Minecraft chat')
    parser.add_argument('--server', default='localhost', help='Minecraft server host')
    parser.add_argument('--rcon-port', type=int, default=25575, help='RCON port')
    parser.add_argument('--rcon-pass', default='haloai', help='RCON password')
    parser.add_argument('--whisper', default='http://127.0.0.1:8082/transcribe', help='Whisper ASR URL')
    parser.add_argument('--lemonade-whisper', action='store_true', help='Use Lemonade Whisper instead')
    parser.add_argument('--mic-device', default='default', help='ALSA mic device')
    parser.add_argument('--mic-host', default='', help='SSH host for remote mic (e.g. ryzen)')
    parser.add_argument('--name', default='Architect', help='Chat display name')
    parser.add_argument('--duration', type=int, default=8, help='Recording duration in seconds')
    parser.add_argument('--continuous', action='store_true', help='Loop continuously')
    parser.add_argument('--min-length', type=int, default=3, help='Min text length to send')
    args = parser.parse_args()

    print(f'>> mc-voice-chat')
    print(f'   server:   {args.server}:{args.rcon_port}')
    print(f'   whisper:  {"lemonade" if args.lemonade_whisper else args.whisper}')
    print(f'   mic:      {args.mic_host or "local"}:{args.mic_device}')
    print(f'   name:     {args.name}')
    print(f'   duration: {args.duration}s per clip')
    print()

    # Connect to RCON
    print('connecting to Minecraft RCON...', end=' ', flush=True)
    try:
        sock = rcon_connect(args.server, args.rcon_port, args.rcon_pass)
        print('connected')
        rcon_command(sock, f'say [Voice Chat] {args.name} joined voice channel')
    except Exception as e:
        print(f'FAILED: {e}')
        print('make sure RCON is enabled in server.properties:')
        print('  enable-rcon=true')
        print(f'  rcon.password={args.rcon_pass}')
        print(f'  rcon.port={args.rcon_port}')
        sys.exit(1)

    print()
    print('listening... (Ctrl+C to stop)')
    print()

    try:
        while True:
            # Record
            sys.stdout.write(f'  [rec {args.duration}s] ')
            sys.stdout.flush()

            if args.mic_host:
                audio = record_audio_ssh(args.mic_host, args.duration, args.mic_device)
            else:
                audio = record_audio(args.duration, args.mic_device)

            if not audio or len(audio) < 1000:
                print('no audio captured')
                continue

            # Transcribe
            sys.stdout.write('transcribing... ')
            sys.stdout.flush()

            if args.lemonade_whisper:
                text = transcribe_lemonade(audio)
            else:
                text = transcribe(audio, args.whisper)

            # Filter noise / empty
            noise_phrases = {'', 'you', 'thank you', 'thanks', 'bye', 'the end',
                            'thank you for watching', 'thanks for watching',
                            'subtitles by the amara.org community'}
            if not text or text.lower().strip('.!?,') in noise_phrases or len(text) < args.min_length:
                print(f'[skip: "{text}"]')
                continue

            print(f'"{text}"')

            # Send to Minecraft
            try:
                msg = f'say <{args.name}> {text}'
                rcon_command(sock, msg)
                print(f'  [sent to server]')
            except (BrokenPipeError, ConnectionError):
                print('  [reconnecting RCON...]')
                try:
                    sock.close()
                    sock = rcon_connect(args.server, args.rcon_port, args.rcon_pass)
                    rcon_command(sock, f'say <{args.name}> {text}')
                except Exception as e:
                    print(f'  [RCON error: {e}]')

            if not args.continuous:
                break

    except KeyboardInterrupt:
        print('\n\nstopping voice chat...')
        try:
            rcon_command(sock, f'say [Voice Chat] {args.name} left voice channel')
        except Exception:
            pass
    finally:
        try:
            sock.close()
        except Exception:
            pass


if __name__ == '__main__':
    main()
