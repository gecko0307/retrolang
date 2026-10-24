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
 * MDEC (Motion Decoder) driver.
 *
 * Decodes MDEC macroblock data (the output of a VLC/bitstream decoder) and
 * uploads the resulting pixels to VRAM, one macroblock column (16 pixels wide)
 * at a time. The MDEC cannot feed the GPU by itself, so the pixels pass through
 * a small pair of RAM buffers, but the CPU never touches them: MDEC input,
 * MDEC output and the GPU upload are all DMA transfers.
 */

// MDEC I/O ports
#define MDEC0 0x1F801820 // write: command/parameters, read: decoded data
#define MDEC1 0x1F801824 // write: control, read: status

// MDEC1 control register (write)
#define MDEC_CTRL_RESET     0x80000000
#define MDEC_CTRL_DMA_IN    0x40000000 // enable data-in requests (DMA0)
#define MDEC_CTRL_DMA_OUT   0x20000000 // enable data-out requests (DMA1)

// MDEC1 status register (read)
#define MDEC_STAT_IN_FULL   0x40000000 // data-in FIFO full

// MDEC0 commands
#define MDEC_CMD_DECODE     0x20000000 // command 1, decode macroblocks
#define MDEC_CMD_SET_QUANT  0x40000000 // command 2, set quant table(s)
#define MDEC_CMD_SET_SCALE  0x60000000 // command 3, set IDCT scale table

// Output depth
#define MDEC_DEPTH_24BIT    24
#define MDEC_DEPTH_15BIT    15
#define MDEC_OUT_24BIT      0x10000000 // command bits 28-27 = 2
#define MDEC_OUT_15BIT      0x18000000 // command bits 28-27 = 3

// DMA channels 0 (MDECin) and 1 (MDECout)
#define MDEC_DMA_IN_ENABLE  0x00000008
#define MDEC_DMA_OUT_ENABLE 0x00000080
#define MDEC_DMA_IN_START   0x01000201 // RAM -> MDEC, block mode, start
#define MDEC_DMA_OUT_START  0x01000200 // MDEC -> RAM, block mode, start

// DMA block size in words for both directions
#define MDEC_BLOCK_WORDS    32

// Busy-wait limit for DMA completion (iterations)
#define MDEC_TIMEOUT        4000000

// Same for the polled frame decoder (number of polls)
#define MDEC_POLL_LIMIT     2000000

/*
 * Two column buffers at fixed RAM addresses. Each holds a fake 3-word TIM data
 * header followed by one decoded macroblock column: up to 6144 words
 * (15 bpp: 768 lines, 24 bpp: 512 lines).
 */
#define MDEC_BUF0        0x801A0000
#define MDEC_BUF1        0x801A8000
#define MDEC_BUF_WORDS   6160
#define MDEC_BUF_BYTES   24640
macro MDECRegionBuffer0 = (MDEC_BUF0, MDEC_BUF_BYTES);
macro MDECRegionBuffer1 = (MDEC_BUF1, MDEC_BUF_BYTES);

#if import

#import "core.r"
#import "dma.r"
#import "gpu.r"

// MDEC I/O ports
int* mdec0 = MDEC0;
int* mdec1 = MDEC1;

// Column buffers (see above)
uint mdecColumnBuf0[MDEC_BUF_WORDS] @MDECRegionBuffer0;
uint mdecColumnBuf1[MDEC_BUF_WORDS] @MDECRegionBuffer1;

/**
 * Frame description for mdecDecodeFrame.
 *
 * data   - macroblock data in MDEC format (VLC-decoded bitstream without the
 *          frame header). The buffer must be padded with zero words up to a
 *          multiple of 32 words (128 bytes), because MDEC input DMA works in
 *          blocks of 32 words; the padding is read as no-op MDEC commands.
 * words  - number of meaningful words in data (1..65535)
 * x, y   - destination in VRAM (in 16-bit VRAM pixels)
 * width  - frame width in pixels, multiple of 16
 * height - frame height in pixels, multiple of 16
 * depth  - MDEC_DEPTH_15BIT or MDEC_DEPTH_24BIT. In 24-bit mode, a VRAM
 *          rectangle is 1.5 times narrower than the frame (3 bytes per pixel),
 *          and the GPU must be in 24-bit display mode.
 */
