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
 * SEQ music sequencer.
 *
 * Plays SEQ files (*.seq) using instruments from a VAB bank (vab.r).
 * It is a software sequencer: you call seqUpdate() once per frame (or
 * seqStep() with the elapsed time) and it drives the SPU voices.
 *
 * Usage:
 *
 *   spuInit();
 *   int bank = vabLoad(vhData, vbData);
 *   seqInit();
 *   seqPlay(seqData, bank, 1);        // 1 = repeat at the end
 *   while (1)
 *   {
 *       padWaitSync();                // once per VBlank
 *       seqUpdate();
 *   }
 *
 * The sequencer owns a range of SPU voices (16 by default, 0..15) which
 * spuPlay will not use, so sound effects can keep playing on the others.
 *
 * SEQ format (big-endian): "pQES", version (u32, 1), resolution (u16, ticks
 * per quarter note), tempo (u24, microseconds per quarter note), time
 * signature (2 bytes), then a MIDI-like event stream: variable-length delta
 * time, status byte, data. Running status is supported. The tempo meta
 * event has no length byte (FF 51 tt tt tt), the track ends with FF 2F.
 *
 * Supported events: note on/off, program change, pitch bend, controllers
 * 6 (data entry), 7 (volume), 10 (pan), 11 (expression), 64 (sustain),
 * 99 (NRPN: loop markers), 120/123 (all notes off).
 * Loop markers: CC99=20 starts a loop (a following CC6 gives the number of
 * plays, 127 = forever), CC99=30 ends it. Loops cannot be nested.
 */

#define SEQ_CHANNELS 16

#if import

#import "spu.r"
#import "vab.r"

struct SeqChannel
{
    int program;
    int volume;     // CC7, 0..127
    int expression; // CC11, 0..127
    int pan;        // CC10, 0..127, 64 = center
    int bend;       // 14-bit, 0x2000 = center
    int sustain;    // CC64 pedal pressed
    int nrpn;       // last CC99 value
};

struct SeqVoice
{
    int state;      // 0 = free, 1 = key held, 2 = releasing, 3 = held by pedal
    int channel;
    int key;
    int base;       // velocity * tone volume * program volume * bank volume
    int serial;     // note start order, used for voice stealing
    int fresh;      // key-on happened since the last seqStep
    uchar* tone;    // VagAtr record
};

struct SeqChannel seqChan[SEQ_CHANNELS];
struct SeqVoice seqVoices[24];

// 2^(k/12) in 4096ths
int seqPitchTab[13] = {4096, 4340, 4598, 4871, 5161, 5468, 5793, 6137, 6502, 6889, 7298, 7732, 8192};

// Playback state
int    seqState;            // 0 = stopped, 1 = playing, 2 = paused
int    seqBank;
int    seqRepeat;           // restart at the end of the track
uchar* seqBase;             // start of the event stream
uchar* seqPos;              // read pointer
int    seqStatus;           // running status
uint   seqWait;             // ticks until the next event
uint   seqTempo;            // microseconds per quarter note
uint   seqPpqn;             // ticks per quarter note
uint   seqAcc;              // fractional tick accumulator
int    seqSerial;
int    seqMasterVol;        // 0..127

// Loop state
uchar* seqLoopStart;
int    seqLoopCount;
int    seqLoopArm;

// Voice range owned by the sequencer
int    seqFirstVoice;
int    seqNumVoices;

// Time source
uint   seqFrameUs;          // length of one frame in microseconds
uint   seqHblankUs64;       // HBlank period in 1/64 microsecond
int    seqTimerLast;

ushort* SEQ_T1_COUNT = 0x1F801110; // root counter 1 current value
ushort* SEQ_T1_MODE  = 0x1F801114; // root counter 1 mode

// Reads a variable-length quantity (7 bits per byte, high bit = more)
uint seqReadDelta()
{
    uint v = 0;
    uint b = *seqPos;
    seqPos++;
    v = b & 0x7F;
    while (b & 0x80)
    {
        b = *seqPos;
        seqPos++;
        v = (v << 7) | (b & 0x7F);
    }
    return v;
}

