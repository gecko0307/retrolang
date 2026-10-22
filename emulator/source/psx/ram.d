module psx.ram;

enum PSX_RAM_SIZE = 2048 * 1024;
enum PSX_BIOS_SIZE = 512 * 1024;
enum PSX_BIOS_OFFSET_KSEG1 = 0xA0000000 - 0x1FC00000;

struct PsxRam
{
    ubyte[] data;

    void init(size_t size)
    {
        data = new ubyte[size];
    }

    uint read32(uint offset)
    {
        uint b0 = data[offset + 0];
        uint b1 = data[offset + 1];
        uint b2 = data[offset + 2];
        uint b3 = data[offset + 3];

        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    }

    void write32(uint offset, uint val)
    {
        ubyte b0 = cast(ubyte)val;
        ubyte b1 = cast(ubyte)(val >> 8);
        ubyte b2 = cast(ubyte)(val >> 16);
        ubyte b3 = cast(ubyte)(val >> 24);

        data[offset + 0] = b0;
        data[offset + 1] = b1;
        data[offset + 2] = b2;
        data[offset + 3] = b3;
    }

    ushort read16(uint offset)
    {
        ushort b0 = cast(ushort)data[offset + 0];
        ushort b1 = cast(ushort)data[offset + 1];

        return cast(ushort)(b0 | (b1 << 8));
    }

    void write16(uint offset, ushort val)
    {
        ubyte b0 = cast(ubyte)val;
        ubyte b1 = cast(ubyte)(val >> 8);

        data[offset + 0] = b0;
        data[offset + 1] = b1;
    }

    void write8(uint offset, ubyte val)
    {
        data[offset] = val;
    }

    ubyte read8(uint offset)
    {
        return data[offset];
    }
}
