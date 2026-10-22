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
 * Simple sound API.
 */

/**
 * Voice n registers start at 0x1F801C00 + n * 16, as ushort offsets:
 *   [0] vol L   [1] vol R   [2] pitch   [3] start addr (8-byte units)
 *   [4] ADSR1   [5] ADSR2
 */
#define SPU_VOICE_BASE 0x1F801C00

#if import

#import "dma.r"

// SPU registers

ushort* SPU_REVERB_BA = 0x1F801DA2; // Sound RAM reverb work area base address
ushort* SPU_IRQ       = 0x1F801DA4; // Sound RAM IRQ address
ushort* SPU_DA_ADDR   = 0x1F801DA6; // SPU RAM transfer address (8-byte units)
ushort* SPU_SPUCNT    = 0x1F801DAA; // SPU control
ushort* SPU_CNT_MODE  = 0x1F801DAC; // SPU RAM transfer control
ushort* SPU_SPUSTAT   = 0x1F801DAE; // SPU status
ushort* SPU_CDVOL_L   = 0x1F801DB0; // CD audio input volume (left)
ushort* SPU_CDVOL_R   = 0x1F801DB2; // CD audio input volume (right)

// Master volume
ushort* SPU_MVOL_L = 0x1F801D80;
ushort* SPU_MVOL_R = 0x1F801D82;

// Reverb volume
ushort* SPU_EVOL_L = 0x1F801D84;
ushort* SPU_EVOL_R = 0x1F801D86;

// "Key on" mode flags
ushort* SPU_KEY_ON0 = 0x1F801D88; // voices 0-15
ushort* SPU_KEY_ON1 = 0x1F801D8A; // voices 16-23

// "Key off" mode flags
ushort* SPU_KEY_OFF0 = 0x1F801D8C; // voices 0-15
ushort* SPU_KEY_OFF1 = 0x1F801D8E; // voices 16-23

// FM mode flags
ushort* SPU_FM_ON0 = 0x1F801D90; // voices 0-15
ushort* SPU_FM_ON1 = 0x1F801D92; // voices 16-23

// Noise mode flags
ushort* SPU_NOISE_ON0 = 0x1F801D94; // voices 0-15
ushort* SPU_NOISE_ON1 = 0x1F801D96; // voices 16-23

// Reverb mode flags
ushort* SPU_REVERB_ON0 = 0x1F801D98; // voices 0-15
ushort* SPU_REVERB_ON1 = 0x1F801D9A; // voices 16-23

// "Reached end" flags
ushort* SPU_ENDX0 = 0x1F801D9C; // voices 0-15
ushort* SPU_ENDX1 = 0x1F801D9E; // voices 16-23

// Internal state

// SPU RAM is 512 KB. The first 0x1000 bytes hold capture buffers, so
// sample data is allocated from 0x1000 upwards.
uint spuNextAddr;

// Sound table (up to 64 sounds)
uint sndAddr[64];    // byte address in SPU RAM
uint sndRate[64];    // sample rate in Hz
uint sndLoops[64];   // 1 if the last ADPCM block has the repeat flag
int  sndCount;

// Which sound each of the 24 voices is playing (-1 = free)
int voiceSound[24];

///
struct VAGHeader
{
    char magic[4];
    int version;
    int reserved1;
    int dataSize;
    int sampleRate;
    char reserved2[12];
    char name[16];
};

///
uint swapEndian(uint val)
{
    return ((val >> 24) & 0xff) |
           ((val << 8)  & 0xff0000) |
           ((val >> 8)  & 0xff00) |
           ((val << 24) & 0xff000000);
}

/**
 * Copies ADPCM data to SPU RAM. spu_dest_addr is a BYTE address
 * (uint, since SPU RAM is larger than 64 KB). vag_data must be 4-byte aligned.
 */