// Computes the SPU pitch register value for a key, tone and pitch bend
int seqCalcPitch(uchar* tone, int key, int bend)
{
    int center = tone[4];
    int shift = tone[5];
    int b = bend - 0x2000;
    int range = tone[13]; // pitch bend limit up (semitones)
    if (b < 0) range = tone[12]; // down

    // Offset from the root key in 1/128 semitones, biased to stay positive
    int o = (key - center) * 128 + shift + b * range / 64 + 24576;
    if (o < 0) o = 0;

    int semis = o / 128;
    int frac = o - semis * 128;
    int oct = semis / 12;
    int k = semis - oct * 12;

    // 0x1000 is the native sample rate
    int p = seqPitchTab[k] + (seqPitchTab[k + 1] - seqPitchTab[k]) * frac / 128;
    oct = oct - 16; // remove the bias
    if (oct >= 0) p = p << oct;
    else p = p >> (0 - oct);
    if (p > 0x3FFF) p = 0x3FFF;
    return p;
}

// Writes the left/right volume of a voice from the current channel state
void seqApplyVolume(int v)
{
    struct SeqVoice* sv = &seqVoices[v];
    struct SeqChannel* c = &seqChan[sv->channel];

    // 0..16129 (127 * 127)
    int a = sv->base * c->volume / 127;
    a = a * c->expression / 127;
    a = a * seqMasterVol / 127;

    int pan = sv->tone[3] + c->pan - 64;
    if (pan < 0) pan = 0;
    if (pan > 127) pan = 127;

    int l = a;
    int r = a;
    if (pan < 64) r = a * pan / 64;
    else l = a * (127 - pan) / 63;

    // 0..16129 -> 0..0x3FFF
    ushort* regs = (ushort*)(SPU_VOICE_BASE + v * 16);
    regs[0] = l + (l >> 6);
    regs[1] = r + (r >> 6);
}

// Re-applies the volume of every sounding voice of a channel
void seqUpdateChannelVolume(int ch)
{
    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
    {
        struct SeqVoice* sv = &seqVoices[v];
        if ((sv->state == 1 || sv->state == 3) && sv->channel == ch)
            seqApplyVolume(v);
    }
}

void seqUpdateChannelPitch(int ch)
{
    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
    {
        struct SeqVoice* sv = &seqVoices[v];
        if ((sv->state == 1 || sv->state == 3) && sv->channel == ch)
        {
            ushort* regs = (ushort*)(SPU_VOICE_BASE + v * 16);
            regs[2] = seqCalcPitch(sv->tone, sv->key, seqChan[ch].bend);
        }
    }
}

void seqReleaseVoice(int v)
{
    spuKeyOff(v);
    seqVoices[v].state = 2;
}

// Releases every sounding voice of a channel
void seqReleaseChannel(int ch)
{
    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
    {
        struct SeqVoice* sv = &seqVoices[v];
        if ((sv->state == 1 || sv->state == 3) && sv->channel == ch)
            seqReleaseVoice(v);
    }
}

void seqReleaseAll()
{
    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
    {
        int s = seqVoices[v].state;
        if (s == 1 || s == 3)
            seqReleaseVoice(v);
    }
}

// Finds a free voice or steals one. Returns -1 if the sequencer has no voices.
int seqAllocVoice()
{
    int best = -1;
    int bestScore = 0x7FFFFFFF;

    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
    {
        struct SeqVoice* sv = &seqVoices[v];

        // A voice whose envelope has reached zero is finished
        if (sv->state != 0 && sv->fresh == 0)
        {
            ushort* regs = (ushort*)(SPU_VOICE_BASE + v * 16);
            if (regs[6] == 0) sv->state = 0;
        }

        if (sv->state == 0) return v;

        // Steal releasing voices first, then the oldest note
        int score = sv->serial;
        if (sv->state == 2) score = score - 0x40000000;
        if (score < bestScore)
        {
            bestScore = score;
            best = v;
        }
    }
    return best;
}

