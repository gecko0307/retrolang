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

/**
 * STR video streaming.
 *
 * Reads a STR movie (MDEC bitstream v2, interleaved with XA audio) from the
 * CD-ROM, assembles the frames from the video sectors, decodes them (vlc.r)
 * and sends them through the MDEC to VRAM (mdec.r).
 *
 * Usage:
 *     cdInit();
 *     gpuInit(&settings);
 *     mdecInit();
 *     strStart(movieLba);
 *     while (playing)
 *     {
 *         strUpdate(0, 0, MDEC_DEPTH_15BIT); // decodes a frame if one is ready
 *         ... wait for vblank, do other work, but call strPoll() often ...
 *     }
 *     strStop();
 *
 * The CD-ROM is serviced by polling. At double speed a sector arrives every
 * 6.7 ms and the controller keeps only one of them, so strPoll() must be called
 * at least that often or sectors are lost. strUpdate() does it by itself while
 * it is decoding; the application has to do it in the rest of its main loop.
 * Do not use cdUpdate() (cd.r) while streaming, both consume the same interrupts.
 *
 * Frames are queued in two demux buffers. If the application is too slow, the
 * oldest complete frame is dropped (see strDropped).
 */

// CD-ROM commands
#define STR_CD_SETLOC       0x02
#define STR_CD_PAUSE        0x09
#define STR_CD_SETFILTER    0x0d
#define STR_CD_SETMODE      0x0e
#define STR_CD_READS        0x1b

// CD-ROM mode bits
#define STR_MODE_FILTER     0x08 // only play the XA channel chosen by strSetChannel
#define STR_MODE_XA         0x40 // play XA-ADPCM audio, don't pass it to the data FIFO
#define STR_MODE_SPEED      0x80 // double speed

// DMA channel 3 (CD-ROM)
#define STR_DMA3_ENABLE     0x00008000
#define STR_DMA3_START      0x11000000 // CD-ROM -> RAM, sync mode 0, start + trigger

// Sector as it comes from the controller in the 2048-byte mode:
// 32 bytes of video header followed by 2016 bytes of frame data.
#define STR_SECTOR_WORDS    512
#define STR_CHUNK_WORDS     504
#define STR_CHUNK_BYTES     2016
#define STR_MAGIC           0x0160
#define STR_MAX_CHUNKS      31

#define STR_DEMUX_WORDS     16384
#define STR_DEMUX_BYTES     65536
#define STR_MDEC_WORDS      32768
#define STR_MDEC_BYTES      131072

#define STR_WAIT_LIMIT      200000

// This many delivered sectors in a row that are not video mean the movie is over
#define STR_END_SECTORS     16

/*
 * Buffers at fixed RAM addresses (see the other regions in gpu.r and mdec.r):
 *   0x801AF000  one sector (2 KB)
 *   0x801B0000  MDEC data of the frame that is being decoded (128 KB)
 *   0x801D0000  demux buffer 0 (64 KB)
 *   0x801E0000  demux buffer 1 (64 KB)
 */
#define STR_SECTOR_ADDR     0x801AF000
#define STR_MDEC_ADDR       0x801B0000
#define STR_DEMUX0_ADDR     0x801D0000
#define STR_DEMUX1_ADDR     0x801E0000

macro StrRegionSector  = (STR_SECTOR_ADDR, 2048);
macro StrRegionMdec    = (STR_MDEC_ADDR,   STR_MDEC_BYTES);
macro StrRegionDemux0  = (STR_DEMUX0_ADDR, STR_DEMUX_BYTES);
macro StrRegionDemux1  = (STR_DEMUX1_ADDR, STR_DEMUX_BYTES);

#if import

#import "core.r"
#import "bios.r"
#import "dma.r"
#import "cd.r"
#import "vlc.r"
#import "mdec.r"

uint strSector[STR_SECTOR_WORDS]  @StrRegionSector;
uint strMdecData[STR_MDEC_WORDS]  @StrRegionMdec;
uint strDemux0[STR_DEMUX_WORDS]   @StrRegionDemux0;
uint strDemux1[STR_DEMUX_WORDS]   @StrRegionDemux1;

// Public state
int strActive = 0;        // streaming is on
int strEof = 0;           // the end of the movie was detected (see strFinished)
int strTail = 0;          // non-video sectors since the last video sector
int strMaskSaved = 0;     // CD-ROM bit of the CPU interrupt mask before strStart
int strErrors = 0;        // CD-ROM errors, bad sectors, corrupt frames
int strTrace = 0;         // 1 = log the first frames to the TTY with printf, set to 0 to silence
int strDropped = 0;       // frames that were lost
int strFramesReceived = 0;
int strFramesDecoded = 0;
int strWidth = 0;         // size of the last decoded frame
int strHeight = 0;

