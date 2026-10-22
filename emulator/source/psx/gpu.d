module psx.gpu;

import std.stdio;
import std.format;
import std.algorithm: min;
import core.atomic;

import psx.dma;
import psx.rasterizer;

enum VRAM_WIDTH = 1024;
enum VRAM_HEIGHT = 512;

enum GpuTextureDepth
{
    T4Bit = 0,
    T8Bit = 1,
    T15Bit = 2
}

enum GpuField
{
    Top = 1,
    Bottom = 0
}

alias GpuHorizontalRes = ubyte;

/*
GpuHorizontalRes hResFromFields(ubyte hr1, ubyte hr2)
{
    return (hr2 & 1) | ((hr1 & 3) << 1);
}
*/

GpuHorizontalRes hResFromFields(ubyte hr1, ubyte hr2)
{
    return (hr1 & 3) | ((hr2 & 1) << 2);
}

uint hResToStatus(GpuHorizontalRes hres)
{
    return cast(uint)hres << 16;
}

enum GpuVerticalRes
{
    Y240Lines = 0,
    Y480Lines = 1
}

enum GpuVMode
{
    // NTSC: 480 @ 60 Hz
    NTSC = 0,
    
    // PAL: 576 @ 60 Hz
    PAL = 1
}

enum GpuDisplayDepth
{
    D15Bits = 0,
    D24Bits = 1
}

enum GpuDmaDirection
{
    Off = 0,
    Fifo = 1,
    CpuToGp0 = 2,
    VRamToCpu = 3
}

struct GpuCommandBuffer
{
    uint[12] buffer;
    ubyte len;
    
    void clear()
    {
        len = 0;
    }
    
    void pushWord(uint w)
    {
        if (len < 12)
        {
            buffer[len] = w;
            len++;
        }
        else
        {
            assert(0, "Command buffer overflow");
        }
    }
}

// Possible states of the GP0 command register
enum GpuGp0Mode
{
    // Default mode: handling commands
    Command,
    
    // Loading an image into VRAM
    ImageLoad
}

struct GpuPos
{
    short x;
    short y;
}

GpuPos posFromGp0(uint val)
{
    short x = cast(short)val;
    short y = cast(short)(val >> 16);
    return GpuPos(x, y);
}

struct GpuColor
{
    ubyte r;
    ubyte g;
    ubyte b;
}

GpuColor colorFromGp0(uint val)
{
    ubyte r = cast(ubyte)val;
    ubyte g = cast(ubyte)(val >> 8);
    ubyte b = cast(ubyte)(val >> 16);
    return GpuColor(r, g, b);
}

//version = DebugMsg;

struct PsxGpu
{
    ubyte[] vram;
    shared bool frameReady = false;
    shared bool frameLocked = false;
    
    // Texture page base X coordinate (4 bits, 64 byte increment)
    ubyte pageBaseX;
    
    // Texture page base Y coordinate (1 bit, 256 line increment)
    ubyte pageBaseY;
    
    //
    ubyte semiTransparency;
    
    // Texture page color depth
    GpuTextureDepth textureDepth;
    
    // Enable dithering from 24 to 15 bits RGB
    bool dithering;
    
    // Allow drawing to the display area
    bool drawToDisplay;
    
    // Force "mask" bit of the pixel to 1 when writing to VRAM
    bool forceSetMaskBit;
    
    // Don't draw to pixels which have the "mask" bit set
    bool preserveMaskedPixels;
    
    // Currently displayed field. For progressive output this is always Top
    GpuField field;
    
    // When true all textures as disabled
    bool textureDisable;
    
    // Video output horizontal resolution
    GpuHorizontalRes hres;
    
    // Video output vertical resolution
    GpuVerticalRes vres;
    
    // Video mode
    GpuVMode vmode;
    
    // Display depth. The GPU itself always draws 15 bit RGB,
    // 24 bit output must use external assets
    GpuDisplayDepth displayDepth;
    