void seqStartVoice(int ch, int key, int vel, uchar* tone)
{
    int v = seqAllocVoice();
    if (v < 0) return;

    struct SeqVoice* sv = &seqVoices[v];
    struct SeqChannel* c = &seqChan[ch];

    uchar* prog = vabProgram(seqBank, c->program);
    int vag = tone[22] | (tone[23] << 8);
    uint addr = vabSampleAddr(seqBank, vag);

    int base = vel * tone[2];
    base = base * prog[1] / 127;
    base = base * vabMasterVolume(seqBank) / 127;

    int stolen = sv->state;

    sv->state = 1;
    sv->channel = ch;
    sv->key = key;
    sv->base = base;
    sv->serial = seqSerial;
    sv->fresh = 1;
    sv->tone = tone;
    seqSerial++;

    if (stolen != 0) spuKeyOff(v); // restart a stolen voice cleanly

    ushort* regs = (ushort*)(SPU_VOICE_BASE + v * 16);
    regs[2] = seqCalcPitch(tone, key, c->bend);
    regs[3] = addr / 8;
    regs[4] = tone[16] | (tone[17] << 8); // ADSR1
    regs[5] = tone[18] | (tone[19] << 8); // ADSR2
    seqApplyVolume(v);

    spuKeyOn(v);
}

void seqNoteOn(int ch, int key, int vel)
{
    int program = seqChan[ch].program;
    int n = vabToneCount(seqBank, program);
    for (int i = 0; i < n; i++)
    {
        uchar* tone = vabTone(seqBank, program, i);
        if (key >= tone[6] && key <= tone[7])
            seqStartVoice(ch, key, vel, tone);
    }
}

void seqNoteOff(int ch, int key)
{
    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
    {
        struct SeqVoice* sv = &seqVoices[v];
        if (sv->state == 1 && sv->channel == ch && sv->key == key)
        {
            if (seqChan[ch].sustain) sv->state = 3;
            else seqReleaseVoice(v);
        }
    }
}

void seqResetChannels()
{
    for (int i = 0; i < SEQ_CHANNELS; i++)
    {
        seqChan[i].program = 0;
        seqChan[i].volume = 127;
        seqChan[i].expression = 127;
        seqChan[i].pan = 64;
        seqChan[i].bend = 0x2000;
        seqChan[i].sustain = 0;
        seqChan[i].nrpn = 0;
    }
}

void seqLoopEnd()
{
    if (seqLoopStart == 0) return;

    if (seqLoopCount == 127) // forever
    {
        seqPos = seqLoopStart;
        seqLoopArm = 0;
    }
    else if (seqLoopCount > 1)
    {
        seqLoopCount--;
        seqPos = seqLoopStart;
        seqLoopArm = 0;
    }
    else
    {
        seqLoopStart = 0; // finished, continue after the marker
    }
}

void seqController(int ch, int cc, int val)
{
    struct SeqChannel* c = &seqChan[ch];

    if (cc == 7)
    {
        c->volume = val;
        seqUpdateChannelVolume(ch);
    }
    else if (cc == 10)
    {
        c->pan = val;
        seqUpdateChannelVolume(ch);
    }
    else if (cc == 11)
    {
        c->expression = val;
        seqUpdateChannelVolume(ch);
    }
    else if (cc == 64)
    {
        if (val >= 64)
        {
            c->sustain = 1;
        }
        else
        {
            c->sustain = 0;
            for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
            {
                struct SeqVoice* sv = &seqVoices[v];
                if (sv->state == 3 && sv->channel == ch)
                    seqReleaseVoice(v);
            }
        }
    }
    else if (cc == 99)
    {
        c->nrpn = val;
        if (val == 20)
        {
            seqLoopStart = seqPos; // already past this event
            seqLoopCount = 127;
            seqLoopArm = 1;
        }
        else if (val == 30)
        {
            seqLoopEnd();
        }
    }
    else if (cc == 6)
    {
        if (seqLoopArm)
        {
            seqLoopCount = val;
            seqLoopArm = 0;
        }
    }
    else if (cc == 120 || cc == 123)
    {
        seqReleaseChannel(ch);
    }
}

// Moves the read pointer to the start of the track (the first delta time is not read)
void seqRewind()
{
    seqPos = seqBase;
    seqStatus = 0;
    seqLoopStart = 0;
    seqLoopCount = 0;
    seqLoopArm = 0;
}

