# SEQ Tool

SEQ Tool is a multi-purpose sequencer music converter that can do the following:

- Convert a Standard MIDI file (format 0 or 1) to PlayStation SEQ file
- Convert a ProTracker MOD file to PlayStation SEQ file
- Generate a VAB instrument bank from a SoundFont 2 file.

## Usage

```
seqtool <command> [options] <input>
```

Available commands:

- `convert` - convert a song file to SEQ
- `bank` - generate an instrument bank.

Available options for the `convert` command:

- `-o/--output <file>` - specify output SEQ file name (default is input name with a ".seq" extension)
- `--bank-out <name>` - specify MOD VAB bank base name (default is output name without extension)
- `--vab` - write the MOD bank as a single .vab file instead of .vh + .vb
- `--map-out <file>` - for MIDI input: write a program map for seqtool bank (default filename is output name with a ".map" extension)
- `--map-in <file>` - for MIDI input: use an existing program map (e.g. of a ready sound bank) instead of generating one; notes without an instrument are dropped
- `--loop` - loop the whole song if no loop markers/order loop exists
- `--drum-channel <n>` - MIDI channel (1..16) that carries drums, 0 for none (default 10)
- `--ppqn <n>` - rescale the time resolution (ticks per quarter note)
- `--tones <n>` - maximum drum keys per program, 1..16 (default 16).

Available options for the `bank` command:

- `-o/--output <file>` - output base name (default is the input map name)
- `--vab` - write a single .vab file instead of .vh + .vb
- `--rate <hz>` - highest sample rate to keep (default 22050)
- `--budget <bytes>` - SPU RAM available for samples (default 400000); the rate and sample length are reduced to fit
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

Use `seqtool convert --map-in <file>` to use an existing program map instead of generating one. Notes for instruments missing from that map are dropped.

## Converting MOD to SEQ

For MOD files, the VAB is built from samples embedded in the module, so a separate bank generation step is not needed. The MOD bank uses one program per sample; sample loops and tuning are preserved, and sample-header/channel volume is applied through SEQ channel volume. Common effects are converted, while unsupported effects are reported as warnings and can cause output to differ from the source module. Input is limited to standard 31-sample, 4-channel modules.

```
seqtool convert song.mod
```

## Building a VAB from SoundFont

`bank` command reads a program map and converts the requested SoundFont 2 presets to a PlayStation VAB (`.vh` + `.vb`, or a single `.vab` with `--vab` option). It resamples and encodes samples to ADPCM, preserves loops, converts volume envelopes to SPU ADSR settings, and maps pan, volume, key, and velocity ranges to VAB tones.

```
seqtool bank soundfont.sf2 song.map
```

SoundFont 3 is not supported. If the samples exceed the configured SPU RAM budget, the tool reduces sample rate and length to fit or reports an error.

## Program map format

```text
<program> melodic <bank> <GM program> <lowest key> <highest key>
<program> drums <kit> <key> <key> ...
```