// Diagnostics
int strStartStep = 0;     // strStart: 0 = ok, otherwise the step that failed
                          // (1 setfilter, 2 setmode, 3 setloc, 4 reads)
int strPolls = 0;         // number of strPoll calls made while streaming
int strHeartbeats = 0;    // trace lines printed by strPoll so far
int strVideoSectors = 0;  // video sectors accepted by the demuxer
int strVlcErrors = 0;     // frames that failed to decode in the VLC stage
int strInts[8];           // how many INT1..INT5 were seen by strPoll

// CPU interrupt mask register
int* strIMask = 0x1F801074;

// Frame pacing (see strSetPacing)
int* strClock = 0;        // application's vblank counter
int strClockHz = 50;      // vblanks per second
int strFps = 15;          // frame rate of the movie
int strPaced = 0;         // 1 = frames are shown at their time, not as soon as they are decoded
int strPaceStarted = 0;   // the first frame has been taken
int strPaceBase = 0;      // clock value when the first frame was taken
int strPaceFirst = 0;     // number of the first frame
int strBufFrame[2];       // movie frame number of each demux buffer
int strWaits = 0;         // diagnostics: times a frame was held back until its time
int strBlocked = 0;       // diagnostics: times the CD-ROM was left alone because of back-pressure
int strLastFrame = 0;     // movie frame number of the frame taken for decoding last

// CD-ROM settings
int strFilterOn = 0;
int strFilterFile = 0;
int strFilterChannel = 0;

// Frame queue. Buffer states: 0 free, 1 being assembled, 2 complete, 3 being decoded
int  strBufState[2];
int  strBufBytes[2];
int  strBufWidth[2];
int  strBufHeight[2];
int  strReady = -1;       // complete frame waiting for strUpdate, or -1

// Frame that is being assembled
int  strAsmBuf = -1;
uint strAsmFrame = 0;
uint strAsmCount = 0;     // chunks in the frame
uint strAsmMask = 0;      // chunks that have been received
uint strAsmGot = 0;
uint strIgnoreFrame = 0;  // frame number whose sectors are skipped (done or dropped)

// Returns the address of a demux buffer
uint* strDemuxBuffer(int index)
{
    uint* p = STR_DEMUX0_ADDR;
    if (index != 0)
        p = STR_DEMUX1_ADDR;
    return p;
}

int strBcd(int v)
{
    int tens = v / 10;
    return (tens << 4) | (v - tens * 10);
}

// Waits until the controller can accept a command
void strCdReady()
{
    int guard = 0;
    while ((*CD_INDEX & 0x80) != 0 && guard < 50000)
        guard++;
}

// Pushes a parameter into the controller's parameter FIFO
void strCdParam(int v)
{
    *CD_INDEX = 0;
    *CD_REG2 = v;
}

// Setloc, the position is a logical block address (sector 0 of the disc = 0)
int strCdSetloc(int lba)
{
    int f = lba + 150;
    int m = f / 4500;
    int s = (f - m * 4500) / 75;
    int fr = f - m * 4500 - s * 75;

    strCdReady();
    strCdParam(strBcd(m));
    strCdParam(strBcd(s));
    strCdParam(strBcd(fr));
    return cdCommand(STR_CD_SETLOC, 0, 0);
}

/**
 * Plays only one XA audio channel of the movie. Call before strStart.
 * Without it, all XA audio sectors are played.
 */
void strSetChannel(int file, int channel)
{
    strFilterOn = 1;
    strFilterFile = file;
    strFilterChannel = channel;
}

/**
 * Makes the player show the frames at their time instead of as soon as they
 * are decoded. Needed where the CD-ROM delivers the data faster than a real drive.
 *
 * clock points to a counter that the application increments once per vblank
 * (from an interrupt handler), hz is the vblank rate (50 for PAL, 60 for NTSC),
 * fps is the frame rate of the movie. Call before strStart.
 *
 * While a decoded frame is waiting for its time, the CD-ROM is not serviced,
 * so the drive can't overwrite it. On a real console the drive is real time
 * already: leave the pacing off there.
 */
void strSetPacing(int* clock, int hz, int fps)
{
    if (clock == 0 || hz <= 0 || fps <= 0)
    {
        strPaced = 0;
        return;
    }
    strClock = clock;
    strClockHz = hz;
    strFps = fps;
    strPaced = 1;
}

