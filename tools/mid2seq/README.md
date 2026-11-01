# MID2SEQ

Converts MIDI files (format 0 or 1) and, experimentally, ProTracker MOD files to PlayStation SEQ files.

For MOD input, MID2SEQ writes the SEQ and a matching VAB sound bank from the samples embedded in the module:

```
mid2seq song.mod                 # song.seq + song.vh + song.vb
mid2seq --vab song.mod           # song.seq + song.vab
```

The MOD bank uses one program per sample. Sample loops and tuning are preserved; sample-header volume and channel volume effects are applied through SEQ channel volume. Supported effects include arpeggio, pitch slides, tone portamento, vibrato, volume slides, pattern loops/delays, note cut/delay, retrigger, pan, order jump/break, channel volume, and tempo/speed changes. Unsupported effects, including sample offset, tremolo, and ProTracker `EFx` funk/invert-loop, are reported as warnings rather than silently ignored. Since those effects cannot be represented directly by static SEQ/VAB data, output may differ from the source module. Supported signatures are `M.K.`, `M!K!`, `FLT4` and `4CHN`; input is limited to standard 31-sample, 4-channel modules.

Use `--bank-out <name>` to set the MOD bank's output base name; by default it matches the SEQ filename without its extension.

A MIDI file only says which General MIDI instruments to play, so a SEQ needs a sound bank (VAB). MID2SEQ writes a *program map* next to the SEQ: a text file that lists the instruments the song uses and the VAB program number it assigned to each. [SF2TOVAB](../sf2tovab) reads that map and builds a matching VAB from a SoundFont.

```
mid2seq song.mid                 # song.seq + song.map
sf2tovab soundfont.sf2 song.map  # song.vh + song.vb
```

If you already have a bank, pass its map with `--map-in` and MID2SEQ will use the program numbers from it (notes of instruments missing from the map are dropped).

Conversion notes:

- Multi-track files are merged into one stream; tempo, controllers (volume, pan, expression, sustain, all notes off), program changes and pitch bend are kept, other events are dropped.
- Channel 10 (or `--drum-channel`) is treated as drums. A drum kit with more than 16 keys is split into several programs of up to `--tones` keys; program changes are inserted before the drum notes as needed.
- Loops: MIDI markers `loopStart` / `loopEnd` or controller 111 become SEQ loop controllers (CC99 = 20 / 30, CC6 = 127 for forever). `--loop` loops the whole song.
- `--ppqn` rescales the time resolution.

Program map format:

```
<prog> melodic <bank> <gm> <keyLo> <keyHi>
<prog> drums <kit> <key> <key> ...
```
