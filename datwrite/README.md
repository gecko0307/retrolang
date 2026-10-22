# DATWrite

DATWrite generates a PlayStation license file (DAT) for patching the CD system area. It can be used with utilities such as mkpsxiso.

Output: 12 sectors x 2336 bytes = 28032 bytes (CD-ROM XA Mode 2 Form 1 sectors without the 12-byte sync and 4-byte header). Sectors 0-3 are zero-filled. Sector 4 contains null-terminated license text. Sectors 5-11 contain a TMD model shown by the BIOS on the boot splash screen.

## Usage

```
datwrite --output=license.dat --tmd=logo.tmd --region=e

datwrite --output=license.dat --tmd=logo.tmd --license-text="Your custom license text"

datwrite --verify license.dat
```

## TMD Logo

A custom logo model (displayed on the boot splash screen) can be exported from Blender 4.5 using the provided addon `io_export_psx_tmd.py`. Requirements are the following:

- The camera at the splash screen looks down the Y-axis in Blender, X-axis points right, and the Z-axis points up;
- Maximum triangle count is ~500;
- The exporter uses material's viewport display color instead of the base color from nodes;
- Textures are not allowed;
- TMD size must be under 14 KiB.

Example logo is provided with the *.blend source file.
