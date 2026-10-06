/*
module disasm;

import std.stdio;
import mips;

class MipsDisassembler
{
    public:
    
    this(uint[] text)
    {
        this.text = text;
        disassemble();
    }
    
    protected:
    
    uint[] text;
    
    void disassemble()
    {
        foreach(uint instr; text)
        {
            disasmInstruction(instr);
        }
    }
    
    void disasmInstruction(uint instr)
    {
        ubyte opcode = cast(ubyte)(instr >> 26);
        
        if (opcode == 0) // R-type
            disasmRType(instr);
        else if (opcode == MipsInstr.J || opcode == MipsInstr.JAL)
            disasmJump(instr);
        else if (opcode == MipsInstr.COP0)
            disasmCOP0(instr);
        else if (opcode == MipsInstr.COP2)
            disasmCOP2(instr);
        else // I-type
            disasmIType(instr);
    }
    
    // TODO: use separate disasm function for each r-type instruction
    void disasmRType(uint instr)
    {
        ubyte funct = cast(ubyte)(instr & 0x3f);
        ubyte rs    = cast(ubyte)((instr >> 21) & 0x1f);
        ubyte rt    = cast(ubyte)((instr >> 16) & 0x1f);
        ubyte rd    = cast(ubyte)((instr >> 11) & 0x1f);
        ubyte shift = cast(ubyte)((instr >> 6)  & 0x1f);
        
        if (funct == MipsRType.JR)
        {
            writefln("  0x%08x: %s $%s", instr, cast(MipsRType)funct, rs);
        }
        else
        {
            if (funct == MipsRType.SLL && rs == 0 && rt == 0 && rd == 0 && shift == 0)
            {
                writefln("  0x%08x: NOP", instr);
            }
            else
            {
                writefln("  0x%08x: %s $%s, $%s, %d($%s)", instr, cast(MipsRType)funct, rd, rs, shift, rt);
            }
        }
    }
    
    void disasmIType(uint instr)
    {
        ubyte opcode = cast(ubyte)(instr >> 26);
        ubyte rs    = cast(ubyte)((instr >> 21) & 0x1f);
        ubyte rt    = cast(ubyte)((instr >> 16) & 0x1f);
        short imm   = cast(short)(instr & 0xffff);
        
        if (opcode == MipsInstr.LUI)
        {
            writefln("  0x%08x: %s $%s, 0x%04x", instr, cast(MipsInstr)opcode, rt, imm);
        }
        else
        {
            writefln("  0x%08x: %s $%s, $%s, 0x%04x", instr, cast(MipsInstr)opcode, rt, rs, imm);
        }
    }
    
    void disasmJump(uint instr)
    {
        ubyte opcode = cast(ubyte)(instr >> 26);
        uint target = instr & 0x03ffffff;
        writefln("  0x%08x: %s 0x%08x", instr, cast(MipsInstr)opcode, target);
    }
    
    void disasmCOP0(uint instr)
    {
        ubyte op = cast(ubyte)((instr >> 21) & 0x1f);
        
        if (op == MipsCop0.MTC0 || op == MipsCop0.MFC0)
        {
            ubyte rt = cast(ubyte)((instr >> 16) & 0x1f);
            ubyte rd = cast(ubyte)((instr >> 11) & 0x1f);
            
            writefln("  0x%08x: %s $%s, $%s", instr, cast(MipsCop0)op, rt, rd);
        }
        else
        {
            writefln("  0x%08x: %s", instr, MipsInstr.COP0);
        }
    }
    
    void disasmCOP2(uint instr)
    {
        ubyte op = cast(ubyte)((instr >> 21) & 0x1f);
        
        if (op == MipsCop2.MTC2 || op == MipsCop2.MFC2 ||
            op == MipsCop2.CTC2 || op == MipsCop2.CFC2)
        {
            ubyte rt = cast(ubyte)((instr >> 16) & 0x1f);
            ubyte rd = cast(ubyte)((instr >> 11) & 0x1f);
            
            writefln("  0x%08x: %s $%s, $%s", instr, cast(MipsCop2)op, rt, rd);
        }
        else
        {
            writefln("  0x%08x: %s", instr, MipsInstr.COP2);
        }
    }
}
*/

module disasm;
 
import std.stdio;
import std.format : format;
import mips;
 
class MipsDisassembler
{
    public:
    