struct MdecFrame
{
    uint* data;
    int words;
    int x;
    int y;
    int width;
    int height;
    int depth;
};

// Default quantization table for STR movies (64 bytes, packed into words).
// Used for both luminance and chroma.
uint mdecDefaultQuant[16] =
{
    0x13101002, 0x16161310, 0x16161616, 0x1b1a181a,
    0x1a1a1b1b, 0x1b1b1a1a, 0x1d1d1d1b, 0x1d222222,
    0x1b1b1d1d, 0x20201d1d, 0x26252222, 0x22232325,
    0x28262623, 0x30302828, 0x38382e2e, 0x5345453a
};

// Default IDCT scale table (64 signed 16-bit values with a 14-bit fraction,
// packed into words). Standard JPEG constants, used by all known games.
uint mdecDefaultScale[32] =
{
    0x5a825a82, 0x5a825a82, 0x5a825a82, 0x5a825a82,
    0x6a6d7d8a, 0x18f8471c, 0xb8e3e707, 0x82759592,
    0x30fb7641, 0x89becf04, 0xcf0489be, 0x764130fb,
    0xe7076a6d, 0xb8e38275, 0x7d8a471c, 0x959218f8,
    0xa57d5a82, 0x5a82a57d, 0xa57d5a82, 0x5a82a57d,
    0x8275471c, 0x6a6d18f8, 0xe7079592, 0xb8e37d8a,
    0x89be30fb, 0xcf047641, 0x7641cf04, 0x30fb89be,
    0xb8e318f8, 0x82756a6d, 0x95927d8a, 0xe707471c
};

/// Returns the MDEC status register.
int mdecStatus()
{
    return *mdec1;
}

/// Writes one word to MDEC0, waiting while the data-in FIFO is full.
void mdecPutWord(uint w)
{
    int guard = 0;
    while ((*mdec1 & MDEC_STAT_IN_FULL) != 0 && guard < MDEC_TIMEOUT)
        guard++;
    *mdec0 = w;
}

/// Waits until a DMA channel is idle. Returns 0, or -1 on timeout.
int mdecWaitDma(int* chcr)
{
    int guard = 0;
    while ((*chcr & DMA_BUSY) != 0)
    {
        guard++;
        if (guard > MDEC_TIMEOUT)
            return -1;
    }
    return 0;
}

// Staging buffer for the quantization tables (luma and chroma must be contiguous)
uint mdecQuantBuf[32];

/**
 * Sends words to the MDEC with DMA0 and waits until the transfer is done.
 * The number of words must be a multiple of 32.
 * Parameters of MDEC commands must go this way: the MDEC takes the command
 * from the port, but only reads its parameters from the DMA stream (and so do
 * accurate emulators), so writing them to MDEC0 with the CPU doesn't work.
 * Returns 0, or -1 on timeout.
 */
int mdecDmaIn(uint* data, int words)
{
    *dma0Madr = (uint)data & 0xffffff;
    *dma0Bcr = MDEC_BLOCK_WORDS | ((words >> 5) << 16);
    *dma0Chcr = MDEC_DMA_IN_START;
    return mdecWaitDma(dma0Chcr);
}

/// Resets the MDEC and enables its DMA requests.
void mdecReset()
{
    *mdec1 = MDEC_CTRL_RESET;
    *mdec1 = MDEC_CTRL_DMA_IN | MDEC_CTRL_DMA_OUT;
}

/**
 * Sets the quantization tables. Each table is 16 words (64 bytes).
 * If chroma is null, only the luminance table is set.
 */
