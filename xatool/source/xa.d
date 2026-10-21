module xa;

import std.file: read;
import std.format: format;
import std.exception: enforce;
import wav;

enum SECTOR = 2336;
enum FILLER_CHANNEL = 31;

struct Stream
{
    string path;
    ubyte[] data;

    @property size_t length() const
    {
        return data.length / SECTOR;
    }

    ubyte[] sector(size_t index)
    {
        return data[index * SECTOR .. (index + 1) * SECTOR];
    }
}

Stream readSectors(string path)
{
    auto data = cast(ubyte[]) read(path);

    enforce(data.length != 0,
        format("%s: empty input file", path));

    enforce(data.length % SECTOR == 0,
        format("%s: size %s is not a multiple of %s "
            ~ "(encode with -t xa, not xacd)",
            path, data.length, SECTOR));

    return Stream(path, data);
}

enum XA_RATE = 37800;
enum XA_CHANNELS = 2;
enum XA_CODING_INFO = 0x01; // stereo, 37800 Hz, 4-bit
enum XA_GROUP_SIZE = 128;
enum XA_GROUPS_PER_SECTOR = 18;
enum XA_SAMPLES_PER_UNIT = 28;
enum XA_FRAMES_PER_GROUP = 112;
enum XA_FRAMES_PER_SECTOR = XA_GROUPS_PER_SECTOR * XA_FRAMES_PER_GROUP;

immutable int[2][4] XA_FILTERS = [
    [0, 0],
    [60, 0],
    [115, -52],
    [98, -55]
];

struct XaState
{
    int h1;
    int h2;
}

struct XaEncodedUnit
{
    int shift;
    int filter;
    ubyte[28] nibbles;
    int h1;
    int h2;
    long error;
}

int xaFloorDiv(int value, int divisor)
{
    int quotient = value / divisor;
    return value < 0 && value % divisor != 0
        ? quotient - 1
        : quotient;
}

int xaClamp16(int value)
{
    return value < -32768 ? -32768
        : value > 32767 ? 32767
        : value;
}

XaEncodedUnit encodeXaUnit(
    const(short)[] samples,
    int initialH1,
    int initialH2)
{
    assert(samples.length == XA_SAMPLES_PER_UNIT);

    bool haveBest;
    XaEncodedUnit best;

    foreach (filterIndex, filter; XA_FILTERS)
    {
        int p1 = initialH1;
        int p2 = initialH2;
        int maximum = 0;

        // Estimate the residual range using the original samples,
        // matching the WAV2VAG algorithm.
        foreach (sample; samples)
        {
            int prediction =
                (p1 * filter[0] + p2 * filter[1] + 32) >> 6;

            int difference = cast(int)sample - prediction;
            int magnitude = difference < 0
                ? -difference
                : difference;

            if (magnitude > maximum)
                maximum = magnitude;

            p2 = p1;
            p1 = sample;
        }

        int shift = 12;

        while (shift > 0 &&
            maximum > 7 * (1 << (12 - shift)))
        {
            --shift;
        }

        int[2] shifts = [
            shift,
            shift > 0 ? shift - 1 : shift
        ];

        size_t shiftCount = shift > 0 ? 2 : 1;

        foreach (candidateShift; shifts[0 .. shiftCount])
        {
            int step = 1 << (12 - candidateShift);
            int half = step >> 1;

            p1 = initialH1;
            p2 = initialH2;

            XaEncodedUnit candidate;
            candidate.shift = candidateShift;
            candidate.filter = cast(int)filterIndex;

            foreach (i, sample; samples)
            {
                int prediction =
                    (p1 * filter[0] + p2 * filter[1] + 32) >> 6;

                int nibble = xaFloorDiv(
                    cast(int)sample - prediction + half,
                    step);

                if (nibble < -8)
                    nibble = -8;
                else if (nibble > 7)
                    nibble = 7;

                int reconstructed = xaClamp16(
                    nibble * step + prediction);

                long residual = cast(int)sample - reconstructed;
                candidate.error += residual * residual;

                candidate.nibbles[i] =
                    cast(ubyte)(nibble & 0x0F);

                p2 = p1;
                p1 = reconstructed;
            }

            candidate.h1 = p1;
            candidate.h2 = p2;

            if (!haveBest || candidate.error < best.error)
            {
                best = candidate;
                haveBest = true;
            }
        }
    }

    return best;
}

