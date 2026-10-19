# WAV2VAG

An utility for converting integer PCM WAV files to PlayStation ADPCM VAG files and decoding VAG files back to WAV. Build it with `dmd wav2vag.d -of=wav2vag.exe`; run `wav2vag.exe --help` for options.

## VAG Format

VAG is an audio compression format developed by Sony. It served as the standard format for storing music, sound effects, and voiceovers in games for the PlayStation 1 (PSX), PlayStation 2 (PS2), and PlayStation Portable (PSP) consoles. VAG utilizes 4-bit PS-ADPCM (Adaptive Differential Pulse Code Modulation) compression. The compression ratio is approximately 3.5:1 compared to uncompressed 16-bit PCM. Audio data is organized into 16-byte blocks. Each block contains 2 bytes of control information (decoding coefficients and looping parameters) and 14 bytes of actual audio data, which decodes into 28 audio samples.
