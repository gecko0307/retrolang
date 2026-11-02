# SEQ Tool

SEQ Tool is a multi-purpose sequencer music converter that can do the following:

- Convert a Standard MIDI file (format 0 or 1) to PlayStation SEQ file
- Convert a ProTracker MOD file to PlayStation SEQ file
- Generate a VAB instrument bank from a SoundFont 2 file.

## Compilation

SEQ Tool is written in [D](https://dlang.org).

To build:

```
dub build --build=release-nobounds
```

## Usage

```
seqtool <command> [options] <input>
```

Available commands:

- `convert` - convert a song file to SEQ
- `bank` - generate an instrument bank.

Available options for the `convert` command:

- `-o/--output <file>` - specify output SEQ file name (default is input name with a ".seq" extension)
- `--bank-out <name>` - MOD: specify MOD VAB bank base name (default is output name without extension)
- `--vab` - MOD: write the bank as a single .vab file instead of .vh + .vb
- `--map-out <file>` - MIDI: write a program map for seqtool bank (default filename is output name with a ".map" extension)
- `--map-in <file>` - MIDI: use an existing program map (e.g. of a ready sound bank) instead of generating one; notes without an instrument are dropped
- `--loop` - loop the whole song if no loop markers/order loop exists
- `--drum-channel <n>` - MIDI: channel (1..16) that carries drums, 0 for none (default 10)
- `--ppqn <n>` - rescale the time resolution (ticks per quarter note). MOD default: 96
- `--tones <n>` - MIDI: maximum drum keys per program, 1..16 (default 16).

Available options for the `bank` command:

- `-o/--output <file>` - output base name (default is the input map name)
- `--vab` - write a single .vab file instead of .vh + .vb
- `--rate <hz>` - highest sample rate to keep (default 22050)
- `--budget <bytes>` - SPU memory available for samples (default 400000); the rate and sample length are reduced to fit
- `--velocity <1..127>` - velocity used to choose velocity layers (default 100)
- `--layers <n>` - layered samples per key (default 1)
- `--max-seconds <s>` - trim samples that do not loop to this length (default 6)
- `--bend <n>` - pitch bend range in semitones (default 2)
- `--stereo` - keep both channels of stereo samples (default: left only)
- `-v/--verbose` - print every sample
- `--list` - list the presets of the SoundFont.

## Converting MIDI to SEQ

A MIDI file contains instrument numbers, not instrument samples. Conversion therefore writes a program map describing the instruments used; pass that map to `bank` command to build a matching VAB from a SoundFont.

```
seqtool convert song.mid
seqtool bank soundfont.sf2 song.map
```

### Notes

- Drum keys are grouped into programs of up to `--tones` keys each.
- Use `seqtool convert --map-in <file>` to use an existing program map instead of generating one. Notes for instruments missing from that map are dropped.
- Loop points: MIDI markers named `loopStart` / `loopEnd`, or controller 111 (loop start). Without a loop end, the end of the song is used.
- Supported controllers: bank select, volume (7), pan (10), expression (11), sustain (64), all notes off (120/123). Pitch bend is passed through; the bend range is fixed per tone (RPN changes are dropped). Other controllers and aftertouch are dropped and reported.
- SMPTE time division and type 2 files are not supported.

## Converting MOD to SEQ

For MOD files, the VAB is built from samples embedded in the module, so a separate bank generation step is not needed.

```
seqtool convert song.mod
```

### How a module is mapped

- The four MOD channels become SEQ channels 1-4 with the classic L-R-R-L panning.
- Every non-empty sample becomes one VAB program with a single tone. Program `n` plays sample `n+1`, so a tracker instrument number maps directly to a program number (instruments 1-31 → programs 0-30).
- Samples are converted from 8-bit PCM to SPU ADPCM. The tone's center note and fine tune are computed from the Amiga (PAL) clock and the sample's finetune value, so a note sounds at the pitch it has in the tracker.
- Row timing is derived from tempo and speed: a quarter note is always 24 module ticks, so tempo changes (`Fxx`) become SEQ tempo events and speed changes only affect row length.
- Pitch effects (slides, portamento, vibrato, arpeggio) are written as pitch bend events. The tone's bend range is ±15 semitones, so slides larger than that are clamped.

### Looping

- If the pattern order jumps back to a position that was already played (`Bxx`, or a song that repeats), that point becomes the SEQ loop. Tempo, channel volumes and pans are restored at the loop start. `E6x` pattern loops are expanded, and their counters are part of the position, so they don't confuse loop detection.
- `--loop` loops the whole song when it simply ends.
- `F00` stops the song, as in ProTracker.

The SPU can only loop over whole 28-sample ADPCM blocks, while module loops can have any length. To keep the pitch right:

- If the loop length isn't a multiple of 28, the loop is unrolled until it is (up to lcm(loop, 28) samples). This is exact, but can make short single-cycle waveforms take more space in the bank than in the module.
- If unrolling would be too long (more than 16384 samples), the sample is stretched very slightly so the loop becomes a multiple of 28, and the tone's pitch is corrected to compensate.

The first block of a loop is encoded without prediction, so every pass of the loop decodes identically.

### Supported effects

| Effect | Notes |
|---|---|
| `0xy` | Arpeggio, via pitch bend |
| `1xx`, `2xx` | Pitch slide up/down (no parameter memory, as in ProTracker) |
| `3xx` | Tone portamento (speed is remembered) |
| `4xy` | Vibrato (speed/depth are remembered, ProTracker depth) |
| `5xy`, `6xy` | Tone portamento / vibrato + volume slide |
| `8xx` | Panning (not standard ProTracker, but widely used) |
| `Axy` | Volume slide |
| `Bxx`, `Dxx` | Position jump, pattern break |
| `Cxx` | Set volume |
| `Fxx` | Speed (1–31) and tempo (32–255); `F00` stops the song |
| `E1x`, `E2x` | Fine pitch slide |
| `E6x` | Pattern loop |
| `E8x` | Panning |
| `E9x` | Retrigger |
| `EAx`, `EBx` | Fine volume slide |
| `ECx` | Note cut (also sets the volume to 0) |
| `EDx` | Note delay |
| `EEx` | Pattern delay (per-tick effects are not repeated) |

**Not supported:** `7xy` tremolo, `9xy` sample offset, and the `E0x`, `E3x`, `E4x`, `E5x`, `E7x`, `EFx` effects. They are ignored, and a warning with the number of affected rows is printed for each.

### Limits and notes

- Input is limited to standard 31-sample, 4-channel modules.
- The whole bank has to fit into SPU memory (512 KB, shared with everything else your program loads), so check the size of the `.vb`/`.vab`. Sample-heavy modules and unrolled loops are the usual reason it grows.
- Truncated modules are accepted: missing sample data is simply shorter.
- Volume is linear MOD volume (0-64) mapped to MIDI volume (0-127).

## Building a VAB from SoundFont

`bank` command reads a program map and converts the requested SoundFont 2 presets to a PlayStation VAB (`.vh` + `.vb`, or a single `.vab` with `--vab` option). It resamples and encodes samples to ADPCM, preserves loops, converts volume envelopes to SPU ADSR settings, and maps pan, volume, key, and velocity ranges to VAB tones.

```
seqtool bank soundfont.sf2 song.map
```

SoundFont 3 is not supported. If the samples exceed the configured SPU memory budget, the tool reduces sample rate and length to fit or reports an error.

## Program map format

```text
<program> melodic <bank> <GM program> <lowest key> <highest key>
<program> drums <kit> <key> <key> ...
```