// Turns the pacing off
void strClearPacing()
{
    strPaced = 0;
}

// Is it time to show the complete frame in the given buffer?
int strFrameDue(int b)
{
    int idx;
    int elapsed;

    if (strPaced == 0 || strPaceStarted == 0)
        return 1;

    // due when elapsed / hz >= idx / fps
    idx = strBufFrame[b] - strPaceFirst;
    elapsed = *strClock - strPaceBase;
    if (elapsed * strFps >= idx * strClockHz)
        return 1;
    return 0;
}

// Picks a buffer for a new frame: a free one, or the one with a stale complete frame
int strPickBuffer()
{
    if (strBufState[0] == 0) return 0;
    if (strBufState[1] == 0) return 1;
    if (strBufState[0] == 2)
    {
        strDropped++;
        strReady = -1;
        return 0;
    }
    if (strBufState[1] == 2)
    {
        strDropped++;
        strReady = -1;
        return 1;
    }
    return -1;
}

// Takes the frame data of the sector in strSector and puts it into a demux buffer.
void strDemuxSector()
{
    uint* s = STR_SECTOR_ADDR;
    uint* src;
    uint* dst;
    uint chunk;
    uint count;
    uint frame;
    uint used;
    uint bit;
    int b;
    int i;

    if ((s[0] & 0xffff) != STR_MAGIC)
    {
        // Not a video sector. After the last frame the drive goes on reading
        // whatever follows the file on the disc.
        strTail++;
        if (strTail >= STR_END_SECTORS && strFramesReceived > 0)
            strEof = 1;
        return;
    }
    strTail = 0;
    strVideoSectors++;

    chunk = s[1] & 0xffff;
    count = s[1] >> 16;
    frame = s[2];
    used = s[3];

    if (count == 0 || count > STR_MAX_CHUNKS || chunk >= count)
    {
        strErrors++;
        return;
    }
    if (used < 12 || used > count * STR_CHUNK_BYTES)
    {
        strErrors++;
        return;
    }
    if (frame == strIgnoreFrame)
        return;

    if (strTrace != 0 && strFramesReceived < 2)
        printf("str: sector chunk=%d count=%d\n", chunk, count);

    if (strAsmBuf < 0 || frame != strAsmFrame)
    {
        // The first sector of a new frame. A frame that is still incomplete is lost.
        if (strAsmBuf >= 0)
        {
            strBufState[strAsmBuf] = 0;
            strAsmBuf = -1;
            strDropped++;
        }

        b = strPickBuffer();
        if (b < 0)
        {
            strIgnoreFrame = frame;
            strDropped++;
            return;
        }

        strBufState[b] = 1;
        strBufWidth[b] = s[4] & 0xffff;
        strBufHeight[b] = s[4] >> 16;
        strAsmBuf = b;
        strAsmFrame = frame;
        strAsmCount = count;
        strAsmMask = 0;
        strAsmGot = 0;
    }

    if (count != strAsmCount)
    {
        strErrors++;
        return;
    }

    bit = 1 << chunk;
    if ((strAsmMask & bit) != 0)
        return; // duplicate

    dst = strDemuxBuffer(strAsmBuf) + chunk * STR_CHUNK_WORDS;
    src = s + 8;
    for (i = 0; i < STR_CHUNK_WORDS; i++)
        dst[i] = src[i];

    strAsmMask = strAsmMask | bit;
    strAsmGot++;

    if (strAsmGot == strAsmCount)
    {
        b = strAsmBuf;
        strBufBytes[b] = used;
        strBufFrame[b] = frame;
        strBufState[b] = 2;
        if (strReady >= 0 && strReady != b)
        {
            strBufState[strReady] = 0;
            strDropped++;
        }
        strReady = b;
        strAsmBuf = -1;
        strIgnoreFrame = frame;
        if (strTrace != 0 && strFramesReceived < 8)
            printf("str: frame %d complete, %d bytes\n", frame, used);
        strFramesReceived++;
    }
}

