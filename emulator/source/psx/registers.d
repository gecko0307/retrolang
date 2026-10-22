module psx.registers;

struct PsxRegisters
{
    uint[32] _regs;
    uint[32] _out_regs;

    void reset()
    {
        _regs[] = 0;
        _out_regs[] = 0;
    }

    uint opIndexAssign(uint val, uint index)
    {
        assert(index < 32);
        _out_regs[index] = val;
        _out_regs[0] = 0;
        return val;
    }

    uint opIndex(uint index)
    {
        assert(index < 32);
        return _regs[index];
    }

    void copyOut()
    {
        _regs[] = _out_regs[];
    }
}
