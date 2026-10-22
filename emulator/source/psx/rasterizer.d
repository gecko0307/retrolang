module psx.rasterizer;

import psx.gpu;

float edgeFunction(float x0, float y0, float x1, float y1, float x, float y)
{
    return (x - x0) * (y1 - y0) - (y - y0) * (x1 - x0);
};

ubyte clamp8(float v)
{
    if (v < 0f) return 0;
    if (v > 255f) return 255;
    return cast(ubyte)v;
}

ushort packRgb555(ubyte r8, ubyte g8, ubyte b8)
{
    ubyte r5 = cast(ubyte)(r8 >> 3);
    ubyte g5 = cast(ubyte)(g8 >> 3);
    ubyte b5 = cast(ubyte)(b8 >> 3);
    return cast(ushort)((b5 << 10) | (g5 << 5) | r5);
}

void drawTriangle(PsxGpu* gpu,
                  GpuPos pa, GpuPos pb, GpuPos pc,
                  GpuColor ca, GpuColor cb, GpuColor cc)
{
    int ax = pa.x + gpu.drawingXOffset;
    int ay = pa.y + gpu.drawingYOffset;
    int bx = pb.x + gpu.drawingXOffset;
    int by = pb.y + gpu.drawingYOffset;
    int cx = pc.x + gpu.drawingXOffset;
    int cy = pc.y + gpu.drawingYOffset;

    int minX = ax < bx ? (ax < cx ? ax : cx) : (bx < cx ? bx : cx);
    int maxX = ax > bx ? (ax > cx ? ax : cx) : (bx > cx ? bx : cx);
    int minY = ay < by ? (ay < cy ? ay : cy) : (by < cy ? by : cy);
    int maxY = ay > by ? (ay > cy ? ay : cy) : (by > cy ? by : cy);

    if (minX > VRAM_WIDTH - 1 || maxX < 0 || minY > VRAM_HEIGHT - 1 || maxY < 0)
        return;

    if (minX < 0) minX = 0;
    if (minY < 0) minY = 0;
    if (maxX >= VRAM_WIDTH) maxX = VRAM_WIDTH - 1;
    if (maxY >= VRAM_HEIGHT) maxY = VRAM_HEIGHT - 1;

    float area = edgeFunction(ax, ay, bx, by, cx, cy);
    if (area == 0) return; // degenerate

    bool areaPos = area > 0;

    for (int y = minY; y <= maxY; ++y)
    {
        for (int x = minX; x <= maxX; ++x)
        {
            float w0 = edgeFunction(bx, by, cx, cy, x, y);
            float w1 = edgeFunction(cx, cy, ax, ay, x, y);
            float w2 = edgeFunction(ax, ay, bx, by, x, y);

            bool inside;
            if (areaPos)
                inside = (w0 >= 0 && w1 >= 0 && w2 >= 0);
            else
                inside = (w0 <= 0 && w1 <= 0 && w2 <= 0);

            if (!inside) continue;

            float denom = cast(float)area;
            float alpha = cast(float)w0 / denom;
            float beta  = cast(float)w1 / denom;
            float gamma = cast(float)w2 / denom;
            
            float r = cast(float)ca.r * alpha + cast(float)cb.r * beta + cast(float)cc.r * gamma;
            float g = cast(float)ca.g * alpha + cast(float)cb.g * beta + cast(float)cc.g * gamma;
            float b = cast(float)ca.b * alpha + cast(float)cb.b * beta + cast(float)cc.b * gamma;
            
            ubyte rr = clamp8(r);
            ubyte gg = clamp8(g);
            ubyte bb = clamp8(b);
            
            size_t idx = (cast(size_t)y * VRAM_WIDTH + cast(size_t)x) * 4;
            gpu.vram[idx+0] = rr;
            gpu.vram[idx+1] = gg;
            gpu.vram[idx+2] = bb;
        }
    }
}