// Moves the sector that the controller has just read into strSector with DMA 3 and demuxes it.
void strSectorReady()
{
    int guard = 0;

    // Ask the controller to load its data FIFO and wait until it has the data
    *CD_INDEX = 0;
    *CD_REG3 = 0;
    *CD_REG3 = 0x80;
    while ((*CD_INDEX & 0x40) == 0 && guard < STR_WAIT_LIMIT)
        guard++;

    if (guard >= STR_WAIT_LIMIT)
    {
        *CD_REG3 = 0;
        strErrors++;
        if (strTrace != 0)
            printf("str: no data request after BFRD, status=%x\n", *CD_INDEX);
        return;
    }

    *dma3Madr = STR_SECTOR_ADDR & 0xffffff;
    *dma3Bcr = STR_SECTOR_WORDS | 0x10000;
    *dma3Chcr = STR_DMA3_START;

    guard = 0;
    while ((*dma3Chcr & DMA_BUSY) != 0 && guard < STR_WAIT_LIMIT)
        guard++;

    *CD_INDEX = 0;
    *CD_REG3 = 0;

    if (guard >= STR_WAIT_LIMIT)
    {
        *dma3Chcr = 0;
        strErrors++;
        return;
    }

    strDemuxSector();
}

/**
 * Services the CD-ROM controller: if a sector is ready, reads it and adds it
 * to the frame that is being assembled. Cheap when there is nothing to do,
 * call it as often as possible.
 */
void strPoll()
{
    int n;

    if (strActive == 0)
        return;

    strPolls++;
    if (strTrace != 0 && (strPolls & 0x7fff) == 0 && strHeartbeats < 12)
    {
        strHeartbeats++;
        printf("str: polls=%d sectors=%d\n", strPolls, strInts[1]);
        printf("str: frames received=%d decoded=%d\n", strFramesReceived, strFramesDecoded);
    }
    n = cdIntPending();
    if (n == 0)
        return;

    // Back-pressure: a new frame has nowhere to go until the waiting one is
    // taken. The sector stays unacknowledged, the controller holds it.
    if (n == 1 && strPaced != 0 && strAsmBuf < 0
        && (strReady >= 0 || (strBufState[0] != 0 && strBufState[1] != 0)))
    {
        strBlocked++;
        return;
    }

    if (n < 8)
        strInts[n]++;

    cdReadResponse();

    if (n == 1)
        strSectorReady(); // INT1: a sector is ready. Must be read before the ack
    else if (n == 4)
        strEof = 1;       // INT4: end of data
    else if (n == 5)
        strErrors++;      // INT5: error

    cdAck();
}

/**
 * Starts streaming from the given logical block address.
 * Returns 0, or -1 if the CD-ROM didn't accept the commands.
 */
int strStart(int lba)
{
    int mode = STR_MODE_SPEED | STR_MODE_XA;
    int i;

    if (strTrace != 0)
        printf("str: strStart entered, lba=%d\n", lba);

    strActive = 0;
    strEof = 0;
    strErrors = 0;
    strDropped = 0;
    strFramesReceived = 0;
    strFramesDecoded = 0;
    strBufState[0] = 0;
    strBufState[1] = 0;
    strReady = -1;
    strAsmBuf = -1;
    strAsmFrame = 0;
    strIgnoreFrame = 0;
    strStartStep = 0;
    strPolls = 0;
    strHeartbeats = 0;
    strVideoSectors = 0;
    strVlcErrors = 0;
    strTail = 0;
    strPaceStarted = 0;
    strWaits = 0;
    strBlocked = 0;
    for (i = 0; i < 8; i++)
        strInts[i] = 0;

    *dmaDpcr = *dmaDpcr | STR_DMA3_ENABLE;
    strMaskSaved = *strIMask & 4;

    // The BIOS may have its own CD-ROM interrupt handler installed (the BIOS file
    // functions such as cd_firstfile initialize it). It would read and acknowledge
    // the controller's interrupts before strPoll sees them. Masking the CD-ROM IRQ
    // keeps the CPU out of it; the controller flags that strPoll reads are not affected.
    *strIMask = *strIMask & ~4;
    *I_STAT = ~4;

    cdDrain();

    if (strFilterOn)
    {
        strCdReady();
        strCdParam(strFilterFile);
        strCdParam(strFilterChannel);
        if (cdCommand(STR_CD_SETFILTER, 0, 0) < 0)
        {
            strStartStep = 1;
            if (strTrace != 0)
                printf("str: strStart failed at step %d\n", 1);
            return -1;
        }
        mode = mode | STR_MODE_FILTER;
    }

    if (cdCommand(STR_CD_SETMODE, mode, 1) < 0)
    {
        strStartStep = 2;
        if (strTrace != 0)
            printf("str: strStart failed at step %d\n", 2);
        return -1;
    }

    if (strCdSetloc(lba) < 0)
    {
        strStartStep = 3;
        if (strTrace != 0)
            printf("str: strStart failed at step %d\n", 3);
        return -1;
    }

    strActive = 1;
    if (cdCommand(STR_CD_READS, 0, 0) < 0)
    {
        strActive = 0;
        strStartStep = 4;
        if (strTrace != 0)
            printf("str: strStart failed at step %d\n", 4);
        return -1;
    }
    if (strTrace != 0)
        printf("str: started, lba=%d mode=%x\n", lba, mode);
    return 0;
}

