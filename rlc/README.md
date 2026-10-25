# Retrolang Compiler

Work-in-progress compiler/assembler/linker for Retrolang. Written in [D](https://dlang.org).

Building:

```
dub build --build=release-nobounds
```

Usage:

```
rlc -o PSX.EXE src/main.r
```

Use `--include` and `--data` to specify additional search directories (separated by `;`), `--region` to select the PS-X EXE region, and `--map` to write linked symbol addresses to a map file. Run `rlc --help` for the full option list.