void seqStopNow()
{
    seqReleaseAll();
    seqState = 0;
}

// Executes the event at the read pointer (its delta time is already consumed)
void seqEvent()
{
    int st = *seqPos;
    if (st & 0x80)
    {
        seqStatus = st;
        seqPos++;
    }

    int cmd = seqStatus & 0xF0;
    int ch = seqStatus & 0x0F;

    if (cmd == 0x90)
    {
        int key = seqPos[0];
        int vel = seqPos[1];
        seqPos += 2;
        if (vel == 0) seqNoteOff(ch, key);
        else seqNoteOn(ch, key, vel);
    }
    else if (cmd == 0x80)
    {
        int key = seqPos[0];
        seqPos += 2;
        seqNoteOff(ch, key);
    }
    else if (cmd == 0xB0)
    {
        int cc = seqPos[0];
        int val = seqPos[1];
        seqPos += 2;
        seqController(ch, cc, val);
    }
    else if (cmd == 0xC0)
    {
        seqChan[ch].program = seqPos[0];
        seqPos++;
    }
    else if (cmd == 0xE0)
    {
        seqChan[ch].bend = seqPos[0] | (seqPos[1] << 7);
        seqPos += 2;
        seqUpdateChannelPitch(ch);
    }
    else if (cmd == 0xA0)
    {
        seqPos += 2; // polyphonic aftertouch, ignored
    }
    else if (cmd == 0xD0)
    {
        seqPos += 1; // channel pressure, ignored
    }
    else if (seqStatus == 0xFF)
    {
        int type = seqPos[0];
        seqPos++;
        if (type == 0x51) // tempo, no length byte
        {
            seqTempo = (seqPos[0] << 16) | (seqPos[1] << 8) | seqPos[2];
            seqPos += 3;
            if (seqTempo == 0) seqTempo = 500000;
        }
        else if (type == 0x2F) // end of track
        {
            if (seqRepeat)
            {
                // seqExecute reads the first delta time after this event
                seqReleaseAll();
                seqResetChannels();
                seqRewind();
            }
            else
            {
                seqStopNow();
            }
        }
        else
        {
            seqStopNow(); // unknown meta event, length is not defined
        }
    }
    else
    {
        seqStopNow(); // system messages are not supported
    }
}

// Runs events until one with a non-zero delta time is found
void seqExecute()
{
    int guard = 0;
    while (seqState == 1)
    {
        guard++;
        if (guard > 2000)
        {
            seqStopNow(); // runaway zero-delta loop
            return;
        }

        seqEvent();
        if (seqState != 1) return;

        seqWait = seqReadDelta();
        if (seqWait > 0) return;
    }
}

// Advances the song by a number of ticks
void seqAdvance(uint ticks)
{
    while (seqState == 1)
    {
        if (seqWait == 0)
        {
            seqExecute();
        }
        else if (ticks == 0)
        {
            return;
        }
        else if (seqWait > ticks)
        {
            seqWait -= ticks;
            ticks = 0;
        }
        else
        {
            ticks -= seqWait;
            seqWait = 0;
        }
    }
}

// Initializes the sequencer. Call spuInit first.
void seqInit()
{
    seqState = 0;
    seqBank = 0;
    seqRepeat = 0;
    seqTempo = 500000;
    seqPpqn = 48;
    seqAcc = 0;
    seqSerial = 0;
    seqMasterVol = 127;
    seqLoopStart = 0;
    seqFrameUs = 16683;  // NTSC
    seqHblankUs64 = 4067;
    seqFirstVoice = 0;
    seqNumVoices = 16;
    spuReserveVoices(seqFirstVoice, seqNumVoices);
    for (int v = 0; v < 24; v++)
    {
        seqVoices[v].state = 0;
        seqVoices[v].fresh = 0;
    }
    seqResetChannels();
}

/**
 * Selects the SPU voices owned by the sequencer (default: 0..15).
 * Call it before seqPlay.
 */
