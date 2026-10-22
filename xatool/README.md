# XA Tool

XA stream encoder and interleaver. Combines 2336-byte sector XA files into one playable file.

Usage:

```
psxavenc -t xa -f 37800 -b 4 -c 2 channel0.mp3 channel0.xa
psxavenc -t xa -f 37800 -b 4 -c 2 channel1.mp3 channel1.xa
xatool -o MUSIC.XA --file 1 channel0.xa channel1.xa
```

Each input becomes one XA channel (input 1 -> channel 0, input 2 -> channel 1, etc). File and channel numbers in the subheaders are overwritten, so the values psxavenc wrote don't matter. Slots without a stream get empty padding sectors (audio, Form 2, tagged with channel 31). The last real sector of each stream gets the EOF/EOR flags.

Interleave span (sectors per cycle):

- 8  = 37800 Hz stereo 4-bit (default)
- 16 = 18900 Hz stereo, or 37800 Hz mono
- 32 = 18900 Hz mono

XA Tool can transcode PCM WAV/MP3/FLAC/OGG files to XA format by itself. Simply use audio files as inputs instead of *.xa:

```
xatool -o MUSIC.XA --file 1 channel0.mp3 channel1.mp3
```