/**
 * Stops streaming, pauses the drive (which also silences the XA audio) and
 * gives the CD-ROM interrupt back to the BIOS if it was enabled before.
 * The drive is left in the XA/double speed mode: call cdInit() again before
 * playing CD audio.
 */
void strStop()
{
    strActive = 0;
    cdCommand(STR_CD_PAUSE, 0, 0);
    cdDrain();
    *I_STAT = ~4;
    if (strMaskSaved != 0)
        *strIMask = *strIMask | 4;
}

/**
 * Returns 1 when the movie is over: it has ended (or never started, or was
 * stopped) and every frame that was received has been drawn. Typical use:
 *
 *     while (strFinished() == 0)
 *     {
 *         if (strUpdate(0, displayOffset, MDEC_DEPTH_15BIT) == 1)
 *             gpuEndFrame();
 *     }
 *     strStop();
 */
int strFinished()
{
    if (strActive == 0)
        return 1;

    strPoll();

    if (strEof == 0)
        return 0;

    if (strReady >= 0)
        return 0; // the last frame hasn't been drawn yet

    return 1;
}

/**
 * If a complete frame is waiting, decodes it and draws it to VRAM at (x, y)
 * (in 16-bit VRAM pixels), using the given depth (MDEC_DEPTH_15BIT or
 * MDEC_DEPTH_24BIT). The CD-ROM is serviced while the decoding goes on.
 * The frame size is in strWidth/strHeight afterwards.
 *
 * Returns 1 if a frame has been drawn, 0 if no frame was ready, -1 on error
 * (the frame is dropped).
 */
int strUpdate(int x, int y, int depth)
{
    struct VlcJob job;
    struct MdecFrame f;
    uint* buf;
    int b;
    int r;

    strPoll();
    if (strReady < 0)
        return 0;

    if (strFrameDue(strReady) == 0)
    {
        strWaits++;
        return 0;
    }

    b = strReady;
    strReady = -1;
    strBufState[b] = 3;
    strLastFrame = strBufFrame[b];

    if (strPaced != 0 && strPaceStarted == 0)
    {
        strPaceStarted = 1;
        strPaceBase = *strClock;
        strPaceFirst = strBufFrame[b];
    }

    if (strTrace != 0 && strFramesDecoded < 8)
        printf("str: decode frame, %d bytes, %d dropped\n", strBufBytes[b], strDropped);

    // VLC decoding, in small steps
    buf = strDemuxBuffer(b);
    job.src = (uchar*)buf;
    job.srcBytes = strBufBytes[b];
    job.dst = STR_MDEC_ADDR;
    job.dstWords = STR_MDEC_WORDS;
    job.width = strBufWidth[b];
    job.height = strBufHeight[b];

    if (vlcBegin(&job) < 0)
    {
        strBufState[b] = 0;
        strErrors++;
        strVlcErrors++;
        return -1;
    }

    r = 0;
    while (r == 0)
    {
        r = vlcStep(12); // two macroblocks
        if (r == 0)
            strPoll();
    }

    // The demux buffer is not needed any more, the CD-ROM can fill it again
    strBufState[b] = 0;

    if (strTrace != 0 && strFramesDecoded < 8)
        printf("str: vlc r=%d words=%d\n", r, vlcOutWords);

    if (r < 0)
    {
        strErrors++;
        strVlcErrors++;
        return -1;
    }

    // MDEC decoding and the upload to VRAM
    f.data = STR_MDEC_ADDR;
    f.words = vlcOutWords;
    f.x = x;
    f.y = y;
    f.width = job.width;
    f.height = job.height;
    f.depth = depth;

    r = mdecFrameBegin(&f);
    if (strTrace != 0 && strFramesDecoded < 8)
        printf("str: mdec begin r=%d (%d words)\n", r, f.words);
    if (r < 0)
    {
        strErrors++;
        return -1;
    }

    while (r == 0)
    {
        strPoll();
        r = mdecFramePoll();
    }

    if (strTrace != 0 && strFramesDecoded < 8)
        printf("str: mdec done r=%d, frames received=%d\n", r, strFramesReceived);
    if (r < 0)
    {
        strErrors++;
        return -1;
    }

    strWidth = job.width;
    strHeight = job.height;
    strFramesDecoded++;
    return 1;
}

#endif
