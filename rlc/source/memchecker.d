module memchecker;

import std.algorithm.sorting: sort;
import std.format;
import error;
import ir;
import memmap;

struct MemoryRange
{
    ulong begin;
    ulong end;
    string name;

    bool overlaps(const ref MemoryRange other) const
    {
        return begin < other.end && other.begin < end;
    }
}

MemoryRange[] allowedRanges =
[
    MemoryRange(RAM_BASE, RAM_BASE + RAM_SIZE, "RAM"),
    MemoryRange(SCRATCHPAD_BASE, SCRATCHPAD_BASE + SCRATCHPAD_SIZE, "Scratchpad")
];

bool isAllowedRegion(RamRegion region)
{
    foreach (r; allowedRanges)
    {
        if (region.baseAddress < r.begin || region.baseAddress > r.end)
            continue;

        if (region.size <= r.end - region.baseAddress)
            return true;
    }

    return false;
}

void validateMemory(RamRegion[] regions, MemoryRange[] reservedRanges = [])
{
    MemoryRange[] ranges;
    if (reservedRanges.length)
        ranges ~= reservedRanges;
    
    foreach (region; regions)
    {
        if (region.pos > region.size)
            region.size = region.pos;
        
        if (!region.isAllowedRegion)
        {
            throw err(format(
                "Region [0x%08x, 0x%08x) is outside of allowed memory\n",
                region.baseAddress, region.size
            ));
        }
        
        ulong end;

        if (region.size > 0)
        {
            end = region.baseAddress + region.size;
        }
        else
        {
            // An unbounded region has no explicit upper limit.
            // Its allocations still have to be checked individually.
            end = region.baseAddress;

            foreach (a; region.allocations)
            {
                ulong allocationEnd = a.offset + a.size;

                if (allocationEnd > end - region.baseAddress)
                    end = region.baseAddress + allocationEnd;
            }
        }

        if (end > region.baseAddress)
        {
            ranges ~= MemoryRange(
                region.baseAddress,
                end,
                "RAM region"
            );
        }
    }

    // Sort by starting address.
    sort!((a, b) => a.begin < b.begin)(ranges);

    // Check adjacent ranges.
    for (size_t i = 1; i < ranges.length; ++i)
    {
        if (ranges[i - 1].overlaps(ranges[i]))
        {
            throw err(format(
                "memory overlap: %s [0x%08x, 0x%08x) and %s [0x%08x, 0x%08x)\n",
                ranges[i - 1].name,
                ranges[i - 1].begin,
                ranges[i - 1].end,
                ranges[i].name,
                ranges[i].begin,
                ranges[i].end
            ));
        }
    }
}