void spuUploadADPCM(uchar* vag_data, uint byte_size, uint spu_dest_addr)
{
    *dmaDpcr |= 0x00080000; // enable DMA4

    *SPU_SPUCNT = 0xC001; // stop any transfer
    for (int i = 0; i < 100; i++) nop();

    *SPU_DA_ADDR  = spu_dest_addr / 8;
    *SPU_CNT_MODE = 0x0004;  // step by 2

    *SPU_SPUCNT = 0xC021; // DMA write mode
    //while ((*SPU_SPUSTAT & 0x0030) != 0x0020) nop();
    for (int i = 0; i < 150; i++) nop();

    *dma4Madr = (uint)vag_data & 0x1FFFFC;

    uint blocks = (byte_size + 63) / 64; // round UP to 64-byte blocks
    *dma4Bcr  = 0x10 | (blocks << 16);
    *dma4Chcr = 0x01000201;

    while (*dma4Chcr & (1 << 24)) nop();
    
    //while (*SPU_SPUSTAT & (1 << 10)) nop();
    for (int i = 0; i < 200; i++) nop(); 

    *SPU_SPUCNT = 0xC001; // back to normal
    for (int i = 0; i < 100; i++) nop();
}

void spuKeyOn(int voice)
{
    if (voice < 16) *SPU_KEY_ON0 = 1 << voice;
    else            *SPU_KEY_ON1 = 1 << (voice - 16);
}

void spuKeyOff(int voice)
{
    if (voice < 16) *SPU_KEY_OFF0 = 1 << voice;
    else            *SPU_KEY_OFF1 = 1 << (voice - 16);
}

int spuEndReached(int voice)
{
    if (voice < 16) return (*SPU_ENDX0 >> voice) & 1;
    return (*SPU_ENDX1 >> (voice - 16)) & 1;
}

// 0..127 -> 0..0x3FFF
int spuScaleVolume(int vol)
{
    if (vol < 0) vol = 0;
    if (vol > 127) vol = 127;
    return (vol * 0x3FFF) / 127;
}

// Public API

void spuInit()
{
    // Clear the SPU
    *SPU_SPUCNT = 0x0000;
    *SPU_MVOL_L = 0;
    *SPU_MVOL_R = 0;
    *SPU_EVOL_L = 0;
    *SPU_EVOL_R = 0;
    *SPU_FM_ON0 = 0;
    *SPU_FM_ON1 = 0; 
    *SPU_REVERB_ON0 = 0;
    *SPU_REVERB_ON1 = 0;
    *SPU_NOISE_ON0 = 0;
    *SPU_NOISE_ON1 = 0; 
    
    // Initialize
    *SPU_SPUCNT = 0xC001;
    *SPU_MVOL_L = 0x3FFF;
    *SPU_MVOL_R = 0x3FFF;
    *SPU_CDVOL_L = 0x7FFF;
    *SPU_CDVOL_R = 0x7FFF;

    *dmaDpcr |= 0x00080000;

    // all voices off, noise off, volume 0
    *SPU_KEY_OFF0 = 0xFFFF;
    *SPU_KEY_OFF1 = 0x00FF;
    *SPU_NOISE_ON0 = 0;
    *SPU_NOISE_ON1 = 0;

    for (int v = 0; v < 24; v++)
    {
        ushort* r = (ushort*)(SPU_VOICE_BASE + v * 16);
        r[0] = 0;
        r[1] = 0;
        r[2] = 0;
        r[3] = 0;
        r[4] = 0;
        r[5] = 0;
        r[6] = 0;
        voiceSound[v] = -1;
    }
    
    ushort dummy0 = *SPU_ENDX0;
    ushort dummy1 = *SPU_ENDX1;

    spuNextAddr = 0x1000;
    sndCount = 0;
}

/// 0..127
void spuSetMasterVolume(int vol)
{
    int v = spuScaleVolume(vol);
    *SPU_MVOL_L = v;
    *SPU_MVOL_R = v;
}

/// Frees all sample memory. Stops everything first.
void spuFreeAll()
{
    spuStopAll();
    spuNextAddr = 0x1000;
    sndCount = 0;
}

