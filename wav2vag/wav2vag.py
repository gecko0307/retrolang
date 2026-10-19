#!/usr/bin/env python3
"""
wav2vag.py - Convert PCM WAV files to PlayStation SPU-ADPCM (.vag) files.

Pure Python 3, standard library only.

Usage:
  wav2vag.py input.wav                    -> input.vag
  wav2vag.py input.wav -o out.vag         -> out.vag
  wav2vag.py a.wav b.wav --rate 22050     -> resample to 22050 Hz first
  wav2vag.py loop.wav --loop              -> whole sample loops
  wav2vag.py loop.wav --loop-start 44100  -> loop from sample 44100 to the end
  wav2vag.py stereo.wav                   -> stereo_L.vag + stereo_R.vag
  wav2vag.py stereo.wav --mix             -> single mono-mixed VAG
  wav2vag.py input.vag --decode           -> input.wav (for checking results)

Format notes
------------
SPU-ADPCM stores 28 samples in each 16-byte block:
  byte 0   : low nibble = shift (0..12), high nibble = filter (0..4)
  byte 1   : flags (bit0 = loop end, bit1 = loop repeat, bit2 = loop start)
  bytes 2-15: 28 four-bit samples, low nibble first

Decoder per sample:
  s = (signed_nibble << 12) >> shift
  s += (old * f0 + older * f1 + 32) >> 6
with (f0, f1) from the 5-entry filter table below.

VAG file: 48-byte big-endian header ("VAGp"), then the ADPCM blocks.
Flags written: 0 normally; last block = 1 (end, mute) when not looping;
loop-start block = 6 and last block = 3 (end + repeat) when looping.
"""
import argparse
import os
import struct
import sys
import wave

FILTERS = ((0, 0), (60, 0), (115, -52), (98, -55), (122, -60))
BLOCK_SAMPLES = 28


def clamp16(v):
    return -32768 if v < -32768 else 32767 if v > 32767 else v


# --------------------------------------------------------------------------
# WAV input
# --------------------------------------------------------------------------
def read_wav(path):
    """Return (channels: list of list[int16], sample_rate)."""
    try:
        with wave.open(path, "rb") as w:
            nch, sw, rate, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(n)
    except wave.Error as e:
        raise SystemExit(f"{path}: cannot read WAV ({e}). Only integer PCM WAV is supported "
                         f"(8/16/24/32-bit); float WAVs must be converted first.")
    total = n * nch
    if sw == 1:
        samples = [(b - 128) << 8 for b in raw[:total]]
    elif sw == 2:
        samples = list(struct.unpack("<%dh" % total, raw[: total * 2]))
    elif sw == 3:
        samples = []
        for i in range(total):
            b = raw[i * 3: i * 3 + 3]
            v = b[0] | (b[1] << 8) | (b[2] << 16)
            if v & 0x800000:
                v -= 1 << 24
            samples.append(v >> 8)
    elif sw == 4:
        samples = [v >> 16 for v in struct.unpack("<%di" % total, raw[: total * 4])]
    else:
        raise SystemExit(f"{path}: unsupported sample width {sw * 8} bits")
    return [samples[c::nch] for c in range(nch)], rate


def resample(x, src, dst):
    """Linear-interpolation resampler."""
    if src == dst or not x:
        return x
    n_out = max(1, int(len(x) * dst / src))
    ratio = src / dst
    last = len(x) - 1
    out = []
    for i in range(n_out):
        pos = i * ratio
        j = int(pos)
        frac = pos - j
        a = x[j] if j <= last else x[last]
        b = x[j + 1] if j + 1 <= last else x[last]
        out.append(int(round(a + (b - a) * frac)))
    return out


# --------------------------------------------------------------------------
# Encoder
# --------------------------------------------------------------------------
def encode_block(block, h1, h2):
    """Encode 28 samples. Returns (shift, filter, nibbles, new_h1, new_h2)."""
    best = None
    for fi, (f0, f1) in enumerate(FILTERS):
        # Open-loop residual estimate -> finest shift whose range fits.
        p1, p2, mx = h1, h2, 0
        for s in block:
            d = abs(s - ((p1 * f0 + p2 * f1 + 32) >> 6))
            if d > mx:
                mx = d
            p2, p1 = p1, s
        shift = 12
        while shift > 0 and mx > 7 * (1 << (12 - shift)):
            shift -= 1
        cands = {shift}
        if shift > 0:
            cands.add(shift - 1)  # safety margin against clipping in closed loop
        for sh in cands:
            step = 1 << (12 - sh)
            half = step >> 1
            p1, p2, err = h1, h2, 0
            nibs = []
            for s in block:
                pred = (p1 * f0 + p2 * f1 + 32) >> 6
                n = (s - pred + half) // step
                n = -8 if n < -8 else 7 if n > 7 else n
                r = clamp16(n * step + pred)
                e = s - r
                err += e * e
                nibs.append(n & 0xF)
                p2, p1 = p1, r
            if best is None or err < best[0]:
                best = (err, sh, fi, nibs, p1, p2)
    _, sh, fi, nibs, p1, p2 = best
    return sh, fi, nibs, p1, p2


