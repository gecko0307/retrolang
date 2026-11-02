# WAV2VAG

Encoder/decoder for PlayStation ADPCM VAG files.

## Compilation

WAV2VAG is written in [D](https://dlang.org).

To build:

```
dub build --build=release-nobounds
```

## Usage

```
wav2vag [options] input.wav
```

Available options:

- `-o/--output <file>` - output path
- `-r/--rate <hz>` - resample to this rate (1..44100)
- `--name <name>` - name stored in the VAG header (maximum 16 chars)
- `--loop` - loop the whole sample
- `--loop-start <n>` - loop from this output sample to the end
- `--mix` - mix multichannel input down to mono
- `--decode` - decode VAG back to WAV.

## VAG Format

VAG is an audio compression format developed by Sony. It served as the standard format for storing music, sound effects, and voiceovers in games for the PlayStation 1 (PSX), PlayStation 2 (PS2), and PlayStation Portable (PSP) consoles. VAG utilizes 4-bit PS-ADPCM (Adaptive Differential Pulse Code Modulation) compression. The compression ratio is approximately 3.5:1 compared to uncompressed 16-bit PCM.

A VAG file begins with a 48-byte header:

- `0x00` - 4 "magic" bytes: `"VAGp"`
- `0x04` - Version (4-byte word) - 3 or 32
- `0x08` - 4 reserved bytes
- `0x0C` - Size of the audio data in bytes (4-byte word)
- `0x10` - Sampling rate in Hertz (4-byte word)
- `0x14` - 12 reserved bytes
- `0x20` - ASCII name of the sound (16 bytes)

Following this is the ADPCM data, which is stored in 16-byte blocks. Each block contains 2 bytes of control information (decoding coefficients and looping parameters) and 14 bytes of actual audio data, which decodes into 28 audio samples.

The structure of each block is as follows:

- 1 byte (`uint8`) - Decoding parameters (shift factor and filter)
- 1 byte (`uint8`) - Playback control flags: 3 = block ends a loop, 6 = block begins a loop, 7 = block ends playback
- 14 bytes (28 samples) - Audio data for the block.