void encodeXaGroup(
    const(short)[] pcm,
    size_t firstFrame,
    ubyte[] dst,
    ref XaState[2] states)
{
    assert(dst.length >= XA_GROUP_SIZE);

    ubyte[8] params;
    ubyte[8][28] encoded;

    foreach (unit; 0 .. 8)
    {
        short[28] unitSamples;

        size_t channel = unit & 1;
        size_t chunk = unit / 2;

        foreach (i; 0 .. 28)
        {
            size_t frame = firstFrame + chunk * 28 + i;
            size_t index = frame * 2 + channel;

            unitSamples[i] =
                index < pcm.length ? pcm[index] : 0;
        }

        auto result = encodeXaUnit(
            unitSamples,
            states[channel].h1,
            states[channel].h2);

        params[unit] = cast(ubyte)(
            (result.filter << 4) | result.shift);

        states[channel].h1 = result.h1;
        states[channel].h2 = result.h2;

        foreach (i; 0 .. 28)
            encoded[i][unit] = result.nibbles[i];
    }

    // XA group parameter layout, including duplicate parameters.
    foreach (i; 0 .. 4)
    {
        dst[i]      = params[i];
        dst[i + 4]  = params[i];
        dst[i + 8]  = params[i + 4];
        dst[i + 12] = params[i + 4];
    }

    // 28 rows, four bytes per row, two samples per byte.
    foreach (i; 0 .. 28)
    {
        foreach (pair; 0 .. 4)
        {
            ubyte lo = encoded[i][pair * 2];
            ubyte hi = encoded[i][pair * 2 + 1];

            dst[16 + i * 4 + pair] =
                cast(ubyte)(lo | (hi << 4));
        }
    }
}


short[] resampleStereo(const(short)[] input, uint srcRate, uint dstRate)
{
    enforce(srcRate > 0 && dstRate > 0, "Invalid sample rate");
    enforce(input.length % 2 == 0, "Invalid stereo PCM data");

    size_t inFrames = input.length / 2;
    if (inFrames == 0)
        return [];

    size_t outFrames = cast(size_t)(
        (cast(ulong)inFrames * dstRate + srcRate / 2) / srcRate);

    short[] output;
    output.length = outFrames * 2;

    foreach (i; 0 .. outFrames)
    {
        // Position of the output frame within the source signal.
        ulong position = cast(ulong)i * srcRate;
        size_t index = cast(size_t)(position / dstRate);
        uint fraction = cast(uint)(position % dstRate);

        if (index >= inFrames - 1)
        {
            output[i * 2]     = input[(inFrames - 1) * 2];
            output[i * 2 + 1] = input[(inFrames - 1) * 2 + 1];
            continue;
        }

        foreach (ch; 0 .. 2)
        {
            int a = input[index * 2 + ch];
            int b = input[(index + 1) * 2 + ch];

            long value = cast(long)a * (dstRate - fraction)
                       + cast(long)b * fraction;

            value = value >= 0
                ? (value + dstRate / 2) / dstRate
                : (value - dstRate / 2) / dstRate;

            output[i * 2 + ch] = cast(short)value;
        }
    }

    return output;
}

Stream wavToXa(string path)
{
    auto wav = readWav(path);

    enforce(wav.channels == 2,
        format("%s: expected stereo WAV", path));
    enforce(wav.bitsPerSample == 16,
        format("%s: expected 16-bit PCM WAV", path));

    enforce(wav.channels == 2,
        format("%s: expected stereo WAV", path));
    enforce(wav.bitsPerSample == 16,
        format("%s: expected 16-bit PCM WAV", path));

    // TODO: support 18900 Hz
    auto pcm = wav.sampleRate == 37800
        ? wav.samples
        : resampleStereo(wav.samples, wav.sampleRate, 37800);

    size_t frames = pcm.length / 2;
    
    size_t sectorCount =
        (frames + XA_FRAMES_PER_SECTOR - 1) / XA_FRAMES_PER_SECTOR;

    // Do not create an empty XA file for a zero-length WAV.
    enforce(sectorCount > 0, format("%s: WAV contains no samples", path));

    Stream result;
    result.path = path;
    result.data.length = sectorCount * SECTOR;
    
    XaState[2] states;

    foreach (sectorIndex; 0 .. sectorCount)
    {
        auto sector = result.data[
            sectorIndex * SECTOR .. (sectorIndex + 1) * SECTOR];

        // XA subheader: file, channel, submode, coding info. 
        // The file and channel numbers will be set later by the interleaving process.
        sector[0] = 0;
        sector[1] = 0;
        sector[2] = 0x64; // audio | Form 2 | realtime
        sector[3] = 0x01; // stereo, 37800 Hz, 4-bit

        sector[4] = sector[0];
        sector[5] = sector[1];
        sector[6] = sector[2];
        sector[7] = sector[3];

        // 18 ADPCM groups begin at offset 8.
        foreach (groupIndex; 0 .. XA_GROUPS_PER_SECTOR)
        {
            size_t firstFrame =
                sectorIndex * XA_FRAMES_PER_SECTOR
                + groupIndex * XA_FRAMES_PER_GROUP;

            auto group = sector[
                8 + groupIndex * XA_GROUP_SIZE ..
                8 + (groupIndex + 1) * XA_GROUP_SIZE];

            //encodeXaGroup(pcm, firstFrame, group);
            encodeXaGroup(pcm, firstFrame, group, states);
        }

        // The remaining 24 bytes of the sector are already filled with zeros.
    }

    return result;
}
