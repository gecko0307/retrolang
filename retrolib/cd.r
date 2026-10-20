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
 * CD audio driver.
 */

#if import

#import "irq.r"

uchar* CD_INDEX = 0x1F801800; // read: status, write: register index (0-3)
uchar* CD_REG1  = 0x1F801801; // idx0 write: command | read: response FIFO
uchar* CD_REG2  = 0x1F801802; // idx0 write: parameter | idx1 write: IRQ enable
uchar* CD_REG3  = 0x1F801803; // idx1 read: IRQ flags, write: IRQ ack

// Internal state
int cdLastStat;
int cdLoopTrack;
int cdPaused;

/// Pending interrupt type: 0 = none, 1..5 = INT1..INT5
int cdIntPending()
{
    *CD_INDEX = 1;
    return *CD_REG3 & 7;
}

/// Reads the whole response FIFO, keeps the first byte (stat) in cdLastStat
void cdReadResponse()
{
    int first = 1;
    while (*CD_INDEX & 0x20) // response FIFO not empty
    {
        int b = *CD_REG1;
        if (first)
        {
            cdLastStat = b;
            first = 0;
        }
    }
}

///
void cdAck()
{
    *CD_INDEX = 1;
    int currentIrq = *CD_REG3 & 7;
    if (currentIrq > 0)
    {
        *CD_REG3 = currentIrq;
    }
    *I_STAT = ~4; // clear the CDROM bit in I_STAT (0 = clear)
}

/// Throws away any interrupts that are waiting
void cdDrain()
{
    int guard = 0;
    while (cdIntPending() && guard < 16)
    {
        cdReadResponse();
        cdAck();
        for (int i = 0; i < 50; i++) {} 
        guard++;
    }
}

/**
 * Sends one command (with an optional single parameter) and waits for its
 * first response. Returns the stat byte, or -1 on error or timeout.
 * Other interrupts that arrive in the meantime (INT1/2/4) are discarded.
 */
int cdCommand(int cmd, int param, int hasParam)
{
    int timeout = 0;
    while ((*CD_INDEX & 0x80) && timeout < 50000)
    {
        // wait while controller is busy
        for (int i = 0; i < 10; i++) {} 
        timeout++;
    }

    *CD_INDEX = 0;
    if (hasParam)
    {
        *CD_REG2 = param;
        for (int i = 0; i < 50; i++) {}
    }
    *CD_REG1 = cmd;

    timeout = 0;
    while (timeout < 250000)
    {
        for (int i = 0; i < 20; i++) {} 
        
        int n = cdIntPending();
        if (n > 0)
        {
            cdReadResponse();
            cdAck();
            
            if (n == 3) return cdLastStat; // INT3: command acknowledged
            if (n == 5) return -1;         // INT5: error
        }
        timeout++;
    }

    return -1; 
}

/// 0..127
void cdSetVolume(int vol)
{
    if (vol < 0) vol = 0;
    if (vol > 127) vol = 127;
    int lvl = (vol * 0x80) / 127;

    *CD_INDEX = 2;
    *CD_REG2 = lvl;
    *CD_REG3 = 0;
    *CD_INDEX = 3;
    *CD_REG1 = lvl;
    *CD_REG2 = 0;
    *CD_REG3 = 0x20;
}

///
void cdInit()
{
    *CD_INDEX = 1;
    *CD_REG2 = 0x1F; 
    cdDrain();

    cdCommand(0x0C, 0, 0); 
    for (int i = 0; i < 10000; i++) {}

    cdCommand(0x0E, 0x03, 1); 
    for (int i = 0; i < 10000; i++) {}

    cdSetVolume(127);
    cdLoopTrack = 0;
    cdPaused = 0;
}

/// Starts a track from its beginning (no looping bookkeeping)
void cdStartTrack(int track)
{
    int bcd = ((track / 10) << 4) | (track - (track / 10) * 10);
    cdCommand(0x03, bcd, 1); 
    cdPaused = 0;
}

/// Plays a track once. Track 1 is the data track; music starts at track 2.
void cdPlay(int track)
{
    cdLoopTrack = 0;
    cdStartTrack(track);
}

/// Plays a track and restarts it whenever it ends (needs cdUpdate() each frame)
void cdPlayLoop(int track)
{
    cdLoopTrack = track;
    cdStartTrack(track);
}

/// Pause keeps the disc spinning, so cdResume() continues almost instantly
void cdPause()
{
    cdPaused = 1;
    cdCommand(0x09, 0, 0); 
}

///
void cdResume()
{
    cdPaused = 0;
    cdCommand(0x03, 0, 0); 
}

// Stops playback and spins the disc down
void cdStop()
{
    cdLoopTrack = 0;
    cdPaused = 0;
    cdCommand(0x08, 0, 0); 
}

/**
 * Call once per frame. Restarts the looped track when it has ended.
 */
void cdUpdate()
{
    int irqType = cdIntPending();
    if (irqType > 0)
    {
        cdReadResponse();
        cdAck();

        if (irqType == 4) 
        {
            if (cdLoopTrack > 0 && !cdPaused)
            {
                cdStartTrack(cdLoopTrack);
            }
        }
    }
}

#endif