void mdecSetQuantTable(uint* luma, uint* chroma)
{
    int i;
    for (i = 0; i < 16; i++)
    {
        mdecQuantBuf[i] = luma[i];
        if (chroma == null)
            mdecQuantBuf[16 + i] = luma[i];
        else
            mdecQuantBuf[16 + i] = chroma[i];
    }

    // The command goes through the port, the table itself through DMA0
    mdecPutWord(MDEC_CMD_SET_QUANT | 1);
    mdecDmaIn(mdecQuantBuf, 32);
}

/// Sets the IDCT scale table (32 words = 64 signed halfwords).
void mdecSetScaleTable(uint* table)
{
    mdecPutWord(MDEC_CMD_SET_SCALE);
    mdecDmaIn(table, 32);
}

/**
 * Initializes the MDEC: enables DMA channels 0 and 1, resets the decoder and
 * loads the default quantization and scale tables.
 * Call it after gpuInit.
 */
void mdecInit()
{
    *dmaDpcr = *dmaDpcr | MDEC_DMA_IN_ENABLE | MDEC_DMA_OUT_ENABLE;
    mdecReset();
    mdecSetQuantTable(mdecDefaultQuant, mdecDefaultQuant);
    mdecSetScaleTable(mdecDefaultScale);
}

// Aborts transfers in progress and brings MDEC back to a known state.
void mdecAbort()
{
    *dma0Chcr = 0;
    *dma1Chcr = 0;
    mdecReset();
}

// Column buffer for the given column index (they alternate).
uint* mdecColumnBuffer(int index)
{
    uint* p = MDEC_BUF0;
    if (index & 1)
        p = MDEC_BUF1;
    return p;
}

// Starts MDEC -> RAM DMA of one column. The pixels land right after the
// 3-word header of the column buffer.
void mdecStartOut(uint* buf, int words)
{
    *dma1Madr = (uint)(buf + 3) & 0xffffff;
    *dma1Bcr = MDEC_BLOCK_WORDS | ((words >> 5) << 16);
    *dma1Chcr = MDEC_DMA_OUT_START;
}

// Width in VRAM pixels (16-bit units) of one 16-pixel macroblock column
int mdecVramWidth(struct MdecFrame* f)
{
    if (f->depth == MDEC_DEPTH_24BIT)
        return 24;
    return 16;
}

// Number of words in one decoded macroblock column
int mdecColumnWords(struct MdecFrame* f)
{
    if (f->depth == MDEC_DEPTH_24BIT)
        return f->height * 12;
    return f->height * 8;
}

// Uploads the decoded column with the given index to VRAM. A TIM data header
// is built in front of the pixels, so the existing GPU upload routine can be
// used as is.
void mdecUploadColumn(struct MdecFrame* f, uint* buf, int column)
{
    int w = mdecVramWidth(f);
    int words = mdecColumnWords(f);
    struct TimData* hdr = (struct TimData*)buf;
    hdr->size = (words + 3) << 2;
    hdr->pos = (f->y << 16) | ((f->x + column * w) & 0xffff);
    hdr->wh = (f->height << 16) | w;
    gpuQueueMemToVram(hdr, hdr->size);
}

// State of the resumable frame decoder (see mdecFrameBegin)
struct MdecFrame* mdecJob = 0;
int mdecPhase = 0;    // 0 idle, 1 decoding columns, 2 waiting for MDECin DMA
int mdecCol = 0;      // column that is being decoded
int mdecCols = 0;     // total number of columns
int mdecColWords = 0; // size of one decoded column in words
int mdecGuard = 0;    // number of polls spent waiting for the hardware
int mdecTrace = 0;    // set to 1 to log timeouts to the TTY (BIOS printf)

// Counts a poll that found the hardware busy. Returns 0, or -1 on timeout.
int mdecBusy()
{
    mdecGuard++;
    if (mdecGuard > MDEC_POLL_LIMIT)
    {
        if (mdecTrace != 0)
            bios_a(0x3f, "mdec: timeout, phase=%d column=%d\n", mdecPhase, mdecCol);
        mdecAbort();
        mdecPhase = 0;
        return -1;
    }
    return 0;
}

