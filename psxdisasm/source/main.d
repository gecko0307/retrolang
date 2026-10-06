import std.stdio;
import std.file;

import psyqobj;
import section;
import psxexe;
import disasm;

int main(string[] args)
{
    if (args.length < 2)
    {
        writeln("No input file specified.");
        return 1;
    }
    
    string objFilename = args[1];
    
    writefln("File: %s", objFilename);
    
    ubyte[] binary = cast(ubyte[])std.file.read(objFilename);
    if (binary.length < 8)
    {
        writeln("Unknown file type!");
        return 1;
    }
    
    string fileStart = cast(string)binary[0..8];
    if (fileStart[0..3] == "LNK")
    {
        // PsyQ object file
        writefln("LNK format object file");
        
        PsyqObject obj = new PsyqObject(binary);
        
        foreach(name, section; obj.sectionsByName)
        {
            if (section.data.length > 0)
            {
                writefln("Section %s (%s):", name, section.index);
                if (section.name == ".text")
                {
                    if (section.data.length > 0)
                    {
                        auto disassembler = new MipsDisassembler(cast(uint[])section.data);
                    }
                }
                else
                {
                    writefln("  \"%s\"", cast(string)section.data);
                }
            }
        }
        
        if (obj.parsed)
            return 0;
        else
            return 1;
    }
    else if (fileStart == "PS-X EXE")
    {
        PsxExe exe;
        try
            exe = new PsxExe(binary);
        catch (Exception e)
        {
            writefln("Invalid PSX-EXE: %s", e.msg);
            return 1;
        }

        writefln("PSX-EXE (%s)", exe.region);
        writefln("  Entry PC:  0x%08X", exe.pc);
        writefln("  GP:        0x%08X", exe.gp);
        writefln("  Load addr: 0x%08X", exe.loadAddr);
        writefln("  Text size: 0x%X bytes", exe.code.length * 4);
        if (exe.spBase != 0)
            writefln("  SP:        0x%08X", exe.spBase + exe.spOffset);
        if (exe.bssSize != 0)
            writefln("  BSS:       0x%08X (0x%X bytes)", exe.bssAddr, exe.bssSize);

        //auto disassembler = new MipsDisassembler(exe.trimmedCode.dup);
        auto disassembler = new MipsDisassembler(exe.code, exe.loadAddr, exe.pc);
        return 0;
    }
    else
    {
        writeln("Unknown file type!");
        return 1;
    }
}
