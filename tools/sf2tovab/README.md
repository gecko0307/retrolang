# SF2TOVAB

Builds a PlayStation VAB sound bank (`.vh` + `.vb`, or a single `.vab`) from a SoundFont 2 file. Uncompressed SoundFont 2 only (SF3 is not supported).

```
sf2tovab [options] soundfont.sf2 song.map
sf2tovab --list soundfont.sf2
```

The program map comes from [MID2SEQ](../mid2seq). For every program in it, SF2TOVAB picks the SoundFont preset (General MIDI program, bank 128 for drums), collects the zones that are needed for the key ranges the song uses, and converts them to VAB tones.

## What is converted

- **Samples**: resampled and encoded to PS-ADPCM, loops preserved. Loops are unrolled or slightly stretched so that they fall on 28-sample block boundaries.
- **Pitch**: the root key, fine and coarse tuning are baked into the sample rate, so every tone has `shift = 0` and sounds at the right pitch at its root key.
- **Envelopes**: the SoundFont volume envelope is converted to the SPU ADSR registers.
- **Pan, volume, key and velocity ranges** go to the tone fields. At most 16 tones fit in a program, so neighbouring zones are merged if there are more (`--layers` controls how many velocity layers are kept per key).
- **Budget**: SPU RAM is 512 KB. If the samples do not fit into `--budget` bytes, the sample rate and length are reduced step by step; if they still do not fit, the tool stops with an error telling you to use fewer instruments or a bigger budget.