def encode_adpcm(samples, loop_start=None):
    """Encode a mono int16 list to raw SPU-ADPCM blocks (bytes).

    loop_start: None for a one-shot sample, otherwise the sample index where the
    loop begins (rounded down to a 28-sample block boundary).
    """
    if not samples:
        samples = [0]
    pad = (-len(samples)) % BLOCK_SAMPLES
    samples = list(samples) + [0] * pad
    nblocks = len(samples) // BLOCK_SAMPLES
    loop_block = None if loop_start is None else min(loop_start // BLOCK_SAMPLES, nblocks - 1)

    out = bytearray()
    h1 = h2 = 0
    for b in range(nblocks):
        blk = samples[b * BLOCK_SAMPLES:(b + 1) * BLOCK_SAMPLES]
        sh, fi, nibs, h1, h2 = encode_block(blk, h1, h2)
        flag = 0
        if loop_block is None:
            if b == nblocks - 1:
                flag = 1
        else:
            if b == loop_block:
                flag = 6
            if b == nblocks - 1:
                flag = 3
        out.append(sh | (fi << 4))
        out.append(flag)
        for i in range(0, BLOCK_SAMPLES, 2):
            out.append(nibs[i] | (nibs[i + 1] << 4))
    return bytes(out)


def build_vag(adpcm, rate, name):
    nm = name.encode("ascii", "replace")[:16].ljust(16, b"\0")
    hdr = b"VAGp" + struct.pack(">IIII", 0x20, 0, len(adpcm), rate) + b"\0" * 12 + nm
    assert len(hdr) == 48
    return hdr + adpcm


# --------------------------------------------------------------------------
# Decoder (for verification)
# --------------------------------------------------------------------------
def decode_vag(data):
    if data[:4] not in (b"VAGp", b"pGAV"):
        raise SystemExit("Not a VAG file (missing VAGp magic)")
    big = data[:4] == b"VAGp"
    size, rate = struct.unpack(">II" if big else "<II", data[12:20])
    body = data[48:48 + size] if size else data[48:]
    out = []
    h1 = h2 = 0
    for off in range(0, len(body) - 15, 16):
        sh, fi = body[off] & 0xF, (body[off] >> 4) % 5
        flag = body[off + 1]
        f0, f1 = FILTERS[fi]
        sh = min(sh, 12)
        for i in range(14):
            byte = body[off + 2 + i]
            for nib in (byte & 0xF, byte >> 4):
                if nib & 8:
                    nib -= 16
                s = clamp16(((nib << 12) >> sh) + ((h1 * f0 + h2 * f1 + 32) >> 6))
                out.append(s)
                h2, h1 = h1, s
        if flag & 1:
            break
    return out, rate


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------
def convert_file(path, args):
    stem = os.path.splitext(os.path.basename(path))[0]
    chans, rate = read_wav(path)
    if len(chans) > 1 and args.mix:
        n = min(len(c) for c in chans)
        chans = [[sum(c[i] for c in chans) // len(chans) for i in range(n)]]
    if args.rate and args.rate != rate:
        chans = [resample(c, rate, args.rate) for c in chans]
        rate = args.rate

    if args.loop_start is not None:
        loop_start = args.loop_start  # in output samples (after any resampling)
    elif args.loop:
        loop_start = 0
    else:
        loop_start = None

    base = args.output[:-4] if args.output and args.output.lower().endswith(".vag") else args.output
    if base is None:
        base = os.path.join(os.path.dirname(path), stem)

    suffixes = [""] if len(chans) == 1 else ["_L", "_R"] + [f"_{i}" for i in range(2, len(chans))]
    for ch, suf in zip(chans, suffixes):
        vag = build_vag(encode_adpcm(ch, loop_start), rate, (args.name or stem) + suf)
        dst = base + suf + ".vag"
        with open(dst, "wb") as f:
            f.write(vag)
        dur = len(ch) / rate
        print(f"{path} -> {dst}  ({len(ch)} samples, {rate} Hz, {dur:.2f}s, {len(vag)} bytes"
              f"{', looped' if loop_start is not None else ''})")


def decode_file(path, args):
    with open(path, "rb") as f:
        samples, rate = decode_vag(f.read())
    dst = args.output or os.path.splitext(path)[0] + ".wav"
    with wave.open(dst, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<%dh" % len(samples), *samples))
    print(f"{path} -> {dst}  ({len(samples)} samples, {rate} Hz)")


def main():
    ap = argparse.ArgumentParser(description="Convert PCM WAV to PlayStation SPU-ADPCM VAG.")
    ap.add_argument("inputs", nargs="+", help="input .wav files (or .vag with --decode)")
    ap.add_argument("-o", "--output", help="output path (single input only)")
    ap.add_argument("-r", "--rate", type=int, help="resample to this rate in Hz (max 44100 for SPU)")
    ap.add_argument("--name", help="name stored in the VAG header (max 16 chars)")
    ap.add_argument("--loop", action="store_true", help="loop the whole sample")
    ap.add_argument("--loop-start", type=int, metavar="SAMPLE",
                    help="loop from this sample (rounded down to a 28-sample block) to the end")
    ap.add_argument("--mix", action="store_true", help="mix multichannel input down to mono")
    ap.add_argument("--decode", action="store_true", help="decode VAG back to WAV")
    args = ap.parse_args()

    if args.output and len(args.inputs) > 1:
        ap.error("-o can only be used with a single input")
    if args.rate and not (0 < args.rate <= 44100):
        ap.error("--rate must be between 1 and 44100")

    for p in args.inputs:
        (decode_file if args.decode else convert_file)(p, args)


if __name__ == "__main__":
    main()