    /// text:     words to disassemble
    /// baseAddr: address of text[0]
    /// entry:    if given, only code reachable from this address is disassembled
    ///           as code, everything else is printed as data. If uint.max,
    ///           everything is disassembled linearly.
    this(uint[] text, uint baseAddr = 0, uint entry = uint.max)
    {
        this.text = text;
        this.baseAddr = baseAddr;
        
        if (entry == uint.max)
        {
            disassembleLinear();
        }
        else
        {
            traceCode(entry);
            disassembleTraced();
        }
    }
    
    protected:
    
    uint[] text;
    uint baseAddr;
    bool[] isCode;
    
    uint addrOf(size_t i)
    {
        return baseAddr + cast(uint)(i * 4);
    }
    
    // ---------------------------------------------------------------
    // Output drivers
    // ---------------------------------------------------------------
    
    void disassembleLinear()
    {
        foreach (i, instr; text)
            printInstruction(addrOf(i), instr);
    }
    
    void disassembleTraced()
    {
        size_t i = 0;
        while (i < text.length)
        {
            if (isCode[i])
            {
                printInstruction(addrOf(i), text[i]);
                i++;
            }
            else
            {
                size_t end = i;
                while (end < text.length && !isCode[end])
                    end++;
                printData(i, end);
                i = end;
            }
        }
    }
    
    void printInstruction(uint pc, uint instr)
    {
        writefln("  %08x: %08x  %s", pc, instr, disasmInstruction(pc, instr));
    }
    
    void printData(size_t start, size_t end)
    {
        size_t i = start;
        while (i < end)
        {
            size_t j = i;
            while (j < end && text[j] == 0)
                j++;
            
            if (j - i >= 4)
            {
                writefln("  %08x: ... %d words of zeros (0x%x bytes)",
                         addrOf(i), j - i, (j - i) * 4);
                i = j;
            }
            else
            {
                writefln("  %08x: %08x  .word 0x%08x%s",
                         addrOf(i), text[i], text[i], asciiHint(text[i]));
                i++;
            }
        }
    }
    
    string asciiHint(uint w)
    {
        string s;
        bool anyPrintable = false;
        foreach (k; 0 .. 4)
        {
            ubyte b = cast(ubyte)((w >> (8 * k)) & 0xff);
            if (b >= 0x20 && b < 0x7f)
            {
                s ~= cast(char)b;
                anyPrintable = true;
            }
            else if (b == '\n')
                s ~= "\\n";
            else if (b == 0)
                s ~= "\\0";
            else
                return "";
        }
        return anyPrintable ? "  ; \"" ~ s ~ "\"" : "";
    }
    
    // ---------------------------------------------------------------
    // Control flow tracing
    // ---------------------------------------------------------------
    
    static uint jumpTarget(uint pc, uint instr)
    {
        return ((pc + 4) & 0xf0000000) | ((instr & 0x03ffffff) << 2);
    }
    
    static uint branchTarget(uint pc, uint instr)
    {
        int offset = cast(int)cast(short)(instr & 0xffff);
        return pc + 4 + cast(uint)(offset * 4);
    }
    
    static bool isBranchOpcode(ubyte op)
    {
        // REGIMM (1), BEQ, BNE, BLEZ, BGTZ (4..7)
        return op == 1 || (op >= 4 && op <= 7);
    }
    
    void markCode(uint addr)
    {
        if (addr < baseAddr || ((addr - baseAddr) & 3) != 0)
            return;
        size_t i = (addr - baseAddr) / 4;
        if (i < text.length)
            isCode[i] = true;
    }
    
    void traceCode(uint entry)
    {
        isCode = new bool[text.length];
        uint[] work = [entry];
        
        while (work.length > 0)
        {
            uint addr = work[$ - 1];
            work = work[0 .. $ - 1];
            
            for (;;)
            {
                if (addr < baseAddr || ((addr - baseAddr) & 3) != 0)
                    break;
                size_t i = (addr - baseAddr) / 4;
                if (i >= text.length || isCode[i])
                    break;
                
                isCode[i] = true;
                uint instr = text[i];
                ubyte op = cast(ubyte)(instr >> 26);
                ubyte rs = cast(ubyte)((instr >> 21) & 0x1f);
                ubyte rt = cast(ubyte)((instr >> 16) & 0x1f);
                
                bool hasDelaySlot = false;
                bool stop = false;
                
                if (op == 0)
                {
                    ubyte funct = cast(ubyte)(instr & 0x3f);
                    if (funct == 0x08)       // JR: no fall-through
                    {
                        hasDelaySlot = true;
                        stop = true;
                    }
                    else if (funct == 0x09)  // JALR: returns here
                    {
                        hasDelaySlot = true;
                    }
                }
                else if (op == 2 || op == 3) // J / JAL
                {
                    work ~= jumpTarget(addr, instr);
                    hasDelaySlot = true;
                    stop = (op == 2);
                }
                else if (isBranchOpcode(op))
                {
                    work ~= branchTarget(addr, instr);
                    hasDelaySlot = true;
                    stop = (op == 4 && rs == rt); // BEQ $x, $x: unconditional
                }
                
                if (hasDelaySlot)
                    markCode(addr + 4);
                if (stop)
                    break;
                
                addr += hasDelaySlot ? 8 : 4;
            }
        }
    }
    