    // Output interlaced video signal instead of progressive
    bool interlaced;
    
    // Disable the display
    bool displayDisabled;
    
    // True when the interrupt is active
    bool interrupt;
    
    // DMA request direction
    GpuDmaDirection dmaDirection;
    
    // Mirror textured rectangles along the x axis
    bool rectangleTextureXFlip;
    
    // Mirror textured rectangles along the y axis
    bool rectangleTextureYFlip;
    
    // Texture window x mask (8 pixel steps)
    ubyte textureWindowXMask;
    
    // Texture window y mask (8 pixel steps)
    ubyte textureWindowYMask;
    
    // Texture window x offset (8 pixel steps)
    ubyte textureWindowXOffset;
    
    // Texture window y offset (8 pixel steps)
    ubyte textureWindowYOffset;
    
    // Left-most column of drawing area
    ushort drawingAreaLeft;
    
    // Top-most line of drawing area
    ushort drawingAreaTop;
    
    // Right-most column of drawing area
    ushort drawingAreaRight;
    
    // Bottom-most line of drawing area
    ushort drawingAreaBottom;
    
    // Horizontal drawing offset applied to all vertex
    short drawingXOffset;
    
    // Vertical drawing offset applied to all vertex
    short drawingYOffset;
    
    // First column on the display area in VRAM
    ushort displayVRamXStart;
    
    // First line of the display area in VRAM
    ushort displayVRamYStart;
    
    // Display output horizontal start relative to HSYNC
    ushort displayHorizStart;
    
    // Display output horizontal end relative to HSYNC
    ushort displayHorizEnd;
    
    // Display output horizontal start relative to HSYNC
    ushort displayLineStart;
    
    // Display output last line relative to VSYNC
    ushort displayLineEnd;
    
    // Buffer containing the current GP0 command
    GpuCommandBuffer gp0_command;
    
    // Remaining words for the current GP0 command
    uint gp0_wordsRemaining;
    
    // Pointer to the function implementing the current GP0 command
    void function(PsxGpu*, uint) gp0_commandMethod;
    
    // Current mode of the GP0 register
    GpuGp0Mode gp0_mode;
    
    void init()
    {
        vram = new ubyte[VRAM_WIDTH * VRAM_HEIGHT * 4];
    }
    
    void reset()
    {
        pageBaseX = 0;
        pageBaseY = 0;
        semiTransparency = 0;
        textureDepth = GpuTextureDepth.T4Bit;
        dithering = false;
        drawToDisplay = false;
        forceSetMaskBit = false;
        preserveMaskedPixels = false;
        field = GpuField.Top;
        textureDisable = false;
        hres = hResFromFields(0, 0);
        vres = GpuVerticalRes.Y240Lines;
        vmode = GpuVMode.NTSC;
        displayDepth = GpuDisplayDepth.D15Bits;
        interlaced = false;
        displayDisabled = true;
        interrupt = false;
        dmaDirection = GpuDmaDirection.Off;
        
        gp0_command.clear();
        gp0_wordsRemaining = 0;
        gp0_commandMethod = null;
        gp0_mode = GpuGp0Mode.Command;
    }
    
