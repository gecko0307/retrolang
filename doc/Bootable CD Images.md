# Bootable CD Images

Generating PlayStation CDs is largely outside of Retrolang's scope, but Retrobuild supports [mkpsxiso](https://github.com/lameguy64/mkpsxiso) for this task. mkpsxiso uses a simple XML description of the disc and outputs standard BIN+CUE ready to burn or use in an emulator.

A simplest XML file for a CD containing `PSX.EXE` and `SYSTEM.CNF` looks like this:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<iso_project image_name="game.bin" cue_sheet="game.cue">
    <track type="data" xa_edc="true" new_type="false">
        <identifiers
            system ="PLAYSTATION"
            application ="PLAYSTATION"
            volume ="GAME"
        />
        <license file="license.dat"/>
        <directory_tree>
            <file name="SYSTEM.CNF" type="data" source="iso/SYSTEM.CNF" order="0"/>
            <file name="PSX.EXE" type="data" source="iso/PSX.EXE" order="1"/>
            <dummy sectors="1024"/>
        </directory_tree>
    </track>
</iso_project>
```

## Boot Requirements

It is strongly recommended to add `SYSTEM.CNF` that provides boot information to the BIOS:

```
BOOT=cdrom:\PSX.EXE;1
TCB=4
EVENT=10
STACK=801FFF00
```

`BOOT` parameter must point to the executable file. It can be named arbitrarily, but all examples in the Retrolang repository use `PSX.EXE` for clarity. `STACK` parameter **must** be `801FFF00` unless you modify linker's defaults in RLC. There's currently no way to set custom stack address without rebuilding the compiler.

If there's no `SYSTEM.CNF` (or if `BOOT` parameter is not specified) then BIOS will try to load `PSX.EXE` with default stack address `801FFF00`.

## License File (*.dat)

License file is necessary to run the CD on a real PlayStation. A modchipped console will skip checking the actual license data, but at least TMD model for the black bootup screen must be present. On licensed CDs it is a colorful 3D "PS" logo. Retrolang SDK cannot provide a license file containing copyrighted material by Sony, so instead it includes a [replacement](https://github.com/gecko0307/retrolang/blob/main/examples/licenses/default.dat). You can also generate a custom license file using the DATWrite tool, but creating a compatible TMD is a challenging task in itself. Retrolang provides an exporter for Blender 4.5 to make things easier.
