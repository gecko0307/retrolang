# XA Files

XA is a streamed audio format that allows games to play music directly from the CD with minimal CPU overhead. It is conceptually similar to CD-DA, except that the seek time is much smaller. Moreover, it has two major advantages:

- Because of the ADPCM compression, XA files take up less space on disc;
- XA-ADPCM is decompressed by the CD-ROM controller, and sent directly to the sound mixer, without needing to store the data in SPU RAM, nor needing to occupy a SPU voice.

XA supports only two sample rates - 37800 and 18900 Hz. XA nibbles are arranged in different order comparing to SPU ADPCM, and XA uses 2x28 nibbles per block (instead of 2x14).

A distinct feature of XA format that is confusing for beginners is interleaving. It is a method of mixing multiple audio streams (or combining audio with STR video data) across alternating CD-ROM sectors. This allows the controller to stream continuous audio or switch tracks smoothly without heavy CPU overhead or constant seeking.