/// Uploads raw ADPCM blocks (no header). Returns a sound id, or -1 on failure.
int spuLoadADPCM(uchar* data, uint size, uint rate)
{
    if (sndCount >= 64) return -1;

    uint aligned = (size + 63) & ~63;  // matches the 64-byte DMA blocks
    if (spuNextAddr + aligned > 0x80000) return -1;   // out of SPU RAM

    spuUploadADPCM(data, size, spuNextAddr);

    int id = sndCount;
    sndAddr[id]  = spuNextAddr;
    sndRate[id]  = rate;
    // last block is 16 bytes, flags byte is its 2nd byte; bit 1 = repeat
    sndLoops[id] = (data[size - 15] >> 1) & 1;

    spuNextAddr += aligned;
    sndCount++;
    return id;
}

/// Uploads a .vag file (48-byte header + ADPCM). Returns a sound id, or -1.
int spuLoadVag(uchar* vagFile)
{
    struct VAGHeader* h = (struct VAGHeader*)vagFile;
    uint size = swapEndian(h->dataSize);
    uint rate = swapEndian(h->sampleRate);
    return spuLoadADPCM(vagFile + 48, size, rate);
}

/**
 * Changes the playback rate of a voice, in Hz (e.g. 22050 = half pitch
 * for a 44100 Hz sample). Call it right after spuPlayVoice to override
 * the sound's own rate.
 */
void spuSetPitch(int voice, uint rate)
{
    ushort* r = (ushort*)(SPU_VOICE_BASE + voice * 16);
    r[2] = (rate << 12) / 44100; // 0x1000 = 44100 Hz
}

/// Changes L/R volume (0..127) of a voice that is already playing.
void spuSetVolume(int voice, int volL, int volR)
{
    ushort* r = (ushort*)(SPU_VOICE_BASE + voice * 16);
    r[0] = spuScaleVolume(volL);
    r[1] = spuScaleVolume(volR);
}

/// Is this voice still making sound?
int spuVoicePlaying(int voice)
{
    int s = voiceSound[voice];
    if (s < 0) return 0;
    if (sndLoops[s]) return 1; // looping sounds play until stopped
    ushort* r = (ushort*)(SPU_VOICE_BASE + voice * 16);
    ushort current_adsr_vol = r[6];
    if (current_adsr_vol == 0)
    {
        voiceSound[voice] = -1;
        return 0;
    }
    return 1;
}

/// Is any voice currently playing this sound?
int spuSoundPlaying(int sound)
{
    for (int v = 0; v < 24; v++)
        if (voiceSound[v] == sound && spuVoicePlaying(v))
            return 1;
    return 0;
}

/// Plays a sound on a specific voice with separate L/R volume (0..127).
void spuPlayVoice(int sound, int voice, int volL, int volR)
{
    ushort* r = (ushort*)(SPU_VOICE_BASE + voice * 16);
    uint rate = sndRate[sound];

    spuKeyOff(voice);

    r[0] = spuScaleVolume(volL);
    r[1] = spuScaleVolume(volR);
    r[2] = (rate << 12) / 44100;
    r[3] = sndAddr[sound] / 8;
    r[4] = 0x00FF; 
    r[5] = 0x0000;
    r[6] = 0x7FFF;

    voiceSound[voice] = sound;
    spuKeyOn(voice);
}

/**
 * Plays a sound on the first free voice at volume 0..127.
 * Returns the voice number, or -1 if all 24 voices are busy.
 */
int spuPlay(int sound, int volume)
{
    for (int v = 0; v < 24; v++)
    {
        if (!spuVoicePlaying(v))
        {
            spuPlayVoice(sound, v, volume, volume);
            return v;
        }
    }
    return -1;
}

void spuStop(int voice)
{
    spuKeyOff(voice);
    voiceSound[voice] = -1;
}

/// Stops every voice playing this sound
void spuStopSound(int sound)
{
    for (int v = 0; v < 24; v++)
        if (voiceSound[v] == sound)
            spuStop(v);
}

void spuStopAll()
{
    *SPU_KEY_OFF0 = 0xFFFF;
    *SPU_KEY_OFF1 = 0x00FF;
    for (int v = 0; v < 24; v++)
        voiceSound[v] = -1;
}

#endif