    uint status()
    {
        debug writeln("GPU status");
        
        uint r = 0;
        r |= cast(uint)pageBaseX << 0;
        r |= cast(uint)pageBaseY << 4;
        r |= cast(uint)semiTransparency << 5;
        r |= cast(uint)textureDepth << 7;
        r |= cast(uint)dithering << 9;
        r |= cast(uint)drawToDisplay << 10;
        r |= cast(uint)forceSetMaskBit << 11;
        r |= cast(uint)preserveMaskedPixels << 12;
        r |= cast(uint)field << 13;
        // Bit 14 not supported
        r |= cast(uint)textureDisable << 15;
        r |= hResToStatus(hres);
        // Temporary hack: f we don't emulate bit 31 correctly,
        // setting vres to 1 locks the BIOS:
        //r |= cast(uint)vres << 19;
        r |= cast(uint)vmode << 20;
        r |= cast(uint)displayDepth << 21;
        r |= cast(uint)interlaced << 22;
        r |= cast(uint)displayDisabled << 23;
        r |= cast(uint)interrupt << 24;
        
        // For now we pretend that the GPU is always ready:
        // Ready to receive command
        r |= 1 << 26;
        // Ready to send VRAM to CPU
        r |= 1 << 27;
        // Ready to receive DMA block
        r |= 1 << 28;
        
        r |= cast(uint)dmaDirection << 29;
        
        // Bit 31 should change depending on the currently drawn
        // line (whether it's even, odd or in the vblack apparently).
        // Let's not bother with it now.
        r |= 0 << 31;
        
        uint dmaRequest;
        if (dmaDirection == GpuDmaDirection.Off)
            dmaRequest = 0;
        else if (dmaDirection == GpuDmaDirection.Fifo)
            dmaRequest = 1;
        else if (dmaDirection == GpuDmaDirection.CpuToGp0)
            dmaRequest = (r >> 28) & 1;
        else if (dmaDirection == GpuDmaDirection.VRamToCpu)
            dmaRequest = (r >> 27) & 1;
        
        r |= dmaRequest << 25;
        
        return r;
    }
    
    uint read()
    {
        version(DebugMsg) writefln("GPUREAD: unimplemented");
        return 0;
    }
    
    // Write to the GP0 command register
    void gp0(uint val)
    {
        if (gp0_wordsRemaining == 0)
        {
            uint opcode = (val >> 24) & 0xff;
            
            uint commandLength;
            void function(PsxGpu*, uint) commandMethod;
            
            switch (opcode)
            {
                case 0x00:
                    commandLength = 1;
                    commandMethod = &gp0_nop;
                    version(DebugMsg) writefln("gp0_nop (0x%0.8x)", val);
                    break;
                case 0x01:
                    commandLength = 1;
                    commandMethod = &gp0_clear_cache;
                    version(DebugMsg) writefln("gp0_clear_cache (0x%0.8x)", val);
                    break;
                case 0x02:
                    commandLength = 3;
                    commandMethod = &gp0_fill_rect_vram;
                    version(DebugMsg) writefln("gp0_fill_rect_vram (0x%0.8x)", val);
                    break;
                case 0x28:
                    commandLength = 5;
                    commandMethod = &gp0_quad_mono_opaque;
                    version(DebugMsg) writefln("gp0_quad_mono_opaque (0x%0.8x)", val);
                    break;
                case 0x2c:
                    commandLength = 9;
                    commandMethod = &gp0_quad_tex_blend_opaque;
                    version(DebugMsg) writefln("gp0_quad_tex_blend_opaque (0x%0.8x)", val);
                    break;
                case 0x30:
                    commandLength = 6;
                    commandMethod = &gp0_tri_shaded_opaque;
                    version(DebugMsg) writefln("gp0_tri_shaded_opaque (0x%0.8x)", val);
                    break;
                case 0x38:
                    commandLength = 8;
                    commandMethod = &gp0_quad_shaded_opaque;
                    version(DebugMsg) writefln("gp0_quad_shaded_opaque (0x%0.8x)", val);
                    break;
                case 0xa0:
                    commandLength = 3;
                    commandMethod = &gp0_image_load;
                    version(DebugMsg) writefln("gp0_image_load (0x%0.8x)", val);
                    break;
                case 0xe1:
                    commandLength = 1;
                    commandMethod = &gp0_draw_mode;
                    version(DebugMsg) writefln("gp0_draw_mode (0x%0.8x)", val);
                    break;
                case 0xe2:
                    commandLength = 1;
                    commandMethod = &gp0_texture_window;
                    version(DebugMsg) writefln("gp0_texture_window (0x%0.8x)", val);
                    break;
                case 0xe3:
                    commandLength = 1;
                    commandMethod = &gp0_drawing_area_top_left;
                    version(DebugMsg) writefln("gp0_drawing_area_top_left (0x%0.8x)", val);
                    break;
                case 0xe4:
                    commandLength = 1;
                    commandMethod = &gp0_drawing_area_bottom_right;
                    version(DebugMsg) writefln("gp0_drawing_area_bottom_right (0x%0.8x)", val);
                    break;
                case 0xe5:
                    commandLength = 1;
                    commandMethod = &gp0_drawing_offset;
                    version(DebugMsg) writefln("gp0_drawing_offset (0x%0.8x)", val);
                    break;
                case 0xe6:
                    commandLength = 1;
                    commandMethod = &gp0_mask_bit_setting;
                    version(DebugMsg) writefln("gp0_mask_bit_setting (0x%0.8x)", val);
                    break;
                case 0xc0:
                    commandLength = 3;
                    commandMethod = &gp0_image_store;
                    version(DebugMsg) writefln("gp0_image_store (0x%0.8x)", val);
                    break;
                default:
                    commandLength = 1;
                    commandMethod = null;
                    version(DebugMsg) writeln(format("unhandled GP0 command opcode 0x%0.2x", opcode));
                    break;
            }
            
            gp0_wordsRemaining = commandLength;
            gp0_commandMethod = commandMethod;
            
            gp0_command.clear();
        }
        
        gp0_wordsRemaining -= 1;
        
        if (gp0_mode == GpuGp0Mode.Command)
        {
            gp0_command.pushWord(val);
            
            if (gp0_wordsRemaining == 0 && gp0_commandMethod !is null)
            {
                gp0_commandMethod(&this, val);
                gp0_command.clear();
            }
        }
        else if (gp0_mode == GpuGp0Mode.ImageLoad)
        {
            // TODO
            debug writeln("-- GPU placeholder: copy pixel data to VRAM --");
            
            if (gp0_wordsRemaining == 0)
            {
                gp0_mode = GpuGp0Mode.Command;
                gp0_command.clear();
            }
        }
    }
    
