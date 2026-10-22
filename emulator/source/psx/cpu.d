module psx.cpu;

import core.atomic;
import std.stdio;
import std.string;
import core.checkedint;

import psx.registers;
import psx.ram;
import psx.dma;
import psx.gpu;
import psx.exception;

//version = PrintAsm;
//version = DebugMsg;
//version = WarnUnimplemented;

struct PsxCpu
{
    bool running = true;
    
    void stop()
    {
        atomicStore(running, false);
        atomicStore(gpu.frameReady, true);
        atomicStore(gpu.frameLocked, false);
    }
    
    void stopError(string err)
    {
        stop();
        writeln(err);
    }
    
    // Registers
    PsxRegisters reg;

    uint pc; // Program Counter
    uint nextPc;
    uint currentPc;

    uint hi; // HI register for division remainder and multiplication high
    uint lo; // LO register for division quotient and multiplication low

    uint sr; // Cop0 register 12: Status Register
    uint cause; // Cop0 register 13: Cause Register
    uint epc; // Cop0 register 14: EPC

    // Set by the current instruction if a branch occured and the
    // next instruction will be in the delay slot.
    bool inBranch;
    // Set if the current instruction executes in the delay slot
    bool inDelaySlot;
    
    bool ignoreBiosCalls = false;

    // Memory
    PsxRam ram;
    ubyte[] bios;

    // DMA
    PsxDma dma;
    
    // GPU
    PsxGpu gpu;

    const uint[8] REGION_MASK = [
        // KUSEG: 2048MB
        0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
        // KSEG0: 512MB
        0x7fffffff,
        // KSEG1: 512MB
        0x1fffffff,
        // KSEG2: 1024MB
        0xffffffff, 0xffffffff,
    ];

    uint maskRegion(uint adr)
    {
        // Index address space in 512MB chunks
        uint index = adr >> 29;
        return adr & REGION_MASK[index];
    }

    void init(ubyte[] biosData)
    {
        assert(biosData.length == PSX_BIOS_SIZE);
        ram.init(PSX_RAM_SIZE);
        gpu.init();
        bios = biosData;
        reset();
    }
    
    void initEXE(ubyte[] psxExe)
    {
        ram.init(PSX_RAM_SIZE);
        gpu.init();
        
        uint[] exeWords = cast(uint[])psxExe;
        
        uint entryPoint = exeWords[4] & 0x1FFFFFFF;
        uint loadAddress = exeWords[6] & 0x1FFFFFFF;
        uint codeSize = exeWords[7];
        
        writefln("EXE load address: 0x%08x", loadAddress);
        writefln("Code size: %s byte(s)", codeSize);
        writefln("Entry point: 0x%08x", entryPoint);
        
        uint loadOffset = loadAddress - 2048;
        ram.data[loadOffset..loadOffset+psxExe.length] = psxExe[];
        
        ignoreBiosCalls = true;
        
        reset(entryPoint);
    }

    void reset(uint initPC = 0xbfc00000)
    {
        reg.reset();
        dma.reset();
        gpu.reset();

        pc = initPC;
        nextPc = pc + 4;

        sr = 0x0;

        hi = 0xdeadbeef;
        lo = 0xdeadbeef;

        inBranch = false;
        inDelaySlot = false;
    }

    // Trigger an exception
    void exception(uint code)
    {
        // Exception handler address depends on the `BEV` bit:
        uint handler;
        if ((sr & (1 << 22)) != 0)
            handler = 0xbfc00180;
        else
            handler = 0x80000080;

        // Shift bits [5:0] of `SR` two places to the left.
        // Those bits are three pairs of Interrupt Enable/User
        // Mode bits behaving like a stack 3 entries deep.
        // Entering an exception pushes a pair of zeroes
        // by left shifting the stack which disables
        // interrupts and puts the CPU in kernel mode.
        // The original third entry is discarded (it's up
        // to the kernel to handle more than two recursive
        // exception levels).
        uint mode = sr & 0x3f;
        sr &= ~0x3f;
        sr |= (mode << 2) & 0x3f;

        // Update `CAUSE` register with the exception code (bits [6:2])
        cause = code << 2;

        // Save current instruction address in `EPC`
        epc = currentPc;

        if (inDelaySlot)
        {
            // When an exception occurs in a delay slot `EPC` points
            // to the branch instruction and bit 31 of `CAUSE` is set.
            epc = epc - 4;
            cause |= 1 << 31;
        }

        // Exceptions don't have a branch delay, we jump directly
        // into the handler
        pc = handler;
        nextPc = pc + 4;
    }

