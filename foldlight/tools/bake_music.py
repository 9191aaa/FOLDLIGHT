"""Bake FOLDLIGHT's synchronized, seamless 32-beat paper-sea music stems.

Regenerate from the Godot project directory with ``python tools/bake_music.py``.
Requires numpy and imageio-ffmpeg (the latter supplies an offline FFmpeg binary).
Only the two small Ogg Vorbis stems and their looping import settings ship.
Intermediate PCM, decoded PCM and the numeric verification report are written
under ignored build/test-runtime/web-audio-waveform/music-bake/.

Both stems have exactly the same sample count, tempo and musical phase. Start
them together, leave base at unity and multiply energy by intensity in [0, 1].
The score retains A/F/C/G add9/maj7 voicings and the 1.24 beats/second rhythm.
Pad oscillators complete an integer number of cycles over the loop, with a
0.56-second crossfade centered on each chord boundary. Arpeggios use note-local
phase with an 8 ms attack; bass pulses integrate their 75-to-55 Hz single-beat
sweep. Shimmer is bounded, periodic FM. Nothing depends on elapsed play time.
Both stem edges taper to silence over 12 ms, avoiding decoder startup padding
becoming a click when the browser loops its decoded AudioBuffer.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import wave
from pathlib import Path

import imageio_ffmpeg
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/audio"
DIAGNOSTICS = ROOT / "build/test-runtime/web-audio-waveform/music-bake"
RATE = 44_100
BEATS = 32
BEATS_PER_SECOND = 1.24
FRAMES = round(RATE * BEATS / BEATS_PER_SECOND)
DURATION = FRAMES / RATE
BEAT_DURATION = DURATION / BEATS
CHORDS = ((45, 52, 57, 61), (41, 48, 52, 57), (48, 55, 59, 64), (43, 50, 57, 59))
ARP_ORDER = (0, 2, 1, 3, 2, 1, 3, 1)
MASTER_GAIN = 0.58


def hz(note: int) -> float:
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def smoothstep(value: np.ndarray) -> np.ndarray:
    u = np.clip(value, 0.0, 1.0)
    return u * u * (3.0 - 2.0 * u)


def periodic_sine(t: np.ndarray, frequency: float, phase: float = 0.0) -> np.ndarray:
    # Frequency rounding is <= 0.0194 Hz; every oscillator joins continuously.
    cycles = round(frequency * DURATION)
    return np.sin(2.0 * np.pi * cycles * t / DURATION + phase)


def synthesize() -> dict[str, np.ndarray]:
    t = np.arange(FRAMES, dtype=np.float64) / RATE
    beat = t / BEAT_DURATION
    chord_duration = BEAT_DURATION * 8.0
    chord_index = np.floor(beat / 8.0).astype(np.int64) % 4
    local_chord = np.remainder(t, chord_duration)
    half_fade = 0.28
    weights = np.zeros((4, FRAMES), dtype=np.float64)
    for chord in range(4):
        region = chord_index == chord
        weights[chord, region] = 1.0
        incoming = region & (local_chord < half_fade)
        progress = (local_chord[incoming] + half_fade) / (half_fade * 2.0)
        blend = 0.5 - 0.5 * np.cos(np.pi * progress)
        weights[chord, incoming] = blend
        weights[(chord - 1) % 4, incoming] = 1.0 - blend
        outgoing = region & (local_chord > chord_duration - half_fade)
        progress = (local_chord[outgoing] - chord_duration + half_fade) / (half_fade * 2.0)
        blend = 0.5 - 0.5 * np.cos(np.pi * progress)
        weights[chord, outgoing] = 1.0 - blend
        weights[(chord + 1) % 4, outgoing] = blend
    assert np.max(np.abs(weights.sum(axis=0) - 1.0)) < 1e-12

    pad = np.zeros(FRAMES)
    for chord, notes in enumerate(CHORDS):
        voice = np.zeros(FRAMES)
        for index, note in enumerate(notes):
            detune = 1.0 + (index - 1.5) * 0.0017
            voice += periodic_sine(t, hz(note) * detune, index * 0.7) * (0.12 / (index + 1))
            voice += periodic_sine(t, hz(note) * 0.5, float(index)) * 0.025
        pad += voice * weights[chord]
    breath = 0.72 - 0.28 * np.cos(2.0 * np.pi * beat / 8.0)

    arp_base = np.zeros(FRAMES)
    arp_energy = np.zeros(FRAMES)
    arp_duration = BEAT_DURATION * 0.5
    for step in range(BEATS * 2):
        start = step * arp_duration
        mask = (t >= start) & (t < start + arp_duration)
        local_t = t[mask] - start
        local_u = local_t / arp_duration
        note = CHORDS[step // 16][ARP_ORDER[step % 8]] + 12
        envelope = smoothstep(local_t / 0.008) * (1.0 - local_u) ** 3.4
        fundamental = np.sin(2.0 * np.pi * hz(note) * local_t)
        overtone = np.sin(2.0 * np.pi * hz(note) * 2.01 * local_t)
        arp_base[mask] = (fundamental * 0.045 + overtone * 0.012) * envelope
        arp_energy[mask] = fundamental * 0.055 * envelope

    local_pulse = np.remainder(t, BEAT_DURATION)
    pulse_u = local_pulse / BEAT_DURATION
    # Integral of f(t)=75 - 20*t/beat_duration, rather than f(t)*global_time.
    pulse_phase = 2.0 * np.pi * (75.0 * local_pulse - 10.0 * local_pulse**2 / BEAT_DURATION)
    pulse_env = smoothstep(local_pulse / 0.006) * np.exp(-pulse_u * 12.0)
    pulse_env *= smoothstep((BEAT_DURATION - local_pulse) / 0.03)
    pulse = np.sin(pulse_phase) * pulse_env * 0.075

    shimmer_carrier = round(880.0 * DURATION)
    modulation_phase = 2.0 * np.pi * t / DURATION
    # Frequency deviation is always +/-4 Hz, even after hours of looping.
    shimmer_phase = 2.0 * np.pi * shimmer_carrier * t / DURATION + 4.0 * DURATION * (1.0 - np.cos(modulation_phase))
    shimmer = np.sin(shimmer_phase) * 0.004 * breath
    width = np.sin(modulation_phase) * 0.035 + np.sin(modulation_phase * 3.0) * 0.018
    wrap_fade = smoothstep(t / 0.012) * smoothstep((t[-1] - t) / 0.012)

    def stereo(mono: np.ndarray) -> np.ndarray:
        tapered = mono * wrap_fade
        return np.column_stack((tapered * (1.0 - width), tapered * (1.0 + width))) * MASTER_GAIN

    return {
        "paper_sea_base": stereo(pad * breath + arp_base + shimmer),
        "paper_sea_energy": stereo(arp_energy + pulse),
    }


def metrics(data: np.ndarray) -> dict[str, object]:
    adjacent = np.abs(np.diff(data, axis=0))
    joins = []
    for half_beat in range(1, BEATS * 2):
        index = round(half_beat * FRAMES / (BEATS * 2))
        joins.append(float(np.max(np.abs(data[index] - data[index - 1]))))
    return {
        "frames": int(data.shape[0]),
        "seconds": data.shape[0] / RATE,
        "peak": float(np.max(np.abs(data))),
        "rms": float(np.sqrt(np.mean(data**2))),
        "dc": data.mean(axis=0).tolist(),
        "first_sample": data[0].tolist(),
        "last_sample": data[-1].tolist(),
        "loop_boundary_delta": float(np.max(np.abs(data[0] - data[-1]))),
        "max_half_beat_boundary_delta": max(joins),
        "max_adjacent_delta": float(np.max(adjacent)),
        "adjacent_delta_p99": float(np.percentile(adjacent, 99.0)),
    }


def write_wav(path: Path, data: np.ndarray) -> None:
    assert np.max(np.abs(data)) < 1.0
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(np.rint(data * 32767.0).astype("<i2").tobytes())


def write_import(path: Path) -> None:
    source = "res://" + path.relative_to(ROOT).as_posix()
    digest = hashlib.md5(source.encode("utf-8")).hexdigest()
    imported = f"res://.godot/imported/{path.name}-{digest}.oggvorbisstr"
    import_path = Path(str(path) + ".import")
    # Keep the engine-assigned UID if regenerating after a Godot import.
    uid = ""
    if import_path.exists():
        uid = next((line for line in import_path.read_text(encoding="utf-8").splitlines() if line.startswith("uid=")), "")
    import_path.write_text(
        '[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n'
        + (uid + "\n" if uid else "")
        + f'path="{imported}"\n\n[deps]\n\nsource_file="{source}"\ndest_files=["{imported}"]\n\n[params]\n\n'
        + 'loop=true\nloop_offset=0\nbpm=74.4\nbeat_count=32\nbar_beats=4\n',
        encoding="utf-8",
    )


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    DIAGNOSTICS.mkdir(parents=True, exist_ok=True)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    stems = synthesize()
    decoded_stems = {}
    report: dict[str, object] = {
        "sample_rate": RATE,
        "beats": BEATS,
        "intended_beats_per_second": BEATS_PER_SECOND,
        "actual_beats_per_second": BEATS / DURATION,
        "duration_seconds": DURATION,
        "phase_model": "local arp/pulse phase; periodic pad/FM; centered 0.56s chord crossfades",
        "regenerate": "python tools/bake_music.py",
    }
    for name, data in stems.items():
        wav_path = DIAGNOSTICS / f"{name}.wav"
        ogg_path = ASSETS / f"{name}.ogg"
        write_wav(wav_path, data)
        subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav_path), "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "3", str(ogg_path)], check=True)
        pcm = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(ogg_path), "-f", "f32le", "-acodec", "pcm_f32le", "-ar", str(RATE), "-ac", "2", "pipe:1"], check=True, stdout=subprocess.PIPE).stdout
        decoded = np.frombuffer(pcm, dtype="<f4").reshape(-1, 2).astype(np.float64)
        decoded_stems[name] = decoded
        assert decoded.shape == data.shape, f"Vorbis changed {name}'s synchronization length"
        # A join must be no larger than the ordinary waveform's own slopes.
        decoded_metrics = metrics(decoded)
        assert decoded_metrics["peak"] < 0.35, f"{name} exceeds reserved headroom"
        assert decoded_metrics["loop_boundary_delta"] < 0.006, f"{name} has an audible loop discontinuity"
        assert np.max(np.abs(decoded[[0, -1]])) < 0.001, f"{name}'s decoded loop edges exceed the silence margin"
        assert ogg_path.stat().st_size < 300_000
        write_wav(DIAGNOSTICS / f"{name}_decoded.wav", decoded)
        write_import(ogg_path)
        report[name] = {"pcm": metrics(data), "decoded": decoded_metrics, "ogg_bytes": ogg_path.stat().st_size, "sha256": hashlib.sha256(ogg_path.read_bytes()).hexdigest()}
    report["full_intensity_pcm"] = metrics(stems["paper_sea_base"] + stems["paper_sea_energy"])
    report["full_intensity_decoded"] = metrics(decoded_stems["paper_sea_base"] + decoded_stems["paper_sea_energy"])
    assert report["full_intensity_decoded"]["peak"] < 0.35
    # Preserve an audible review loop with the seam in the middle of the file.
    full_mix = decoded_stems["paper_sea_base"] + decoded_stems["paper_sea_energy"]
    write_wav(DIAGNOSTICS / "loop_seam_review.wav", np.concatenate((full_mix[-RATE * 2 :], full_mix[: RATE * 2])))
    output = DIAGNOSTICS / "music_bake_report.json"
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    print(f"Verified synchronized stems. Report: {output}")


if __name__ == "__main__":
    main()
