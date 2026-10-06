import std.math: sin, PI, round;
import std.file: write;

enum COUNT = 4096;
enum SCALE = 0x1000;

void main()
{
    ubyte[] data;
    data.length = COUNT * 2;

    foreach (i; 0 .. COUNT)
    {
        double angle = 2.0 * PI * i / COUNT;
        short value = cast(short)round(sin(angle) * SCALE);

        data[i * 2 + 0] = cast(ubyte)(value & 0xff);
        data[i * 2 + 1] = cast(ubyte)(value >> 8);
    }

    write("sin4096.bin", data);
}