    void gp1(uint val)
    {
        version(DebugMsg) writefln("GP1 command: 0x%0.8x", val);
        
        uint opcode = (val >> 24) & 0xff;
        switch (opcode)
        {
            case 0x00:
                gp1_reset(val);
                break;
            case 0x01:
                gp1_reset_command_buffer(val);
                break;
            case 0x02:
                gp1_acknowledge_irq(val);
                break;
            case 0x03:
                gp1_display_enable(val);
                break;
            case 0x04:
                gp1_dma_direction(val);
                break;
            case 0x05:
                gp1_display_vram_start(val);
                break;
            case 0x06:
                gp1_display_horizontal_range(val);
                break;
            case 0x07:
                gp1_display_vertical_range(val);
                break;
            case 0x08:
                gp1_display_mode(val);
                break;
            default:
                assert(0, format("unhandled GP1 command opcode 0x%0.2x", opcode));
                break;
        }
    }
    
    void gp1_reset(uint val)
    {
        interrupt = false;
        
        pageBaseX = 0;
        pageBaseY = 0;
        semiTransparency = 0;
        textureDepth = GpuTextureDepth.T4Bit;
        textureWindowXMask = 0;
        textureWindowYMask = 0;
        textureWindowXOffset = 0;
        textureWindowYOffset = 0;
        dithering = false;
        drawToDisplay = false;
        textureDisable = false;
        rectangleTextureXFlip = false;
        rectangleTextureYFlip = false;
        drawingAreaLeft = 0;
        drawingAreaTop = 0;
        drawingAreaRight = 0;
        drawingAreaBottom = 0;
        drawingXOffset = 0;
        drawingYOffset = 0;
        forceSetMaskBit = false;
        preserveMaskedPixels = false;
        
        dmaDirection = GpuDmaDirection.Off;
        
        displayDisabled = true;
        displayVRamXStart = 0;
        displayVRamYStart = 0;
        hres = hResFromFields(0, 0);
        vres = GpuVerticalRes.Y240Lines;
        
        vmode = GpuVMode.NTSC;
        interlaced = false;
        displayHorizStart = 0x200;
        displayHorizEnd = 0xc00;
        displayLineStart = 0x10;
        displayLineEnd = 0x100;
        displayDepth = GpuDisplayDepth.D15Bits;
        
        gp1_reset_command_buffer(val);
        
        // Should also invalidate GPU cache if we ever implement it
    }
    
