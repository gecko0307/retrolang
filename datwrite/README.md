# DATWrite

DATWrite generates a PlayStation license file (DAT) for patching the CD system area. It can be used with utilities such as mkpsxiso.

Output: 12 sectors x 2336 bytes = 28032 bytes (CD-ROM XA Mode 2 Form 1 sectors without the 12-byte sync and 4-byte header). Sectors 0-3 are zero-filled. Sector 4 contains null-terminated license text. Sectors 5-11 contain a TMD model shown by the BIOS on the boot splash screen

## Usage

```
datwrite -o license.dat -t logo.tmd -r e

datwrite -o license.dat -t logo.tmd -l "Your custom license text"

datwrite --verify license.dat
```