    // ---------------------------------------------------------------
    // Instruction decoding (returns the text after the address)
    // ---------------------------------------------------------------
    
    string disasmInstruction(uint pc, uint instr)
    {
        ubyte opcode = cast(ubyte)(instr >> 26);
        
        if (opcode == 0) // R-type
            return disasmRType(instr);
        else if (opcode == MipsInstr.J || opcode == MipsInstr.JAL)
            return disasmJump(pc, instr);
        else if (opcode == MipsInstr.COP0)
            return disasmCOP0(instr);
        else if (opcode == MipsInstr.COP2)
            return disasmCOP2(instr);
        else // I-type
            return disasmIType(pc, instr);
    }
    
    // TODO: use separate disasm function for each r-type instruction
    string disasmRType(uint instr)
    {
        ubyte funct = cast(ubyte)(instr & 0x3f);
        ubyte rs    = cast(ubyte)((instr >> 21) & 0x1f);
        ubyte rt    = cast(ubyte)((instr >> 16) & 0x1f);
        ubyte rd    = cast(ubyte)((instr >> 11) & 0x1f);
        ubyte shift = cast(ubyte)((instr >> 6)  & 0x1f);
        
        if (funct == MipsRType.JR)
            return format("%s $%s", cast(MipsRType)funct, rs);
        
        if (funct == MipsRType.SLL && rs == 0 && rt == 0 && rd == 0 && shift == 0)
            return "NOP";
        
        return format("%s $%s, $%s, %d($%s)", cast(MipsRType)funct, rd, rs, shift, rt);
    }
    
    string disasmIType(uint pc, uint instr)
    {
        ubyte opcode = cast(ubyte)(instr >> 26);
        ubyte rs    = cast(ubyte)((instr >> 21) & 0x1f);
        ubyte rt    = cast(ubyte)((instr >> 16) & 0x1f);
        short imm   = cast(short)(instr & 0xffff);
        
        if (opcode == MipsInstr.LUI)
            return format("%s $%s, 0x%04x", cast(MipsInstr)opcode, rt, imm);
        
        if (isBranchOpcode(opcode))
            return format("%s $%s, $%s, 0x%08x", cast(MipsInstr)opcode, rt, rs,
                          branchTarget(pc, instr));
        
        return format("%s $%s, $%s, 0x%04x", cast(MipsInstr)opcode, rt, rs, imm);
    }
    
    string disasmJump(uint pc, uint instr)
    {
        ubyte opcode = cast(ubyte)(instr >> 26);
        return format("%s 0x%08x", cast(MipsInstr)opcode, jumpTarget(pc, instr));
    }
    
    string disasmCOP0(uint instr)
    {
        ubyte op = cast(ubyte)((instr >> 21) & 0x1f);
        
        if (op == MipsCop0.MTC0 || op == MipsCop0.MFC0)
        {
            ubyte rt = cast(ubyte)((instr >> 16) & 0x1f);
            ubyte rd = cast(ubyte)((instr >> 11) & 0x1f);
            return format("%s $%s, $%s", cast(MipsCop0)op, rt, rd);
        }
        
        return format("%s", MipsInstr.COP0);
    }
    
    string disasmCOP2(uint instr)
    {
        ubyte op = cast(ubyte)((instr >> 21) & 0x1f);
        
        if (op == MipsCop2.MTC2 || op == MipsCop2.MFC2 ||
            op == MipsCop2.CTC2 || op == MipsCop2.CFC2)
        {
            ubyte rt = cast(ubyte)((instr >> 16) & 0x1f);
            ubyte rd = cast(ubyte)((instr >> 11) & 0x1f);
            return format("%s $%s, $%s", cast(MipsCop2)op, rt, rd);
        }
        
        return format("%s", MipsInstr.COP2);
    }
}