    void gp1_reset_command_buffer(uint val)
    {
        gp0_command.clear();
        gp0_wordsRemaining = 0;
        gp0_mode = GpuGp0Mode.Command;
        
        // Should also clear the command FIFO when we implement it
    }
    
    void gp1_acknowledge_irq(uint val)
    {
        interrupt = false;
    }
    
    void gp1_display_enable(uint val)
    {
        displayDisabled = (val & 1) != 0;
    }
    
    void gp1_dma_direction(uint val)
    {
        switch(val & 3)
        {
            case 0:
                dmaDirection = GpuDmaDirection.Off;
                break;
            case 1:
                dmaDirection = GpuDmaDirection.Fifo;
                break;
            case 2:
                dmaDirection = GpuDmaDirection.CpuToGp0;
                break;
            case 3:
                dmaDirection = GpuDmaDirection.VRamToCpu;
                break;
            default:
                // Unreachable
                break;
        }
    }
    
    void gp1_display_vram_start(uint val)
    {
        displayVRamXStart = cast(ushort)(val & 0x3fe);
        displayVRamYStart = cast(ushort)((val >> 10) & 0x1ff);
    }
    
    void gp1_display_horizontal_range(uint val)
    {
        displayHorizStart = cast(ushort)(val & 0xfff);
        displayHorizEnd = cast(ushort)((val >> 12) & 0xfff);
    }
    
    void gp1_display_vertical_range(uint val)
    {
        displayLineStart = cast(ushort)(val & 0x3ff);
        displayLineEnd = cast(ushort)((val >> 10) & 0x3ff);
    }
    
    void gp1_display_mode(uint val)
    {
        ubyte hr1 = cast(ubyte)(val & 3);
        ubyte hr2 = cast(ubyte)((val >> 6) & 1);
        
        hres = hResFromFields(hr1, hr2);
        
        if ((val & 0x4) != 0)
            vres = GpuVerticalRes.Y480Lines;
        else
            vres = GpuVerticalRes.Y240Lines;
        
        if ((val & 0x8) != 0)
            vmode = GpuVMode.PAL;
        else
            vmode = GpuVMode.NTSC;
        
        if ((val & 0x10) != 0)
            displayDepth = GpuDisplayDepth.D15Bits;
        else
            displayDepth = GpuDisplayDepth.D24Bits;
        
        interlaced = (val & 0x20) != 0;
        
        if ((val & 0x80) != 0)
            assert(0, format("unsupported display node 0x%0.8x", val));
    }
}

void gp0_nop(PsxGpu* gpu, uint val)
{
    // NOP
}

void gp0_clear_cache(PsxGpu* gpu, uint val)
{
    debug writeln("-- GPU placeholder: gp0_clear_cache --");
}