    uint load32(uint adr)
    {
        adr = maskRegion(adr);

        // TODO: make a function to detect regions
        if (adr >= 0x00000000 && adr < PSX_RAM_SIZE) // if adr is within RAM
        {
            return ram.read32(adr);
        }
        else if (adr >= 0x1f000000 && adr < 0x1f000000 + 512 * 1024) // if adr is within EXPANSION_1 region
        {
            version(WarnUnimplemented) writefln("load32 from EXPANSION_1 region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1fc00000 && adr < 0x1fc00000 + 512 * 1024) // if adr is within BIOS region
        {
            return biosRead(adr - 0x1fc00000);
        }
        else if (adr >= 0x1f800000 && adr < 0x1f800000 + 1024) // if adr is within SCRATCH_PAD region
        {
            version(WarnUnimplemented) writefln("load32 from SCRATCH_PAD region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801000 && adr < 0x1f801000 + 36) // if adr is within MEM_CONTROL region
        {
            version(WarnUnimplemented) writefln("load32 from MEM_CONTROL region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801040 && adr < 0x1f801040 + 4) // if adr is PAD_MEMCARD register
        {
            version(WarnUnimplemented) writefln("load32 from PAD_MEMCARD register: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801060 && adr < 0x1f801060 + 4) // if adr is RAM_SIZE register
        {
            version(WarnUnimplemented) writefln("load32 from RAM_SIZE register: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801070 && adr < 0x1f801070 + 8) // if adr is within IRQ control region
        {
            version(WarnUnimplemented) writefln("load32 from IRQ_CONTROL register: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801080 && adr < 0x1f801080 + 0x80) // if adr is within DMA region
        {
            return dmaRead(adr - 0x1f801080);
        }
        else if (adr >= 0x1f801100 && adr < 0x1f801100 + 0x30) // if adr is within TIMERS region
        {
            version(WarnUnimplemented) writefln("load32 from TIMERS region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801800 && adr < 0x1f801800 + 0x4) // if adr is within CDROM region
        {
            version(WarnUnimplemented) writefln("load32 from CDROM region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801810 && adr < 0x1f801810 + 8) // if adr is within GPU control region
        {
            uint offset = adr - 0x1f801810;
            if (offset == 0) // GPUREAD register
                return gpu.read();
            if (offset == 4) // GPUSTAT register
                return gpu.status();
            else
            {
                version(WarnUnimplemented) writefln("load32 from GPU register 0x%0.8x: unimplemented", adr);
                return 0;
            }
        }
        else if (adr >= 0x1f801820 && adr < 0x1f801820 + 8) // if adr is within MDEC region
        {
            version(WarnUnimplemented) writefln("load32 from MDEC region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801c00 && adr < 0x1f801c00 + 640) // if adr is within SPU region
        {
            version(WarnUnimplemented) writefln("load32 from SPU region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f802000 && adr < 0x1f802000 + 66) // if adr is within EXPANSION_2 region
        {
            version(WarnUnimplemented) writefln("load32 from EXPANSION_2 region: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0xfffe0130 && adr < 0xfffe0130 + 4) // if adr is CACHE_CONTROL register
        {
            version(WarnUnimplemented) writefln("load32 from CACHE_CONTROL register: unimplemented", adr);
            return 0;
        }
        else
        {
            stopError(format("unhandled load32 at address 0x%0.8x", adr));
            return 0;
        }
    }

    void store32(uint adr, uint val)
    {
        adr = maskRegion(adr);

        if ((sr & 0x10000) != 0)
        {
            version(DebugMsg) writeln("ignoring store32 while cache is isolated");
            return;
        }

        if (adr >= 0x1fc00000 && adr < 0x1fc00000 + 512 * 1024) // if adr is within BIOS region
        {
            biosWrite(adr - 0x1fc00000, val);
        }
        else if (adr >= 0x1f801000 && adr < 0x1f801000 + 36) // if adr is within memory control region
        {
            version(WarnUnimplemented) writefln("store32 to Memory Control register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801060 && adr < 0x1f801060 + 4) // if adr is RAM_SIZE register
        {
            version(WarnUnimplemented) writefln("store32 to Memory Control register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0xfffe0130 && adr < 0xfffe0130 + 4) // if adr is CACHE_CONTROL register
        {
            version(WarnUnimplemented) writefln("store32 to Memory Control register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x00000000 && adr < PSX_RAM_SIZE) // if adr is within RAM
        {
            ram.write32(adr, val);
        }
        else if (adr >= 0x1f801070 && adr < 0x1f801070 + 8) // if adr is within IRQ control region
        {
            version(WarnUnimplemented) writefln("store32 to IRQ Control register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801080 && adr < 0x1f801080 + 0x80) // if adr is within DMA control region
        {
            version(DebugMsg) writefln("DMA write 0x%0.8x", val);
            dmaWrite(adr - 0x1f801080, val);
        }
        else if (adr >= 0x1f801810 && adr < 0x1f801810 + 8) // if adr is within GPU control region
        {
            uint offset = adr - 0x1f801810;
            if (offset == 0)
                gpu.gp0(val);
            else if (offset == 4)
                gpu.gp1(val);
            else
                version(WarnUnimplemented) writefln("store32 to GPU register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801100 && adr < 0x1f801100 + 16) // if adr is within Timer0 region
        {
            version(WarnUnimplemented) writefln("store32 to Timer0 register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801110 && adr < 0x1f801110 + 16) // if adr is within Timer1 region
        {
            version(WarnUnimplemented) writefln("store32 to Timer1 register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801120 && adr < 0x1f801120 + 16) // if adr is within Timer2 region
        {
            version(WarnUnimplemented) writefln("store32 to Timer2 register 0x%0.8x: unimplemented", adr);
        }
        else
        {
            stopError(format("unhandled store32 at address 0x%0.8x", adr));
        }
    }

    ushort load16(uint adr)
    {
        adr = maskRegion(adr);

        if (adr >= 0x1f801c00 && adr < 0x1f801c00 + 640) // if adr is within SPU region
        {
            version(WarnUnimplemented) writefln("load16 from SPU register 0x%0.8x: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x00000000 && adr < PSX_RAM_SIZE) // if adr is within RAM
        {
            return ram.read16(adr);
        }
        else if (adr >= 0x1f801070 && adr < 0x1f801070 + 8) // if adr is within IRQ control region
        {
            version(WarnUnimplemented) writefln("load16 from IRQ Control register 0x%0.8x: unimplemented", adr);
            return 0;
        }
        else
        {
            stopError(format("unhandled load16 at address 0x%0.8x", adr));
            return 0;
        }
    }

    void store16(uint adr, ushort val)
    {
        adr = maskRegion(adr);

        if (adr >= 0x1f801c00 && adr < 0x1f801c00 + 640) // if adr is within SPU region
        {
            version(WarnUnimplemented) writefln("store16 to SPU register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801100 && adr < 0x1f801100 + 16) // if adr is within Timer0 region
        {
            version(WarnUnimplemented) writefln("store16 to Timer0 register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801110 && adr < 0x1f801110 + 16) // if adr is within Timer1 region
        {
            version(WarnUnimplemented) writefln("store16 to Timer1 register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x1f801120 && adr < 0x1f801120 + 16) // if adr is within Timer2 region
        {
            version(WarnUnimplemented) writefln("store16 to Timer2 register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x00000000 && adr < PSX_RAM_SIZE) // if adr is within RAM
        {
            ram.write16(adr, val);
        }
        else if (adr >= 0x1f801070 && adr < 0x1f801070 + 8) // if adr is within IRQ control region
        {
            version(WarnUnimplemented) writefln("store16 to IRQ Control register 0x%0.8x: unimplemented", adr);
        }
        else
        {
            stopError(format("unhandled store16 at address 0x%0.8x", adr));
        }
    }

    ubyte load8(uint adr)
    {
        //writefln("load8 0x%0.8x", adr);
        adr = maskRegion(adr);

        if (adr >= 0x1fc00000 && adr < 0x1fc00000 + 512 * 1024) // if adr is within BIOS region
        {
            return bios[adr - 0x1fc00000];
        }
        else if (adr >= 0x1f000000 && adr < 0x1f000000 + 8192) // if adr is within EXPANSION_1 region
        {
            return 0xff; // No expansion implemented
        }
        else if (adr >= 0x1f801000 && adr < 0x1f801000 + 36) // if adr is within SYS_CONTROL region
        {
            version(WarnUnimplemented) writefln("load8 from Memory Control register 0x%0.8x: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x1f801060 && adr < 0x1f801060 + 4) // if adr is RAM_SIZE register
        {
            version(WarnUnimplemented) writefln("load8 from Memory Control register 0x%0.8x: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0xfffe0130 && adr < 0xfffe0130 + 4) // if adr is CACHE_CONTROL register
        {
            version(WarnUnimplemented) writefln("load8 from Memory Control register 0x%0.8x: unimplemented", adr);
            return 0;
        }
        else if (adr >= 0x00000000 && adr < PSX_RAM_SIZE) // if adr is within RAM
        {
            return ram.read8(adr);
        }
        else
        {
            stopError(format("unhandled load8 at address 0x%0.8x", adr));
            return 0;
        }
    }

    void store8(uint adr, ubyte val)
    {
        adr = maskRegion(adr);

        if (adr >= 0x1f802000 && adr < 0x1f802000 + 66) // if adr is within EXPANSION_2 region
        {
            version(WarnUnimplemented) writefln("store8 to EXPANSION2 register 0x%0.8x: unimplemented", adr);
        }
        else if (adr >= 0x00000000 && adr < PSX_RAM_SIZE) // if adr is within RAM
        {
            ram.write8(adr, val);
        }
        else
        {
            stopError(format("unhandled store8 at address 0x%0.8x", adr));
        }
    }

    void branch(uint offset)
    {
        offset = offset << 2;
        nextPc = pc + offset;
        inBranch = true;
    }

    uint biosRead(uint offset)
    {
        uint b0 = bios[offset + 0];
        uint b1 = bios[offset + 1];
        uint b2 = bios[offset + 2];
        uint b3 = bios[offset + 3];
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
    }

    void biosWrite(uint offset, uint value)
    {
        assert(0, format("unhandled biosWrite by address 0x%0.8x", offset));
    }

    // DMA register read
    uint dmaRead(uint offset)
    {
        uint major = (offset & 0x70) >> 4;
        uint minor = offset & 0xf;
        
        version(PrintAsm) writefln("dmaRead %s %s", major, minor);

        if (major >= 0 && major < 7)
        {
            // Per-channel registers
            DmaChannel* channel = &dma.channels[major];

                 if (minor == 0) return channel.base();
            else if (minor == 4) return channel.block_control();
            else if (minor == 8) return channel.control();
            else
            {
                stopError(format("unhandled dmaRead by address 0x%0.8x", offset));
                return 0;
            }
        }
        else if (major == 7)
        {
            // Common DMA registers
                 if (minor == 0) return dma.control;
            else if (minor == 4) return dma.interrupt;
            else
            {
                stopError(format("unhandled dmaRead by address 0x%0.8x", offset));
                return 0;
            }
        }
        else
        {
            stopError(format("unhandled dmaRead by address 0x%0.8x", offset));
            return 0;
        }
    }

    // DMA register write
    void dmaWrite(uint offset, uint value)
    {
        uint major = (offset & 0x70) >> 4;
        uint minor = offset & 0xf;
        
        version(PrintAsm) writefln("dmaWrite %s %s %s", major, minor, value);
        
        DmaPort activePort = DmaPort.None;

        if (major >= 0 && major < 7)
        {
            // Per-channel registers
            DmaPort port = dmaPortFromIndex(major);
            DmaChannel* channel = &dma.channels[port];

                 if (minor == 0) channel.base = value;
            else if (minor == 4) channel.block_control = value;
            else if (minor == 8) channel.control = value;
            else
                stopError(format("unhandled dmaWrite by address 0x%0.8x", offset));
            
            if (channel.active())
                activePort = port;
            else
                activePort = DmaPort.None;
        }
        else if (major == 7)
        {
            activePort = DmaPort.None;
            
            // Common DMA registers
                 if (minor == 0) dma.control = value;
            else if (minor == 4) dma.interrupt = value;
            else
                stopError(format("unhandled dmaWrite by address 0x%0.8x", offset));
        }
        else
            stopError(format("unhandled dmaWrite by address 0x%0.8x", offset));
        
        if (activePort != DmaPort.None)
        {
            dmaTransfer(activePort);
        }
        else
        {
            //writeln("Warning: no active DMA port for dmaTransfer");
        }
    }
    
    // Execute DMA transfer for a port
    void dmaTransfer(DmaPort port)
    {
        DmaChannel* channel = &dma.channels[port];
        
        if (channel.sync == DmaSync.LinkedList)
            dmaLinkedListTransfer(port);
        else
            dmaBlockTransfer(port);
    }
    
    // DMA transfer for linked list synchronization mode
    void dmaLinkedListTransfer(DmaPort port)
    {
        debug writeln("DMA start linked list transfer");
        
        DmaChannel* channel = &dma.channels[port];
        
        auto addr = channel.base() & 0x1ffffc;
        
        if (channel.direction == DmaDirection.ToRam)
        {
            stopError(format("unhandled dmaLinkedListTransfer direction: %s", channel.direction));
        }
        
        if (port != DmaPort.Gpu)
        {
            stopError(format("attempted linked list DMA transfer on port %s", port));
        }
        
        while(1)
        {
            uint header = ram.read32(addr);
            uint remsz = header >> 24;
            while(remsz > 0)
            {
                addr = (addr + 4) & 0x1ffffc;
                uint command = ram.read32(addr);
                gpu.gp0(command);
                remsz -= 1;
            }
            
            if ((header & 0x800000) != 0)
            {
                break;
            }
            
            addr = header & 0x1ffffc;
        }
        
        channel.done();
        
        debug writeln("DMA end linked list transfer");
    }
    
    // DMA transfer for block of data
    void dmaBlockTransfer(DmaPort port)
    {
        debug writeln("DMA start block transfer");
        
        DmaChannel* channel = &dma.channels[port];
        
        int increment;
        if (channel.step == DmaStep.Increment)
            increment = 4;
        else
            increment = -4;
        
        uint adr = channel.base;
        
        uint transferSize = channel.transfer_size;
        
        while (transferSize > 0)
        {
            uint curAddr = adr & 0x1ffffc;
            
            if (channel.direction == DmaDirection.FromRam)
            {
                uint srcWord = ram.read32(curAddr);
                if (port == DmaPort.Gpu)
                {
                    gpu.gp0(srcWord);
                }
                else
                {
                    stopError(format("unhandled dmaBlockTransfer destination port: %s", port));
                }
            }
            else
            {
                uint srcWord;
                if (port == DmaPort.Otc)
                {
                    if (transferSize == 1)
                    {
                        // End of table marker
                        srcWord = 0xffffff;
                    }
                    else
                    {
                        // Pointer to the previous OT entry
                        srcWord = (adr - 4) & 0x1fffff;
                    }
                }
                else
                {
                    stopError(format("unhandled dmaBlockTransfer port: %s", port));
                }
                
                ram.write32(curAddr, srcWord);
            }
            
            adr = adr + increment;
            transferSize--;
        }
        
        channel.done();
        
        debug writeln("DMA end block transfer");
    }

    void runNextInstruction()
    {
        // Save the address of the current instruction to save in
        // `EPC` in case of an exception.
        currentPc = pc;
        
        //writefln("[0x%08x]", pc);

        if (pc % 4 != 0)
        {
            // PC is not correctly aligned!
            exception(PsxException.LoadAddressError);
            return;
        }
        
        if (ignoreBiosCalls && (pc == 0x000000A0 || pc == 0x000000B0 || pc == 0x000000C0))
        {
            // BIOS call, just ignore for now
            nextPc = reg[31];
            pc = nextPc;
            nextPc += 4;
            reg.copyOut();
            return;
        }

        uint instr = load32(pc);

        pc = nextPc;
        nextPc += 4;

        // If the last instruction was a branch then we're in the delay slot
        inDelaySlot = inBranch;
        inBranch = false;

        execute(instr);
        reg.copyOut();
    }

    uint opcode(uint instr)
    {
        return instr >> 26;
    }

    uint rs(uint instr)
    {
        return (instr >> 21) & 0x1f;
    }

    uint rt(uint instr)
    {
        return (instr >> 16) & 0x1f;
    }

    uint rd(uint instr)
    {
        return (instr >> 11) & 0x1f;
    }

    uint immediate16(uint instr)
    {
        return instr & 0xffff;
    }

    uint immediate16se(uint instr)
    {
        short v = cast(short)(instr & 0xffff);
        return v;
    }

    uint shift(uint instr)
    {
        return (instr >> 6) & 0x1f;
    }

    uint funct(uint instr)
    {
        return instr & 0x3f;
    }

    uint jump(uint instr)
    {
        return instr & 0x3ffffff;
    }

    void execute(uint instr)
    {
        uint op = opcode(instr);
        //writefln("[execute 0x%0.8x opc %0.6b rs %0.2s rt %0.2s imm 0x%0.4x]", instr, op, rs(instr), rt(instr), immediate16(instr));

        // TODO: use switch instead of if/else

             if (op == 0b000001) op_bxx(instr);

        else if (op == 0b000010) op_j(instr);
        else if (op == 0b000011) op_jal(instr);

        else if (op == 0b000100) op_beq(instr);
        else if (op == 0b000101) op_bne(instr);
        else if (op == 0b000110) op_blez(instr);
        else if (op == 0b000111) op_bgtz(instr);

        else if (op == 0b001000) op_addi(instr);
        else if (op == 0b001001) op_addiu(instr);
        else if (op == 0b001010) op_slti(instr);
        else if (op == 0b001011) op_sltiu(instr);

        else if (op == 0b001100) op_andi(instr);
        else if (op == 0b001101) op_ori(instr);
        else if (op == 0b001110) op_xori(instr);
        else if (op == 0b001111) op_lui(instr);

        else if (op == 0b010000) op_cop0(instr);
        else if (op == 0b010001) op_cop1(instr);
        else if (op == 0b010010) op_cop2(instr);
        else if (op == 0b010011) op_cop3(instr);

        else if (op == 0b100000) op_lb(instr);
        else if (op == 0b100001) op_lh(instr);
        else if (op == 0b100010) op_lwl(instr);
        else if (op == 0b100011) op_lw(instr);
        else if (op == 0b100100) op_lbu(instr);
        else if (op == 0b100101) op_lhu(instr);
        else if (op == 0b100110) op_lwr(instr);

        else if (op == 0b101000) op_sb(instr);
        else if (op == 0b101001) op_sh(instr);
        else if (op == 0b101010) op_swl(instr);
        else if (op == 0b101011) op_sw(instr);
        else if (op == 0b101110) op_swr(instr);

        else if (op == 0b110000) op_lwc0(instr);
        else if (op == 0b110001) op_lwc1(instr);
        else if (op == 0b110010) op_lwc2(instr);
        else if (op == 0b110011) op_lwc3(instr);

        else if (op == 0b111000) op_swc0(instr);
        else if (op == 0b111001) op_swc1(instr);
        else if (op == 0b111010) op_swc2(instr);
        else if (op == 0b111011) op_swc3(instr);

        else if (op == 0b000000)
        {
            uint sf = funct(instr);

                 if (sf == 0b000000) op_sll(instr);
            else if (sf == 0b000010) op_srl(instr);
            else if (sf == 0b000011) op_sra(instr);
            else if (sf == 0b000100) op_sllv(instr);
            else if (sf == 0b000110) op_srlv(instr);
            else if (sf == 0b000111) op_srav(instr);

            else if (sf == 0b001000) op_jr(instr);
            else if (sf == 0b001001) op_jalr(instr);

            else if (sf == 0b001100) op_syscall(instr);
            else if (sf == 0b001101) op_break(instr);

            else if (sf == 0b010000) op_mfhi(instr);
            else if (sf == 0b010001) op_mthi(instr);
            else if (sf == 0b010010) op_mflo(instr);
            else if (sf == 0b010011) op_mtlo(instr);

            else if (sf == 0b011000) op_mult(instr);
            else if (sf == 0b011001) op_multu(instr);
            else if (sf == 0b011010) op_div(instr);
            else if (sf == 0b011011) op_divu(instr);
            else if (sf == 0b100000) op_add(instr);
            else if (sf == 0b100001) op_addu(instr);
            else if (sf == 0b100010) op_sub(instr);
            else if (sf == 0b100011) op_subu(instr);

            else if (sf == 0b100100) op_and(instr);
            else if (sf == 0b100101) op_or(instr);
            else if (sf == 0b100110) op_xor(instr);
            else if (sf == 0b100111) op_nor(instr);

            else if (sf == 0b101010) op_slt(instr);
            else if (sf == 0b101011) op_stlu(instr);

            else op_illegal(instr);
        }
        else op_illegal(instr);

        //dumpRegisters();
    }

    // Jump
    void op_j(uint instr)
    {
        uint i = jump(instr);
        nextPc = (pc & 0xf0000000) | (i << 2);
        inBranch = true;
        version(PrintAsm) writefln("j 0x%0.8x", nextPc);
    }

    // Add Immediate Unsigned
    void op_addiu(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint v = reg[s] + i;
        reg[t] = v;
        version(PrintAsm) writefln("addiu $%s $%s %s", t, s, i);
    }

    // Add Unsigned
    void op_addu(uint instr)
    {
        uint t = rt(instr);
        uint s = rs(instr);
        uint d = rd(instr);
        uint v = reg[s] + reg[t];
        reg[d] = v;
        version(PrintAsm) writefln("addu $%s $%s $%s", d, s, t);
    }

    // Substract Unsigned
    void op_subu(uint instr)
    {
        uint t = rt(instr);
        uint s = rs(instr);
        uint d = rd(instr);
        uint v = reg[s] - reg[t];
        reg[d] = v;
        version(PrintAsm) writefln("subu $%s $%s $%s", d, s, t);
    }

    // Load Upper Immediate
    void op_lui(uint instr)
    {
        uint i = immediate16(instr);
        uint t = rt(instr);
        uint v = i << 16;
        reg[t] = v;
        version(PrintAsm) writefln("lui $%s %s", t, i);
    }

    // Bitwise Or Immediate
    void op_ori(uint instr)
    {
        uint i = immediate16(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint v = reg[s] | i;
        reg[t] = v;
        version(PrintAsm) writefln("ori $%s $%s %s", t, s, i);
    }

    // Store Word
    void op_sw(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint adr = reg[s] + i;
        uint v = reg[t];
        version(PrintAsm) writefln("sw $%s 0x%0.8x", t, adr);

        if (adr % 4 == 0)
            store32(adr, v);
        else
            exception(PsxException.StoreAddressError);
    }

    // Logical Shift Left
    void op_sll(uint instr)
    {
        uint i = shift(instr);
        uint t = rt(instr);
        uint d = rd(instr);
        uint v = reg[t] << i;
        reg[d] = v;
        version(PrintAsm) writefln("sll $%s $%s %s", d, t, i);
    }

    // Bitwise OR
    void op_or(uint instr)
    {
        uint d = rd(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        uint v = reg[s] | reg[t];
        reg[d] = v;
        version(PrintAsm) writefln("or $%s $%s $%s", d, s, t);
    }

    // Set on Less Than Unsigned
    void op_stlu(uint instr)
    {
        uint d = rd(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        uint v = reg[s] < reg[t];
        reg[d] = v;
        version(PrintAsm) writefln("stlu $%s $%s $%s", d, s, t);
    }

    // Set on Less Than (signed)
    void op_slt(uint instr)
    {
        uint d = rd(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        int v = cast(int)reg[s] < cast(int)reg[t];
        reg[d] = cast(uint)v;
        version(PrintAsm) writefln("stl $%s $%s $%s", d, s, t);
    }

    // Set if Less Than Immediate (signed)
    void op_slti(uint instr)
    {
        int i = cast(int)immediate16se(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        uint v = cast(int)reg[s] < i;
        reg[t] = v;
        version(PrintAsm) writefln("stli $%s $%s %s", t, s, i);
    }

    // Set if Less Than Immediate Unsigned
    void op_sltiu(uint instr)
    {
        uint i = immediate16se(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        uint v = reg[s] < i;
        reg[t] = v;
        version(PrintAsm) writefln("stliu $%s $%s %s", t, s, i);
    }

    // Coprocessor 0 opcode
    void op_cop0(uint instr)
    {
        uint op = rs(instr);

             if (op == 0b00100) op_mtc0(instr);
        else if (op == 0b00000) op_mfc0(instr);
        else if (op == 0b10000) op_rfe(instr);
        else
            stopError(format("unsupported cop0 opcode %0.5b", op));
    }

    // Move to coprocessor 0
    void op_mtc0(uint instr)
    {
        uint t = rt(instr);
        uint d = rd(instr);
        uint v = reg[t];

        version(PrintAsm) writefln("mtc0 $%s $cop0_%s", t, d);

        if (d == 12)
        {
            sr = v;
        }
        else if (d == 3 || d == 5 || d == 6 || d == 7 || d == 9 || d == 11)
        {
            if (v != 0)
                stopError(format("unhandled write to cop0 register %0.8s", d));

            version(DebugMsg) writeln("ignoring write to cop0 breakpoint register");
        }
        else if (d == 13)
        {
            if (v != 0)
                stopError(format("unhandled write to cop0 CAUSE register", d));
        }
        else
            stopError(format("unhandled write to cop0 register %0.8s", d));
    }

    // Move from coprocessor 0
    void op_mfc0(uint instr)
    {
        uint t = rt(instr);
        uint d = rd(instr);
        uint v;

        version(PrintAsm) writefln("mfc0 $%s $cop0_%s", t, d);

        if (d == 12)
        {
            v = sr;
        }
        else if (d == 13)
        {
            v = cause;
        }
        else if (d == 14)
        {
            v = epc;
        }
        else
        {
            stopError(format("unhandled reaf from cop0 register %0.8s", d));
        }

        reg[t] = v;
    }

    // Branch if Equal
    void op_beq(uint instr)
    {
        uint i = immediate16se(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        if (reg[s] == reg[t])
            branch(i);

        version(PrintAsm) writefln("beq $%s $%s 0x%0.8x", s, t, i);
    }

    // Branch if Not Equal
    void op_bne(uint instr)
    {
        uint i = immediate16se(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        if (reg[s] != reg[t])
            branch(i);

        version(PrintAsm) writefln("bne $%s $%s 0x%0.8x", s, t, i);
    }

    // Add Immediate
    void op_addi(uint instr)
    {
        int i = cast(int)immediate16se(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        int ss = cast(int)reg[s];
        bool overflow;
        int v = core.checkedint.adds(ss, i, overflow);

        version(PrintAsm) writefln("addi $%s $%s %s", t, s, i);

        if (overflow)
        { 
            exception(PsxException.Overflow);
        }
        else
            reg[t] = v;
    }

    // Load Word
    void op_lw(uint instr)
    {
        if ((sr & 0x10000) != 0)
        {
            version(DebugMsg) writeln("ignoring load while cache is isolated");
            return;
        }
        uint i = immediate16se(instr);
        uint s = rs(instr);
        uint t = rt(instr);
        uint addr = reg[s] + i;

        version(PrintAsm) writefln("lw $%s 0x%0.8x", t, addr);

        if (addr % 4 == 0)
        {
            uint v = load32(addr);
            reg[t] = v;
        }
        else
            exception(PsxException.LoadAddressError);
    }

    // Store Halfword
    void op_sh(uint instr)
    {
        if ((sr & 0x10000) != 0)
        {
            version(DebugMsg) writeln("ignoring store while cache is isolated");
            return;
        }

        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint addr = reg[s] + i;
        uint v = reg[t];

        version(PrintAsm) writefln("sh $%s 0x%0.8x", t, addr);

        if (addr % 2 == 0)
            store16(addr, cast(ushort)v);
        else
            exception(PsxException.StoreAddressError);
    }

    // Jump And Link
    void op_jal(uint instr)
    {
        uint ra = nextPc;
        reg[31] = ra; // Store return address in $31 ($ra)

        version(PrintAsm) writefln("jal");

        op_j(instr);
    }

    // Bitwise And Immediate
    void op_andi(uint instr)
    {
        uint i = immediate16(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint v = reg[s] & i;
        reg[t] = v;

        version(PrintAsm) writefln("andi $%s $%s %s", t, s, i);
    }

    // Bitwise And
    void op_and(uint instr)
    {
        uint d = rd(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint v = reg[s] & reg[t];
        reg[d] = v;

        version(PrintAsm) writefln("and $%s $%s $%s", d, s, t);
    }

    // Store Byte
    void op_sb(uint instr)
    {
        if ((sr & 0x10000) != 0)
        {
            version(DebugMsg) writeln("ignoring store while cache is isolated");
            return;
        }

        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint addr = reg[s] + i;
        uint v = reg[t];

        version(PrintAsm) writefln("sb $%s 0x%0.8x", t, addr);

        store8(addr, cast(ubyte)v);
    }

    // Jump Register
    void op_jr(uint instr)
    {
        uint s = rs(instr);
        nextPc = reg[s];

        inBranch = true;

        version(PrintAsm) writefln("jr $%s", s);
    }

    // Jump And Link Register
    void op_jalr(uint instr)
    {
        uint d = rd(instr);
        uint s = rs(instr);

        reg[d] = nextPc; // Store return address in `d`
        nextPc = reg[s];

        inBranch = true;

        version(PrintAsm) writefln("jalr $%s $%s", d, s);
    }

    // Load Byte (signed)
    void op_lb(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint addr = reg[s] + i;

        version(PrintAsm) writefln("lb $%s 0x%0.8x", t, addr);

        // Cast as i8 to force sign extension
        byte v = cast(byte)load8(addr);
        reg[t] = cast(uint)v;
    }

    // Load Byte (unsigned)
    void op_lbu(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);
        uint addr = reg[s] + i;

        version(PrintAsm) writefln("lbu $%s 0x%0.8x", t, addr);

        ubyte v = load8(addr);
        reg[t] = v;
    }

    // Add and generate an exception on overflow
    void op_add(uint instr)
    {
        uint t = rt(instr);
        uint s = rs(instr);
        uint d = rd(instr);

        int ss = cast(int)reg[s];
        int tt = cast(int)reg[t];

        bool overflow;
        int v = core.checkedint.adds(ss, tt, overflow);

        version(PrintAsm) writefln("add $%s $%s $%s", d, s, t);

        if (overflow) 
            exception(PsxException.Overflow);
        else
            reg[d] = v;
    }

    // Branch if Greater Than Zero
    void op_bgtz(uint instr)
    {
        uint i = immediate16se(instr);
        uint s = rs(instr);
        int v = cast(int)reg[s];

        if (v > 0)
            branch(i);

        version(PrintAsm) writefln("bgtz $%s 0x%0.8x", s, i);
    }

    // Branch if Less than or Equal to Zero
    void op_blez(uint instr)
    {
        uint i = immediate16se(instr);
        uint s = rs(instr);
        int v = cast(int)reg[s];

        if (v <= 0)
            branch(i);

        version(PrintAsm) writefln("blez $%s 0x%0.8x", s, i);
    }

    // Various branch instructions: BGEZ, BLTZ, BGEZAL, BLTZAL.
    // Bits 16 and 20 are used to figure out which one to use.
    void op_bxx(uint instr)
    {
        uint i = immediate16se(instr);
        uint s = rs(instr);

        uint is_bgez = (instr >> 16) & 1;
        uint is_link = ((instr >> 17) & 0xf) == 8;

        int v = cast(int)reg[s];

        // Test "less than zero"
        uint test = (v < 0);

        // If the test is "greater than or equal to zero" we need
        // to negate the comparison above since
        // ("a >= 0" <=> "!(a < 0)"). The xor takes care of that.
        test = test ^ is_bgez;

        if (is_link)
        {
            // Store return address in R31
            reg[31] = pc;
        }

        if (test != 0)
        {
            branch(i);
        }

        version(PrintAsm) writefln("bxx $%s 0x%0.8x", s, i);
    }

    // Shift Right Arithmetic
    void op_sra(uint instr)
    {
        uint i = shift(instr);
        uint t = rt(instr);
        uint d = rd(instr);

        int v = (cast(int)reg[t]) >> i;

        reg[d] = cast(uint)v;

        version(PrintAsm) writefln("sra $%s $%s %s", d, t, i);
    }

    // Shift Right Logical
    void op_srl(uint instr)
    {
        uint i = shift(instr);
        uint t = rt(instr);
        uint d = rd(instr);

        uint v = reg[t] >> i;

        reg[d] = v;

        version(PrintAsm) writefln("srl $%s $%s %s", d, t, i);
    }

    // Divide (signed)
    void op_div(uint instr)
    {
        uint s = rs(instr);
        uint t = rt(instr);

        int n = cast(int)reg[s];
        int d = cast(int)reg[t];

        if (d == 0)
        {
            // Division by zero, results are bogus
            hi = cast(uint)n;

            if (n >= 0)
                lo = 0xffffffff;
            else
                lo = 1;
        }
        else if (cast(uint)n == 0x80000000 && d == -1)
        {
            // Result is not representable in a 32bit signed integer
            hi = 0;
            lo = 0x80000000;
        }
        else
        {
            hi = cast(uint)(n % d);
            lo = cast(uint)(n / d);
        }

        version(PrintAsm) writefln("div $%s $%s", s, t);
    }

    // Divide Unsigned
    void op_divu(uint instr)
    {
        uint s = rs(instr);
        uint t = rt(instr);

        uint n = reg[s];
        uint d = reg[t];

        if (d == 0)
        {
            // Division by zero, results are bogus
            hi = n;
            lo = 0xffffffff;
        }
        else
        {
            hi = n % d;
            lo = n / d;
        }

        version(PrintAsm) writefln("divu $%s $%s", s, t);
    }

    // Move From LO
    void op_mflo(uint instr)
    {
        uint d = rd(instr);
        reg[d] = lo;

        version(PrintAsm) writefln("mflo $%s", d);
    }

    // Move From HI
    void op_mfhi(uint instr)
    {
        uint d = rd(instr);
        reg[d] = hi;

        version(PrintAsm) writefln("mfhi $%s", d);
    }

    // System Call
    void op_syscall(uint instr)
    {
        exception(PsxException.SysCall);

        version(PrintAsm) writeln("syscall");
    }

    // Move to LO
    void op_mtlo(uint instr)
    {
        uint s = rs(instr);
        lo = reg[s];

        version(PrintAsm) writefln("mtlo $%s", s);
    }

    // Move to HI
    void op_mthi(uint instr)
    {
        uint s = rs(instr);
        hi = reg[s];

        version(PrintAsm) writefln("mthi $%s", s);
    }

    // Return From Exception
    void op_rfe(uint instr)
    {
        // There are other instructions with the same encoding but all
        // are virtual memory related and the Playstation doesn't
        // implement them. Still, let's make sure we're not running
        // buggy code.
        if ((instr & 0x3f) != 0b010000)
        {
            stopError(format("invalid cop0 instruction 0x%08x", instr));
        }

        // Restore the pre-exception mode by shifting the Interrupt
        // Enable/User Mode stack back to its original position.
        uint mode = sr & 0x3f;
        sr &= !0x3f;
        sr |= mode >> 2;

        version(PrintAsm) writefln("rfe");
    }

    // Load Halfword Unsigned
    void op_lhu(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint addr = reg[s] + i;

        // Address must be 16bit aligned
        if (addr % 2 == 0)
        {
            uint v = load16(addr);
            reg[t] = v;
        }
        else 
            exception(PsxException.LoadAddressError);
    }

    // Shift Left Logical Variable
    void op_sllv(uint instr)
    {
        uint d = rd(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        // Shift amount is truncated to 5 bits
        uint v = reg[t] << (reg[s] & 0x1f);

        reg[d] = v;
    }

    // Load Halfword (signed)
    void op_lh(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint addr = reg[s] + i;

        // Cast as i16 to force sign extension
        short v = cast(short)load16(addr);

        reg[t] = cast(uint)v;
    }

    // Bitwise Not Or
    void op_nor(uint instr)
    {
        uint d = rd(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint v = !(reg[s] | reg[t]);

        reg[d] = v;
    }

    // Shift Right Arithmetic Variable
    void op_srav(uint instr)
    {
        uint d = rd(instr);
        uint s = rs(instr);
        uint t = rt(instr);

        // Shift amount is truncated to 5 bits
        uint v = (cast(int)reg[t]) >> (reg[s] & 0x1f);

        reg[d] = cast(uint)v;
    }

    // Shift Right Logical Variable
    void op_srlv(uint instr)
    {
        uint d = rd(instr);
        uint s = rs(instr);
        uint t = rt(instr);

        // Shift amount is truncated to 5 bits
        uint v = reg[t] >> (reg[s] & 0x1f);

        reg[d] = v;
    }

    // Multiply Unsigned
    void op_multu(uint instr)
    {
        uint s = rs(instr);
        uint t = rt(instr);

        ulong a = reg[s];
        ulong b = reg[t];
        ulong v = a * b;

        hi = cast(uint)(v >> 32);
        lo = cast(uint)v;
    }

    // Bitwise Exclusive Or
    void op_xor(uint instr)
    {
        uint d = rd(instr);
        uint s = rs(instr);
        uint t = rt(instr);

        uint v = reg[s] ^ reg[t];

        reg[d] = v;
    }

    // Break
    void op_break(uint instr)
    {
        exception(PsxException.Break);
    }

    // Multiply (signed)
    void op_mult(uint instr)
    {
        uint s = rs(instr);
        uint t = rt(instr);

        long a = cast(long)(cast(int)reg[s]);
        long b = cast(long)(cast(int)reg[t]);

        ulong v = cast(ulong)(a * b);

        hi = cast(uint)(v >> 32);
        lo = cast(uint)v;
    }

    // Substract and check for signed overflow
    void op_sub(uint instr)
    {
        uint s = rs(instr);
        uint t = rt(instr);
        uint d = rd(instr);

        int ss = cast(int)reg[s];
        int tt = cast(int)reg[t];

        bool overflow;
        int v = core.checkedint.subs(ss, tt, overflow);

        if (overflow) 
            exception(PsxException.Overflow);
        else
            reg[d] = v;
    }

    // Bitwise eXclusive Or Immediate
    void op_xori(uint instr)
    {
        uint i = immediate16(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint v = reg[s] ^ i;

        reg[t] = v;
    }

    // Coprocessor 1 opcode (does not exist on the Playstation)
    void op_cop1(uint instr)
    {
        exception(PsxException.CoprocessorError);
    }

    // Coprocessor 2 opcode (GTE)
    void op_cop2(uint instr)
    {
        // TODO
        stopError(format("unhandled cop2 (GTE) instruction: 0x%08x", instr));
    }

    // Coprocessor 3 opcode (does not exist on the Playstation)
    void op_cop3(uint instr)
    {
        exception(PsxException.CoprocessorError);
    }

    // Load Word Left (little-endian only implementation)
    void op_lwl(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint addr = reg[s] + i;

        // This instruction bypasses the load delay restriction: this
        // instruction will merge the new contents with the value
        // currently being loaded if need be.
        uint cur_v = reg._out_regs[t];

        // Next we load the *aligned* word containing the first
        // addressed byte
        uint aligned_addr = addr & !3;
        uint aligned_word = load32(aligned_addr);

        // Depending on the address alignment we fetch the 1, 2, 3 or
        // 4 *most* significant bytes and put them in the target
        // register.
        uint v;
        switch(addr & 3)
        {
            case 0: v = (cur_v & 0x00ffffff) | (aligned_word << 24); break;
            case 1: v = (cur_v & 0x0000ffff) | (aligned_word << 16); break;
            case 2: v = (cur_v & 0x000000ff) | (aligned_word << 8); break;
            case 3: v = (cur_v & 0x00000000) | (aligned_word << 0); break;
            default: break;
        }

        reg[t] = v;
    }

    // Load Word Right (little-endian only implementation)
    void op_lwr(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint addr = reg[s] + i;

        // This instruction bypasses the load delay restriction: this
        // instruction will merge the new contents with the value
        // currently being loaded if need be.
        uint cur_v = reg._out_regs[t];

        // Next we load the *aligned* word containing the first
        // addressed byte
        uint aligned_addr = addr & !3;
        uint aligned_word = load32(aligned_addr);

        // Depending on the address alignment we fetch the 1, 2, 3 or
        // 4 *least* significant bytes and put them in the target
        // register.
        uint v;
        switch(addr & 3)
        {
            case 0: v = (cur_v & 0x00000000) | (aligned_word >> 0); break;
            case 1: v = (cur_v & 0xff000000) | (aligned_word >> 8); break;
            case 2: v = (cur_v & 0xffff0000) | (aligned_word >> 16); break;
            case 3: v = (cur_v & 0xffffff00) | (aligned_word >> 24); break;
            default: break;
        }

        reg[t] = v;
    }

    // Store Word Left (little-endian only implementation)
    void op_swl(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint addr = reg[s] + i;
        uint v = reg[t];

        uint aligned_addr = addr & !3;
        // Load the current value for the aligned word at the target address
        uint cur_mem = load32(aligned_addr);

        uint mem;
        switch(addr & 3)
        {
            case 0: mem = (cur_mem & 0xffffff00) | (v >> 24); break;
            case 1: mem = (cur_mem & 0xffff0000) | (v >> 16); break;
            case 2: mem = (cur_mem & 0xff000000) | (v >> 8); break;
            case 3: mem = (cur_mem & 0x00000000) | (v >> 0); break;
            default: break;
        }

        store32(aligned_addr, mem);
    }

    // Store Word Right (little-endian only implementation)
    void op_swr(uint instr)
    {
        uint i = immediate16se(instr);
        uint t = rt(instr);
        uint s = rs(instr);

        uint addr = reg[s] + i;
        uint v = reg[t];

        uint aligned_addr = addr & !3;
        // Load the current value for the aligned word at the target address
        uint cur_mem = load32(aligned_addr);

        uint mem;
        switch(addr & 3)
        {
            case 0: mem = (cur_mem & 0000000000) | (v << 0); break;
            case 1: mem = (cur_mem & 0x000000ff) | (v << 8); break;
            case 2: mem = (cur_mem & 0x0000ffff) | (v << 16); break;
            case 3: mem = (cur_mem & 0x00ffffff) | (v << 24); break;
            default: break;
        }

        store32(aligned_addr, mem);
    }

    // Load Word in Coprocessor 0
    void op_lwc0(uint instr)
    {
        // Not supported by this coprocessor
        exception(PsxException.CoprocessorError);
    }

    // Load Word in Coprocessor 1
    void op_lwc1(uint instr)
    {
        // Not supported by this coprocessor
        exception(PsxException.CoprocessorError);
    }

    // Load Word in Coprocessor 2
    void op_lwc2(uint instr)
    {
        // TODO
        stopError(format("unhandled GTE LWC instruction: 0x%08x", instr));
    }

    // Load Word in Coprocessor 3
    void op_lwc3(uint instr)
    {
        // Not supported by this coprocessor
        exception(PsxException.CoprocessorError);
    }

    // Store Word in Coprocessor 0
    void op_swc0(uint instr)
    {
        // Not supported by this coprocessor
        exception(PsxException.CoprocessorError);
    }

    // Store Word in Coprocessor 1
    void op_swc1(uint instr)
    {
        // Not supported by this coprocessor
        exception(PsxException.CoprocessorError);
    }

    // Store Word in Coprocessor 2
    void op_swc2(uint instr)
    {
        // TODO
        stopError(format("unhandled GTE SWC instruction: 0x%08x", instr));
    }

    // Store Word in Coprocessor 3
    void op_swc3(uint instr)
    {
        // Not supported by this coprocessor
        exception(PsxException.CoprocessorError);
    }

    // Illegal instruction
    void op_illegal(uint instr)
    {
        writefln("illegal instruction: 0x%08x at 0x%08x", instr, currentPc);
        exception(PsxException.IllegalInstruction);
        //stop();
    }

    void dumpRegisters()
    {
        writeln(reg._regs);
        writefln("pc: %s sr: %s", pc, sr);
        writeln("---------");
    }
}
