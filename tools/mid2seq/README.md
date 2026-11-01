# MID2SEQ

Converts a MIDI File (format 0 or 1) to a PlayStation SEQ file.

A MIDI file only says which General MIDI instruments to play, so a SEQ needs a sound bank (VAB). MID2SEQ writes a *program map* next to the SEQ: a text file that lists the instruments the song uses and the VAB program number it assigned to each. [SF2TOVAB](../sf2tovab) reads that map and builds a matching VAB from a SoundFont.

```
mid2seq song.mid                 # song.seq + song.map
sf2tovab soundfont.sf2 song.map  # song.vh + song.vb
```

If you already have a bank, pass its map with `--map-in` and MID2SEQ will use the program numbers from it (notes of instruments missing from the map are dropped).

## Conversion

- Multi-track files are merged into one stream; tempo, controllers (volume, pan, expression, sustain, all notes off), program changes and pitch bend are kept, other events are dropped.
- Channel 10 (or `--drum-channel`) is treated as drums. A drum kit with more than 16 keys is split into several programs of up to `--tones` keys; program changes are inserted before the drum notes as needed.
- Loops: MIDI markers `loopStart` / `loopEnd` or controller 111 become SEQ loop controllers (CC99 = 20 / 30, CC6 = 127 for forever). `--loop` loops the whole song.
- `--ppqn` rescales the time resolution.

## Program map format

```
<prog> melodic <bank> <gm> <keyLo> <keyHi>
<prog> drums <kit> <key> <key> ...
```