void gp0_fill_rect_vram(PsxGpu* gpu, uint val)
{
    uint color = gpu.gp0_command.buffer[0];
    uint xy = gpu.gp0_command.buffer[1];
    uint wh = gpu.gp0_command.buffer[2];

    uint r = color & 0xff;
    uint g = (color >> 8) & 0xff;
    uint b = (color >> 16) & 0xff;

    int x = cast(int)(xy & 0x3ff);
    int y = cast(int)((xy >> 16) & 0x1ff);

    int w = cast(int)(wh & 0xffff);
    int h = cast(int)(wh >> 16);

    // Quick fill operates in 16-pixel horizontal units.
    x &= ~15;
    w = (w + 15) & ~15;

    if (w == 0 || h == 0)
        return;

    // Clip the rectangle to VRAM bounds.
    if (x >= VRAM_WIDTH || y >= VRAM_HEIGHT)
        return;

    w = cast(int)min(w, VRAM_WIDTH - x);
    h = cast(int)min(h, VRAM_HEIGHT - y);

    foreach (int dy; 0 .. h)
    {
        foreach (int dx; 0 .. w)
        {
            size_t offset =
                (cast(size_t)(y + dy) * VRAM_WIDTH + x + dx) * 4;

            gpu.vram[offset + 0] = cast(ubyte)r;
            gpu.vram[offset + 1] = cast(ubyte)g;
            gpu.vram[offset + 2] = cast(ubyte)b;
            gpu.vram[offset + 3] = 0;
        }
    }
}

void gp0_quad_mono_opaque(PsxGpu* gpu, uint val)
{
    GpuPos p1 = posFromGp0(gpu.gp0_command.buffer[1]);
    GpuPos p2 = posFromGp0(gpu.gp0_command.buffer[2]);
    GpuPos p3 = posFromGp0(gpu.gp0_command.buffer[3]);
    GpuPos p4 = posFromGp0(gpu.gp0_command.buffer[4]);

    GpuColor c = colorFromGp0(gpu.gp0_command.buffer[0]);

    gpu.drawTriangle(p1, p2, p3, c, c, c);
    gpu.drawTriangle(p2, p3, p4, c, c, c);
}

void gp0_quad_tex_blend_opaque(PsxGpu* gpu, uint val)
{
    GpuPos p1 = posFromGp0(gpu.gp0_command.buffer[1]);
    GpuPos p2 = posFromGp0(gpu.gp0_command.buffer[3]);
    GpuPos p3 = posFromGp0(gpu.gp0_command.buffer[5]);
    GpuPos p4 = posFromGp0(gpu.gp0_command.buffer[7]);

    GpuColor c = GpuColor(128, 128, 128);

    gpu.drawTriangle(p1, p2, p3, c, c, c);
    gpu.drawTriangle(p2, p3, p4, c, c, c);
}

void gp0_quad_shaded_opaque(PsxGpu* gpu, uint val)
{
    GpuPos p1 = posFromGp0(gpu.gp0_command.buffer[1]);
    GpuPos p2 = posFromGp0(gpu.gp0_command.buffer[3]);
    GpuPos p3 = posFromGp0(gpu.gp0_command.buffer[5]);
    GpuPos p4 = posFromGp0(gpu.gp0_command.buffer[7]);

    GpuColor c1 = colorFromGp0(gpu.gp0_command.buffer[0]);
    GpuColor c2 = colorFromGp0(gpu.gp0_command.buffer[2]);
    GpuColor c3 = colorFromGp0(gpu.gp0_command.buffer[4]);
    GpuColor c4 = colorFromGp0(gpu.gp0_command.buffer[6]);

    gpu.drawTriangle(p1, p2, p3, c1, c2, c3);
    gpu.drawTriangle(p2, p3, p4, c2, c3, c4);
}

void gp0_tri_shaded_opaque(PsxGpu* gpu, uint val)
{
    GpuPos p1 = posFromGp0(gpu.gp0_command.buffer[1]);
    GpuPos p2 = posFromGp0(gpu.gp0_command.buffer[3]);
    GpuPos p3 = posFromGp0(gpu.gp0_command.buffer[5]);
    
    GpuColor c1 = colorFromGp0(gpu.gp0_command.buffer[0]);
    GpuColor c2 = colorFromGp0(gpu.gp0_command.buffer[2]);
    GpuColor c3 = colorFromGp0(gpu.gp0_command.buffer[4]);
    
    gpu.drawTriangle(p1, p2, p3, c1, c2, c3);
}

