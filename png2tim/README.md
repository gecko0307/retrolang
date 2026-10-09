#png2tim

A simple PNG to TIM converter.

Usage:

```
png2tim --bpp=8 --alpha=128 --ix=320 --iy=0 --cx=320 --cy=256 -o=texture.tim texture.png
```

Options:
- `--bpp` is bits per pixel, possible values are 4, 8 and 16. Default is 8
- `--alpha` is transparency threshold. Alpha values lower than this will be treated as fully transparent in the TIM. Default is 128
- `--ix`, `--iy` - image position in VRAM. Default is 0, 0
- `--cx`, `--cy` - CLUT position in VRAM. Default is 0, 480. `--cx` must be a multiple of 16
- `-o` is the output TIM file name. Default the input filename + ".tim" extension.
