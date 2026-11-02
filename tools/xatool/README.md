# XA Tool

XA stream encoder and interleaver. Combines 2336-byte sector XA files into one playable file.

## Compilation

XA Tool is written in [D](https://dlang.org).

To build:

```
dub build --build=release-nobounds
```

## Usage

```
xatool [options] input1 [input2...]
```

Available options:

- `-o/--output <file>` - output XA path
- `-r/--rate` - resample input PCM to this rate (37800 or 18900 Hz)
- `-s/--stereo` - stereo output (true/false)
- `--file` - stream file number (0-255)
- `--span` - interleave span (sectors per cycle).

XA Tool can interleave existing XA streams, or transcode WAV/MP3/FLAC/OGG files to XA format. Typical usage scenario is to interleave multiple audio streams directly into one XA file:

```
xatool -o MUSIC.XA --file 1 channel0.mp3 channel1.mp3
```

Each input becomes one XA channel (input 1 -> channel 0, input 2 -> channel 1, etc). Slots without a stream get empty padding sectors (audio, Form 2, tagged with channel 31). The last real sector of each stream gets the EOF/EOR flags.

Interleave span (sectors per cycle):

- 8  = 37800 Hz stereo 4-bit (default)
- 16 = 18900 Hz stereo, or 37800 Hz mono
- 32 = 18900 Hz mono

Single stream mode (no interleaving, analogous to `psxavenc -t xa`):

```
xatool --single -o channel0.xa --file 1 --channel 0 channel0.mp3
```
