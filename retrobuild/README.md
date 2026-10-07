# Retrobuild

Retrobuild is the build automation system for the Retrolang SDK. It compiles a Retrolang project into a PlayStation 1 executable, packs it into a CD-ROM image, and generates a CU2 sector index for PSIO.

## Usage

```
retrobuild [command] [options]
```

| Command | Description |
|---|---|
| `build` (default) | Run the full pipeline: compile, ISO, CU2 |
| `compile` | Run only the compile stage |
| `iso` | Run only the ISO stage (requires an existing executable) |
| `cu2 <file.cue>` | Convert a CUE sheet to CU2 (standalone, no project needed) |
| `init <name>` | Scaffold a new project in `./<name>` |
| `clean` | Remove generated outputs |
| `doctor` | Report which tools were found and where |

Global options:

| Option | Description |
|---|---|
| `-C <dir>` | Run as if started in `<dir>` |
| `-m <file>` | Use a specific manifest file |
| `-v`, `--verbose` | Print every external command line before running it |
| `-q`, `--quiet` | Print errors only |
| `--no-iso` | Skip ISO and CU2 stages |
| `--no-cu2` | Skip CU2 stage |
| `--version`, `--help` | Standard |

Running `retrobuild` with no arguments is equivalent to `retrobuild build`.

## Build Pipeline

`build` runs the following stages in order. A failed stage aborts the pipeline and returns a non-zero exit code.

| # | Stage | Action | If tool is missing |
|---|---|---|---|
| 1 | compile | `rlc -o <output.exe> <source>` | **Error** |
| 2 | iso | `mkpsxiso -y <iso_xml>` | **Warning**, pipeline ends successfully with the compiled executable only |
| 3 | cu2 | Native conversion of `<cue>` to `<cu2>` | n/a (built in) |

Notes:

- The output directory of the executable (default `iso/`) is created if it does not exist.
- Stage 3 runs only if stage 2 ran and produced the CUE file.
- Retrobuild passes through the stdout/stderr of external tools unchanged.
- `rlc` and `mkpsxiso` exit codes are propagated (see section 9).

## Project Layout and Defaults

```
myproject/
├── retrobuild.toml     (optional)
├── iso.xml
├── iso/
│   └── PSX.EXE         (generated)
├── src/
│   └── main.r
├── game.bin            (generated)
├── game.cue            (generated)
└── game.cu2            (generated)
```

Default values (used when no manifest or key is present):

| Key | Default |
|---|---|
| `source` | `src/main.r` |
| `executable` | `iso/PSX.EXE` |
| `iso_xml` | `iso.xml` |
| `cue` | `game.cue` |
| `cu2` | same as `cue` with extension `.cu2` |

## Manifest (`retrobuild.toml`)

Optional. TOML format. Unknown keys are an error (to catch typos).

```toml
# Entry point passed to rlc
source = "src/main.r"

# Compiler output, also the file mkpsxiso packs (must match iso.xml)
executable = "iso/PSX.EXE"

# mkpsxiso project description
iso_xml = "iso.xml"

# CUE sheet produced by mkpsxiso (must match iso.xml)
cue = "game.cue"

# Extra arguments forwarded to rlc
rlc_args = []

[tools]
# Explicit tool paths (highest priority in discovery)
# rlc = "C:/retrolang/rlc/rlc.exe"
# mkpsxiso = "/opt/mkpsxiso/mkpsxiso"

[hooks]
# Optional commands run before/after stages; each is an argv array
# pre_compile = [[ ]]
# post_iso    = [[ ]]
```

All paths are relative to the manifest's directory. Forward slashes are accepted on all platforms.

### Hooks

Hook names: `pre_compile`, `post_compile`, `pre_iso`, `post_iso`, `pre_cu2`, `post_cu2`. Each is a list of argv arrays, executed in order, without a shell. A non-zero exit code aborts the build. Hooks are the intended escape hatch for custom steps such as asset conversion.

A hook entry is either an argv array, or a table that also sets the working directory:

```toml
[hooks]
pre_compile = [
  { run = ["cmd", "/c", "convert.bat"], cwd = "assets" },
]
```

`cwd` is relative to the manifest directory and defaults to it. A program path containing a directory separator is resolved relative to the hook's `cwd` on all platforms; bare names use the normal PATH lookup. Within one hook list, use either all arrays or all tables (TOML 0.5 forbids mixed-type arrays).

## Tool discovery

For each external tool (`rlc`, `mkpsxiso`), Retrobuild resolves the executable in this order and uses the first match:

1. `[tools]` entry in the manifest.
2. Environment variable: `RETROLANG_RLC`, `RETROLANG_MKPSXISO` (explicit per-tool override).
3. Retrolang SDK root, taken from `RETROLANG_HOME` if set, otherwise from the directory containing the `retrobuild` executable. Within the SDK root the tool is looked up at:
   - `rlc`: `<root>/rlc/rlc[.exe]`
   - `mkpsxiso`: `<root>/mkpsxiso/mkpsxiso[.exe]`
4. `PATH`.

Behavior:

- The `.exe` suffix is added automatically on Windows.
- With `--verbose`, the chosen path and the discovery step that found it are printed.
- `retrobuild doctor` prints the result for every tool, including "not found" with the locations searched.

## CU2 generation

`retrobuild cu2 <file.cue> [-o <file.cu2>]` converts a CUE sheet and its referenced BIN into the binary CU2 index table used by PSIO.

- Input: a CUE sheet referencing one BIN file, resolved relative to the CUE file.
- Output: `<name>.cu2` next to the CUE file unless `-o` is given.
- Existing outputs are overwritten.
- Errors (missing BIN, unsupported CUE constructs, multi-file sheets if unsupported) are reported with the offending line number where applicable.
- The existing `cue2cu2.py` is the reference implementation for the output format. Retrobuild's output should be byte-identical to it for the same input; this is the acceptance test.
- Implemented as an independent module with no dependency on the rest of the tool, so it can be reused or tested alone.

## Scaffolding (`init`)

`retrobuild init <name>` creates:

- `src/main.r`: minimal "hello" program
- `iso.xml`: minimal mkpsxiso description referencing `iso/PSX.EXE` and producing `game.bin` / `game.cue`
- `retrobuild.toml`: commented example with defaults
- `.gitignore`: ignores `iso/PSX.EXE`, `game.bin`, `game.cue`, `game.cu2`

It refuses to write into a non-empty directory unless `--force` is given.

## Clean

`retrobuild clean` removes `executable`, the BIN referenced by the CUE sheet, the CUE file, and the CU2 file. It deletes only files it knows it produces and never recurses into directories.
