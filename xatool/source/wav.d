module wav;

import std.stdio;
import std.file: read;
import std.exception: enforce;
import std.format: format;

struct WavData
{
    uint sampleRate;
    ushort channels;
    ushort bitsPerSample;
    short[] samples; // Interleaved PCM, signed 16-bit.
}

uint readU32(const(ubyte)[] data, size_t offset)
{
    enforce(offset + 4 <= data.length, "Unexpected end of WAV");
    return cast(uint)data[offset]
        | (cast(uint)data[offset + 1] << 8)
        | (cast(uint)data[offset + 2] << 16)
        | (cast(uint)data[offset + 3] << 24);
}

ushort readU16(const(ubyte)[] data, size_t offset)
{
    enforce(offset + 2 <= data.length, "Unexpected end of WAV");
    return cast(ushort)(data[offset] | (data[offset + 1] << 8));
}

bool tagEquals(const(ubyte)[] data, size_t offset, string tag)
{
    if (offset + tag.length > data.length)
        return false;

    foreach (i, c; tag)
        if (data[offset + i] != c)
            return false;

    return true;
}

WavData readWav(string path)
{
    auto raw = cast(const(ubyte)[]) read(path);

    enforce(raw.length >= 12, "WAV file is too small");
    enforce(tagEquals(raw, 0, "RIFF"), "Not a RIFF file");
    enforce(tagEquals(raw, 8, "WAVE"), "Not a WAVE file");

    bool haveFmt, haveData;
    ushort formatTag, channels, bits, blockAlign;
    uint sampleRate;
    size_t dataOffset, dataSize;

    size_t pos = 12;

    while (pos + 8 <= raw.length)
    {
        uint chunkSize = readU32(raw, pos + 4);
        size_t start = pos + 8;

        enforce(chunkSize <= raw.length - start,
            "WAV chunk extends beyond end of file");

        if (tagEquals(raw, pos, "fmt "))
        {
            enforce(chunkSize >= 16, "Invalid WAV fmt chunk");

            formatTag = readU16(raw, start);
            channels = readU16(raw, start + 2);
            sampleRate = readU32(raw, start + 4);
            blockAlign = readU16(raw, start + 12);
            bits = readU16(raw, start + 14);
            haveFmt = true;
        }
        else if (tagEquals(raw, pos, "data"))
        {
            dataOffset = start;
            dataSize = chunkSize;
            haveData = true;
        }

        // RIFF chunks are padded to an even byte boundary.
        pos = start + chunkSize + (chunkSize & 1);
    }

    enforce(haveFmt, "WAV fmt chunk not found");
    enforce(haveData, "WAV data chunk not found");
    enforce(formatTag == 1, "Only uncompressed PCM WAV is supported");
    enforce(channels == 1 || channels == 2,
        "Only mono and stereo WAV are supported");
    enforce(bits == 8 || bits == 16,
        "Only 8-bit and 16-bit PCM are supported");
    enforce(sampleRate != 0, "Invalid sample rate");
    enforce(blockAlign == channels * (bits / 8),
        "Invalid WAV block alignment");
    enforce(dataSize % blockAlign == 0,
        "Incomplete PCM sample frame");

    WavData wav;
    wav.sampleRate = sampleRate;
    wav.channels = channels;
    wav.bitsPerSample = bits;

    size_t count = dataSize / (bits / 8);
    wav.samples.length = count;

    foreach (i; 0 .. count)
    {
        size_t offset = dataOffset + i * (bits / 8);

        if (bits == 8)
        {
            // WAV 8-bit PCM is unsigned.
            wav.samples[i] =
                cast(short)((cast(int)raw[offset] - 128) << 8);
        }
        else
        {
            // WAV 16-bit PCM is signed little-endian.
            wav.samples[i] =
                cast(short)readU16(raw, offset);
        }
    }

    return wav;
}