void seqSetVoices(int first, int count)
{
    if (first < 0) first = 0;
    if (first > 23) first = 23;
    if (count < 1) count = 1;
    if (first + count > 24) count = 24 - first;
    seqFirstVoice = first;
    seqNumVoices = count;
    spuReserveVoices(first, count);
}

// Tells the sequencer the video standard, for seqUpdate and seqUpdateTimer
void seqSetPAL(int pal)
{
    if (pal)
    {
        seqFrameUs = 20000;
        seqHblankUs64 = 4097;
    }
    else
    {
        seqFrameUs = 16683;
        seqHblankUs64 = 4067;
    }
}

/**
 * Starts playing a SEQ file with instruments from a loaded VAB bank.
 * If repeat is non-zero, the song restarts when it ends.
 * Returns 1 on success, 0 if the data is not a valid SEQ file.
 */
int seqPlay(uchar* seq, int bank, int repeat)
{
    if (seq[0] != 'p' || seq[1] != 'Q' || seq[2] != 'E' || seq[3] != 'S') return 0;
    if (seq[4] != 0 || seq[5] != 0 || seq[6] != 0 || seq[7] != 1) return 0;
    if (bank < 0 || bank >= vabCount) return 0;

    seqReleaseAll();

    seqBank = bank;
    seqRepeat = repeat;
    seqPpqn = (seq[8] << 8) | seq[9];
    if (seqPpqn == 0) seqPpqn = 48;
    seqTempo = (seq[10] << 16) | (seq[11] << 8) | seq[12];
    if (seqTempo == 0) seqTempo = 500000;
    seqBase = seq + 15;
    seqAcc = 0;

    seqResetChannels();
    seqRewind();
    seqWait = seqReadDelta();
    seqState = 1;
    return 1;
}

// Stops the song, notes go through their release phase
void seqStop()
{
    if (seqState != 0) seqStopNow();
}

// Pauses the song. Sounding notes are released and not resumed.
void seqPause()
{
    if (seqState == 1)
    {
        seqReleaseAll();
        seqState = 2;
    }
}

void seqResume()
{
    if (seqState == 2) seqState = 1;
}

// 1 while a song is playing (not stopped, paused or finished)
int seqIsPlaying()
{
    return seqState == 1;
}

// Music volume, 0..127
void seqSetVolume(int vol)
{
    if (vol < 0) vol = 0;
    if (vol > 127) vol = 127;
    seqMasterVol = vol;
    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
    {
        int s = seqVoices[v].state;
        if (s == 1 || s == 3)
            seqApplyVolume(v);
    }
}

// Advances the sequencer by a number of microseconds
void seqStep(uint us)
{
    for (int v = seqFirstVoice; v < seqFirstVoice + seqNumVoices; v++)
        seqVoices[v].fresh = 0;

    if (seqState != 1) return;

    // Step in chunks so that us * ppqn can not overflow.
    // Runs at least once so that events which are already due are executed.
    do
    {
        uint chunk = us;
        if (chunk > 100000) chunk = 100000;
        us -= chunk;

        seqAcc += chunk * seqPpqn;
        uint ticks = seqAcc / seqTempo;
        seqAcc -= ticks * seqTempo;
        seqAdvance(ticks);
    }
    while (us > 0 && seqState == 1);
}

// Advances the sequencer by one frame. Call once per VBlank.
void seqUpdate()
{
    seqStep(seqFrameUs);
}

/**
 * Starts the timer used by seqUpdateTimer (root counter 1, counting
 * HBlanks). Call it right before the main loop.
 */
void seqTimerStart()
{
    *SEQ_T1_MODE = 0x0100; // clock source: HBlank, free running
    seqTimerLast = *SEQ_T1_COUNT;
}

/**
 * Like seqUpdate, but advances by the real time elapsed since the previous
 * call, measured with root counter 1. Keeps the tempo correct when a frame
 * takes longer than a VBlank. Must be called at least once every 4 seconds.
 */
void seqUpdateTimer()
{
    int now = *SEQ_T1_COUNT;
    uint d = (now - seqTimerLast) & 0xFFFF;
    seqTimerLast = now;
    seqStep((d * seqHblankUs64) >> 6);
}

#endif