void gp0_image_load(PsxGpu* gpu, uint val)
{
    // Parameter 2 contains the image resolution
    uint res = gpu.gp0_command.buffer[2];
    
    uint width = res & 0xffff;
    uint height = res >> 16;
    
    // Size of the image in 16-bit pixels
    uint imgSize = width * height;
    
    // If we have an odd number of pixels we must round up
    // since we transfer 32 bits at a time.
    // There'll be 16 bits of padding in the last word
    imgSize = (imgSize + 1) & (~1);
    
    // Store number of words expected for this image
    gpu.gp0_wordsRemaining = imgSize / 2;
    
    // Put the GP0 state machine in ImageLoad mode
    gpu.gp0_mode = GpuGp0Mode.ImageLoad;
}

void gp0_image_store(PsxGpu* gpu, uint val)
{
    // Parameter 2 contains the image resolution
    uint res = gpu.gp0_command.buffer[2];
    
    uint width = res & 0xffff;
    uint height = res >> 16;
    
    debug writeln("-- GPU placeholder: gp0_image_store --");
}

void gp0_draw_mode(PsxGpu* gpu, uint val)
{
    gpu.pageBaseX = cast(ubyte)(val & 0xf);
    gpu.pageBaseY = cast(ubyte)((val >> 4) & 1);
    gpu.semiTransparency = cast(ubyte)((val >> 5) & 3);
    
    uint n = (val >> 7) & 3;
    switch (n)
    {
        case 0:
            gpu.textureDepth = GpuTextureDepth.T4Bit;
            break;
        case 1:
            gpu.textureDepth = GpuTextureDepth.T8Bit;
            break;
        case 2:
            gpu.textureDepth = GpuTextureDepth.T15Bit;
            break;
        default:
            assert(0, format("unhandled texture depth %s", n));
            break;
    }
    
    gpu.dithering = ((val >> 9) & 1) != 0;
    gpu.drawToDisplay = ((val >> 10) & 1) != 0;
    gpu.textureDisable = ((val >> 11) & 1) != 0;
    gpu.rectangleTextureXFlip = ((val >> 12) & 1) != 0;
    gpu.rectangleTextureYFlip = ((val >> 13) & 1) != 0;
}

void gp0_texture_window(PsxGpu* gpu, uint val)
{
    gpu.textureWindowXMask = cast(ubyte)(val & 0x1f);
    gpu.textureWindowYMask = cast(ubyte)((val >> 5) & 0x1f);
    gpu.textureWindowXOffset = cast(ubyte)((val >> 10) & 0x1f);
    gpu.textureWindowYOffset = cast(ubyte)((val >> 15) & 0x1f);
}

void gp0_drawing_area_top_left(PsxGpu* gpu, uint val)
{
    gpu.drawingAreaTop = cast(ushort)((val >> 10) & 0x3ff);
    gpu.drawingAreaLeft = cast(ushort)(val & 0x3ff);
}

void gp0_drawing_area_bottom_right(PsxGpu* gpu, uint val)
{
    gpu.drawingAreaBottom = cast(ushort)((val >> 10) & 0x3ff);
    gpu.drawingAreaRight = cast(ushort)(val & 0x3ff);
}

void gp0_drawing_offset(PsxGpu* gpu, uint val)
{
    // Release VRAM for reading
    atomicStore(gpu.frameReady, true);
    atomicStore(gpu.frameLocked, true);
    
    while (atomicLoad(gpu.frameLocked))
    {
        // busy-wait for the display to read VRAM
    }
    
    ushort x = cast(ushort)(val & 0x7ff);
    ushort y = cast(ushort)((val >> 11) & 0x7ff);
    
    // Values are 11 bit two's complement signed values,
    // we need to shift the value to 16 bits to force sign extension
    gpu.drawingXOffset = cast(short)(x << 5) >> 5;
    gpu.drawingYOffset = cast(short)(y << 5) >> 5;
}

void gp0_mask_bit_setting(PsxGpu* gpu, uint val)
{
    gpu.forceSetMaskBit = (val & 1) != 0;
    gpu.preserveMaskedPixels = (val & 2) != 0;
}
