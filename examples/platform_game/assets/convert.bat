"../../../png2tim/png2tim.exe" --bpp=8 --alpha=128 --ix=320 --iy=0 --cx=320 --cy=256 -o=tiles.tim tiles.png
"../../../png2tim/png2tim.exe" --bpp=8 --alpha=128 --ix=448 --iy=0 --cx=320 --cy=257 -o=character.tim character.png
"../../../png2tim/png2tim.exe" --bpp=4 --alpha=128 --ix=512 --iy=0 --cx=320 --cy=258 -o=font.tim font.png
"../../../wav2vag/wav2vag.exe" --rate 22050 -o jump.vag jump.wav
"../../../wav2vag/wav2vag.exe" --rate 22050 -o pickup.vag pickup.wav