/**
 * Starts decoding a frame. The work is then advanced by mdecFramePoll().
 * The frame is decoded as a sequence of 16-pixel wide columns, in the order
 * macroblocks are stored in the bitstream. While column N is being uploaded to
 * VRAM, the MDEC is already decoding column N+1.
 *
 * The MdecFrame struct must stay valid until the frame is finished.
 * This function flushes the GPU command queue (gpuQueueMemToVram does so
 * for every column), so call it at the start of the frame, before sorting
 * primitives.
 *
 * Returns 0 if started, -1 on invalid parameters or a timeout.
 */
int mdecFrameBegin(struct MdecFrame* f)
{
    int colWords;
    uint cmd;
    uint blocks;

    mdecPhase = 0;

    if (f->data == null || f->words < 1 || f->words > 0xffff)
        return -1;
    if ((f->width & 15) != 0 || (f->height & 15) != 0 || f->width < 16 || f->height < 16)
        return -1;

    if (f->depth == MDEC_DEPTH_15BIT)
    {
        cmd = MDEC_CMD_DECODE | MDEC_OUT_15BIT;
        colWords = f->height * 8;
    }
    else if (f->depth == MDEC_DEPTH_24BIT)
    {
        cmd = MDEC_CMD_DECODE | MDEC_OUT_24BIT;
        colWords = f->height * 12;
    }
    else
    {
        return -1;
    }

    if (colWords + 3 > MDEC_BUF_WORDS)
        return -1;

    // Make sure the previous frame is completely done
    if (mdecWaitDma(dma0Chcr) < 0 || mdecWaitDma(dma1Chcr) < 0)
    {
        mdecAbort();
        return -1;
    }

    mdecJob = f;
    mdecCols = f->width >> 4;
    mdecColWords = colWords;
    mdecCol = 0;
    mdecGuard = 0;

    // Decode command, then the macroblock data via DMA0
    mdecPutWord(cmd | f->words);

    blocks = (f->words + MDEC_BLOCK_WORDS - 1) >> 5;
    *dma0Madr = (uint)f->data & 0xffffff;
    *dma0Bcr = MDEC_BLOCK_WORDS | (blocks << 16);
    *dma0Chcr = MDEC_DMA_IN_START;

    // Start decoding the first column
    mdecStartOut(mdecColumnBuffer(0), colWords);

    mdecPhase = 1;
    return 0;
}

/**
 * Advances the frame started by mdecFrameBegin. Never blocks for long: one call
 * uploads at most one column, so the caller can do other work (for example
 * service the CD-ROM) between the calls.
 * Returns 0 while the frame is in progress, 1 when it is complete,
 * -1 on a timeout.
 */
int mdecFramePoll()
{
    int c;
    uint* cur;

    if (mdecPhase == 0)
        return 1;

    if (mdecPhase == 1)
    {
        if ((*dma1Chcr & DMA_BUSY) != 0)
            return mdecBusy();

        c = mdecCol;
        cur = mdecColumnBuffer(c);

        // Let the MDEC work on the next column while this one goes to VRAM
        if (c + 1 < mdecCols)
            mdecStartOut(mdecColumnBuffer(c + 1), mdecColWords);

        mdecUploadColumn(mdecJob, cur, c);

        mdecCol = c + 1;
        mdecGuard = 0;
        if (mdecCol >= mdecCols)
            mdecPhase = 2;
        return 0;
    }

    // All columns are out, wait until the input DMA has finished too
    if ((*dma0Chcr & DMA_BUSY) != 0)
        return mdecBusy();

    mdecPhase = 0;
    return 1;
}

/**
 * Decodes a frame and uploads it to VRAM, waiting until it is done.
 * Returns 0 on success, -1 on invalid parameters or a transfer timeout.
 */
int mdecDecodeFrame(struct MdecFrame* f)
{
    int r = mdecFrameBegin(f);
    if (r < 0)
        return -1;

    while (r == 0)
        r = mdecFramePoll();

    if (r < 0)
        return -1;
    return 0;
}

#endif
