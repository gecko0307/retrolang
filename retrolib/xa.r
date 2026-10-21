/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/

/*
 * CD-XA streaming on top of cd.r.
 *
 * XA audio is decoded by the CD controller and mixed into the SPU through the
 * same CD input as CDDA.
 *
 * Usage:
 *   spuInit();
 *   cdInit();
 *   
 *   struct DirEntry xaStream;
 *   cd_firstfile("cdrom:\\MUSIC\\FILE0.XA;1", &xaStream);
 *   cdPlayXALoop(xaStream.lba, 0, 0); // play XA stream from file 0, channel 0
 *   ...
 *   every frame: cdXaUpdate(); // use instead of cdUpdate()
 *   ...
 *   cdXaStop(); // before using cdPlay() for CDDA again
 */

#if import

#import "cd.r"

int cdXaActive;
int cdXaFramesLeft;
int cdXaFramesTotal;
int cdXaLba;
int cdXaFile;
int cdXaChannel;

int cdBcd(int v)
{
    return ((v / 10) << 4) | (v % 10);
}

/// Pushes one parameter into the parameter FIFO. The last parameter of a
/// command goes through cdCommand(), which only takes a single one.
void cdPushParam(int v)
{
    int timeout = 0;
    while ((*CD_INDEX & 0x80) && timeout < 50000)
    {
        timeout++;
    }
    *CD_INDEX = 0;
    *CD_REG2 = v;
    for (int i = 0; i < 50; i++) {}
}

/// Setloc (0x02) from an absolute LBA of the file start (as given by mkpsxiso)
void cdSetLoc(int lba)
{
    int a = lba + 150; // the 2 second pregap
    int mm = a / 4500;
    int ss = (a / 75) % 60;
    int ff = a % 75;
    cdPushParam(cdBcd(mm));
    cdPushParam(cdBcd(ss));
    cdCommand(0x02, cdBcd(ff), 1);
}

/// Mode 0xC8 = double speed + XA-ADPCM to SPU + XA filter.
/// Then Setfilter(file, channel), Setloc, ReadS.
void cdXaStart()
{
    cdCommand(0x0E, 0xC8, 1);
    cdPushParam(cdXaFile);
    cdCommand(0x0D, cdXaChannel, 1);
    cdSetLoc(cdXaLba);
    cdCommand(0x1B, 0, 0); // ReadS
    cdXaFramesLeft = cdXaFramesTotal;
}

/// Plays an XA stream once (no looping)
void cdPlayXA(int lba, int file, int channel)
{
    cdLoopTrack = 0;
    cdPaused = 0;
    cdXaLba = lba;
    cdXaFile = file;
    cdXaChannel = channel;
    cdXaFramesTotal = 0;
    cdXaActive = 1;
    cdXaStart();
}

/**
 * Plays a XA stream and restarts it after `frames` frames.
 * frames = totalSectors * fps / 150, where totalSectors is the size of the
 * whole interleaved XA file in 2336/2352-byte sectors (double speed = 150/s)
 * and fps is 60 (NTSC) or 50 (PAL). Needs cdXaUpdate() once per frame.
 */
void cdPlayXALoop(int lba, int file, int channel, int frames)
{
    cdPlayXA(lba, file, channel);
    cdXaFramesTotal = frames;
    cdXaFramesLeft = frames;
}

/// Stops XA and restores single speed + CDDA mode (what cdInit() sets)
void cdXaStop()
{
    cdXaActive = 0;
    cdXaFramesTotal = 0;
    cdCommand(0x09, 0, 0);    // Pause
    cdCommand(0x0E, 0x03, 1); // back to 1x, CDDA + autopause
}

/// Call once per frame instead of cdUpdate()
void cdXaUpdate()
{
    cdUpdate(); // keeps draining CD interrupts

    if (cdXaActive && cdXaFramesTotal > 0)
    {
        cdXaFramesLeft = cdXaFramesLeft - 1;
        if (cdXaFramesLeft <= 0)
        {
            cdXaStart();
        }
    }
}

#endif
