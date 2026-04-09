#!/usr/bin/env python3
"""
halo-ai voice agent — local-only conversational AI
"Open the pod bay doors, HAL." — Dave Bowman

Pipecat pipeline: Mic → Whisper STT → Lemonade LLM → Kokoro TTS → Speaker
Everything runs on localhost. No cloud. No latency. Pure Strix Halo power.

Usage:
    source ~/pipecat-env/bin/activate
    python3 voice-agent.py [--llm-model MODEL] [--voice VOICE] [--system-prompt TEXT]

Requires: pipecat-ai[silero,openai], aiohttp, pyaudio
"""

import argparse
import asyncio
import io
import struct
import wave

import aiohttp

from pipecat.frames.frames import (
    Frame,
    TTSAudioRawFrame,
    TTSStartedFrame,
    TTSStoppedFrame,
)
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.services.openai import OpenAILLMService
from pipecat.services.ai_services import STTService, TTSService
from pipecat.transports.local.audio import LocalAudioTransport
from pipecat.transports.base_transport import TransportParams
from pipecat.audio.vad.silero import SileroVADAnalyzer


# ── Custom STT: Local Whisper ──

class WhisperLocalSTT(STTService):
    """Whisper STT via local HTTP endpoint."""

    def __init__(self, base_url: str = "http://127.0.0.1:8082"):
        super().__init__()
        self._base_url = base_url
        self._session = None

    async def start(self, frame: Frame):
        await super().start(frame)
        self._session = aiohttp.ClientSession()

    async def stop(self, frame: Frame):
        if self._session:
            await self._session.close()
        await super().stop(frame)

    async def run_stt(self, audio: bytes) -> str | None:
        if not self._session or not audio:
            return None

        # Build WAV in memory (16kHz, 16-bit, mono)
        wav_buf = io.BytesIO()
        data_len = len(audio)
        wav_buf.write(b"RIFF")
        wav_buf.write(struct.pack("<I", 36 + data_len))
        wav_buf.write(b"WAVEfmt ")
        wav_buf.write(struct.pack("<IHHIIHH", 16, 1, 1, 16000, 32000, 2, 16))
        wav_buf.write(b"data")
        wav_buf.write(struct.pack("<I", data_len))
        wav_buf.write(audio)
        wav_buf.seek(0)

        form = aiohttp.FormData()
        form.add_field("file", wav_buf, filename="audio.wav",
                       content_type="audio/wav")

        try:
            async with self._session.post(
                f"{self._base_url}/transcribe", data=form, timeout=30
            ) as resp:
                if resp.status == 200:
                    result = await resp.json()
                    text = result.get("text", "").strip()
                    if text:
                        print(f"  [heard] {text}")
                    return text
        except Exception as e:
            print(f"  [stt error] {e}")
        return None


# ── Custom TTS: Local Kokoro ──

class KokoroLocalTTS(TTSService):
    """Kokoro TTS via local HTTP endpoint."""

    def __init__(self, base_url: str = "http://127.0.0.1:5000",
                 voice: str = "af_heart", sample_rate: int = 24000):
        super().__init__(sample_rate=sample_rate)
        self._base_url = base_url
        self._voice = voice
        self._session = None

    async def start(self, frame: Frame):
        await super().start(frame)
        self._session = aiohttp.ClientSession()

    async def stop(self, frame: Frame):
        if self._session:
            await self._session.close()
        await super().stop(frame)

    async def run_tts(self, text: str):
        if not self._session or not text.strip():
            return

        await self.push_frame(TTSStartedFrame())

        try:
            async with self._session.post(
                f"{self._base_url}/tts",
                json={"text": text, "voice": self._voice},
                timeout=30
            ) as resp:
                if resp.status == 200:
                    audio_data = await resp.read()

                    # Strip WAV header if present (44 bytes)
                    if audio_data[:4] == b"RIFF":
                        audio_data = audio_data[44:]

                    print(f"  [speak] {text[:80]}...")

                    await self.push_frame(
                        TTSAudioRawFrame(
                            audio=audio_data,
                            sample_rate=self.sample_rate,
                            num_channels=1,
                        )
                    )
        except Exception as e:
            print(f"  [tts error] {e}")

        await self.push_frame(TTSStoppedFrame())


# ── Main ──

async def main():
    parser = argparse.ArgumentParser(description="halo-ai voice agent")
    parser.add_argument("--whisper-url", default="http://127.0.0.1:8082",
                        help="Whisper ASR base URL")
    parser.add_argument("--lemonade-url", default="http://127.0.0.1:13305/v1",
                        help="Lemonade LLM base URL")
    parser.add_argument("--kokoro-url", default="http://127.0.0.1:5000",
                        help="Kokoro TTS base URL")
    parser.add_argument("--llm-model", default="Qwen3.5-35B-A3B-GGUF",
                        help="LLM model name")
    parser.add_argument("--voice", default="af_heart",
                        help="Kokoro voice name")
    parser.add_argument("--system-prompt", default=(
                        "You are a helpful AI assistant running on a local AMD Ryzen AI "
                        "MAX+ 395 system called halo-ai. You are conversational, concise, "
                        "and friendly. Keep responses under 3 sentences unless asked for more."
                        ),
                        help="System prompt for the LLM")
    args = parser.parse_args()

    print()
    print(">> halo-ai voice agent")
    print(f"   stt:   {args.whisper_url}")
    print(f"   llm:   {args.lemonade_url} ({args.llm_model})")
    print(f"   tts:   {args.kokoro_url} ({args.voice})")
    print()
    print("   speak naturally — the agent will respond when you pause")
    print("   press Ctrl+C to stop")
    print()

    # Transport: local mic + speaker
    transport = LocalAudioTransport(
        TransportParams(
            audio_in_enabled=True,
            audio_out_enabled=True,
            vad_enabled=True,
            vad_analyzer=SileroVADAnalyzer(),
            vad_audio_passthrough=True,
        )
    )

    # STT: Whisper
    stt = WhisperLocalSTT(base_url=args.whisper_url)

    # LLM: Lemonade (OpenAI-compatible)
    llm = OpenAILLMService(
        api_key="local",
        model=args.llm_model,
        base_url=args.lemonade_url,
    )

    # TTS: Kokoro
    tts = KokoroLocalTTS(
        base_url=args.kokoro_url,
        voice=args.voice,
        sample_rate=24000,
    )

    # Pipeline: mic → stt → llm → tts → speaker
    pipeline = Pipeline([
        transport.input(),
        stt,
        llm,
        tts,
        transport.output(),
    ])

    task = PipelineTask(
        pipeline,
        PipelineParams(allow_interruptions=True),
    )

    runner = PipelineRunner()

    print("listening...\n")
    await runner.run(task)


if __name__ == "__main__":
    asyncio.run(main())
