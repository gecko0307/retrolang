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
 * Gamepad driver.
 */

#define JOY_BASE 0x1F800000
#define JOY_DATA 0x1040
#define JOY_STAT 0x1044
#define JOY_MODE 0x1048
#define JOY_CTRL 0x104A
#define JOY_BAUD 0x104E

#define PAD_ID_DIGITAL      0x41
#define PAD_ID_ANALOG_GREEN 0x53
#define PAD_ID_ANALOG_RED   0x73

#define PAD_L2       0x0001
#define PAD_R2       0x0002
#define PAD_L1       0x0004
#define PAD_R1       0x0008
#define PAD_TRIANGLE 0x0010
#define PAD_CIRCLE   0x0020
#define PAD_CROSS    0x0040
#define PAD_SQUARE   0x0080
#define PAD_SELECT   0x0100
#define PAD_START    0x0800
#define PAD_UP       0x1000
#define PAD_RIGHT    0x2000
#define PAD_DOWN     0x4000
#define PAD_LEFT     0x8000

#define STICK_ON  64    // |value - 128| above this: pressed
#define STICK_OFF 40    // below this: released

#if import

/*
 * SIO
 */

// TODO: make intrinsics
void sioSet8(int offset, char value)
{
    char* addr = JOY_BASE | (offset & 0xFFFF);
    *addr = value;
}

void sioSet16(int offset, short value)
{
    short* addr = JOY_BASE | (offset & 0xFFFF);
    *addr = value;
}

uchar sioGet8(int offset)
{
    uchar* addr = JOY_BASE | (offset & 0xFFFF);
    return *addr;
}

ushort sioGet16(int offset)
{
    ushort* addr = JOY_BASE | (offset & 0xFFFF);
    return *addr;
}

int _cmd_enter[9];
int _cmd_mode[9];
int _cmd_exit[9];

void setCmd(int *c, int cmd, int a, int b)
{
    c[0] = 0x01;
    c[1] = cmd;
    c[2] = 0x00;
    c[3] = a;
    c[4] = b;
    c[5] = 0;
    c[6] = 0;
    c[7] = 0;
    c[8] = 0;
}

int sioXfer(int b)
{
    sioSet8(JOY_DATA, b);                     // TX
    int t = 0;
    while ((sioGet16(JOY_STAT) & 2) == 0 && t < 100000)
        // wait for RX byte
        t++;
    if ((sioGet16(JOY_STAT) & 2) == 0)
    {
        return -1;
    }
    int r = sioGet8(JOY_DATA);                // RX
    for (int d = 0; d < 100; d++) { }         // let the pad ACK before the next byte
    return r;
}

void sioSend(int *c)
{
    sioSet16(JOY_CTRL, 0x0003);               // TXEN + DTR (select port 1)
    for (int i = 0; i < 9; i++)
    {
        int r = sioXfer(c[i]);
        if (r < 0) break;
        c[i] = r;                             // reply overwrites the sent byte
    }
    sioSet16(JOY_CTRL, 0x0000);               // deselect
    for (int d = 0; d < 20000; d++) { }       // gap between commands
}

/*
 * Buffered pad API
 */

/*
 * Byte 0 - status (0x00 = OK, 0xFF = no pad)
 * Byte 1 - pad ID: high nibble = type, low nibble = number of halfwords of data
 * Bytes 2-3 - buttons, active low
 * Byte 4 - right stick X
 * Byte 5 - right stick Y
 * Byte 6 - left stick X
 * Byte 7 - left stick Y
 */
int _pad_buf1[9];
int _pad_buf2[9];
int _pad_data;

int _pad_rx, _pad_ry, _pad_lx, _pad_ly;
int _pad_id;

int _stick_dirs;        // PAD_LEFT/RIGHT/UP/DOWN bits derived from the left stick

void padInit()
{
    _pad_buf1[0] = -1; // status byte 0xFF = "not updated yet"
    _pad_buf2[0] = -1;
    _pad_data = -1;

    bios_b(0x12, _pad_buf1, 34, _pad_buf2, 34); // InitPad2
    _pad_buf1[0] = -1;
    bios_b(0x13, 0, 0, 0, 0); // StartPad2
    bios_b(0x14, 0, 0, 0, 0); // StopPad2
    sioSet16(JOY_MODE, 0x000D);
    sioSet16(JOY_BAUD, 0x0088);
    setCmd(_cmd_enter, 0x43, 0x01, 0x00); // enter config
    setCmd(_cmd_mode,  0x44, 0x01, 0x03); // analog + lock
    setCmd(_cmd_exit,  0x43, 0x00, 0x5A); // exit config
    sioSend(_cmd_enter);
    sioSend(_cmd_mode);
    sioSend(_cmd_exit);
    _pad_buf1[0] = -1;
    bios_b(0x13, 0, 0, 0, 0); // StartPad2
}

int padWaitSync()
{
    int tries = 0;
    int w = _pad_buf1[0];
    while (((w & 0xFF) != 0 || ((w >> 8) & 0xFF) == 0) && tries < 1000000)
    {
        w = _pad_buf1[0];
        tries++;
    }
    if (tries >= 1000000) return 0;

    int w2 = _pad_buf1[1];      // read both words right away
    _pad_buf1[0] = -1;          // invalidate: the next call waits for the next VBlank

    _pad_id = (w >> 8) & 0xFF;

    int b2 = (w >> 16) & 0xFF;
    int b3 = (w >> 24) & 0xFF;
    _pad_data = (b2 << 8) | b3;

    if ((_pad_id & 0x0F) >= 3)
    {
        _pad_rx = w2 & 0xFF;
        _pad_ry = (w2 >> 8) & 0xFF;
        _pad_lx = (w2 >> 16) & 0xFF;
        _pad_ly = (w2 >> 24) & 0xFF;
    }
    else
    {
        _pad_rx = 0x80;
        _pad_ry = 0x80;
        _pad_lx = 0x80;
        _pad_ly = 0x80;
    }
    
    int bits = 0;
    bits = bits | stickAxis(_pad_lx, PAD_LEFT, PAD_RIGHT);
    bits = bits | stickAxis(_pad_ly, PAD_UP,   PAD_DOWN);
    _stick_dirs = bits;
    
    return 1;
}

int padRead1()
{
    return ((~_pad_data) & 0xFFFF) | _stick_dirs;
}

int stickAxis(int v, int neg, int pos)
{
    int s = v - 128;
    int bits = 0;

    // Keep the previous state in the hysteresis band
    if (_stick_dirs & neg) bits = bits | neg;
    if (_stick_dirs & pos) bits = bits | pos;

    if (s < -STICK_ON)       bits = (bits | neg) & ~pos;
    else if (s > STICK_ON)   bits = (bits | pos) & ~neg;
    else
    {
        if (s > -STICK_OFF) bits = bits & ~neg;
        if (s <  STICK_OFF) bits = bits & ~pos;
    }
    return bits;
}

// Signed -128..127
int padAxis(int v)
{
    int s = v - 128;
    if (s > -24 && s < 24) // dead zone
        return 0;
    return s;
}

#endif
