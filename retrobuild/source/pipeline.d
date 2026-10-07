module pipeline;

import std.file: exists, mkdirRecurse;
import std.path: dirName, relativePath;

import errors;
import exec;
import log;
import manifest;
import tools;

/// Path shown to the user, relative to the project directory.
private string display(ref const Manifest m, string path)
{
    return relativePath(path, m.baseDir);
}

/// Runs the commands configured for a hook (e.g. "pre_compile"), if any.
void runHooks(Manifest m, string hook)
{
    if (auto commands = hook in m.hooks)
    {
        foreach (argv; *commands)
        {
            verbose("Running hook " ~ hook);
            runChecked(argv, m.baseDir, "Hook \"" ~ hook ~ "\" (" ~ argv[0] ~ ")");
        }
    }
}

/// Stage 1: compile the entry source into the PS1 executable.
void compileStage(Manifest m)
{
    // Fail fast on a missing compiler, before any hook runs.
    auto rlc = requireTool(rlcTool, m.toolPaths);

    runHooks(m, "pre_compile");

    // Checked after pre_compile on purpose: a hook may generate the source.
    if (!exists(m.source))
        throw new RetrobuildException("Source file not found: " ~ display(m, m.source));

    info("Compiling " ~ display(m, m.executable) ~ "...");
    mkdirRecurse(dirName(m.executable));

    string[] argv = [rlc.path] ~ m.rlcArgs ~ ["-o", m.executable, m.source];
    runChecked(argv, m.baseDir, "rlc");

    runHooks(m, "post_compile");
}

/// Stage 2: pack the executable into a CD-ROM image with mkpsxiso.
///
/// If `required` is false (full pipeline) a missing mkpsxiso is only a
/// warning and the function returns false, meaning "image not built".
/// If `required` is true (explicit `iso` command) it is an error.
bool isoStage(Manifest m, bool required)
{
    auto mk = required
        ? requireTool(mkpsxisoTool, m.toolPaths)
        : optionalTool(mkpsxisoTool, m.toolPaths);

    if (!mk.found)
    {
        warning("mkpsxiso not found, omitting CD-ROM image generation");
        return false;
    }

    runHooks(m, "pre_iso");

    if (!exists(m.executable))
        throw new RetrobuildException(
            "Executable not found: " ~ display(m, m.executable) ~ " (run \"retrobuild compile\" first)");
    if (!exists(m.isoXml))
        throw new RetrobuildException("ISO description not found: " ~ display(m, m.isoXml));

    info("Building CD-ROM image...");
    runChecked([mk.path, "-y", m.isoXml], m.baseDir, "mkpsxiso");

    if (!exists(m.cue))
        warning("mkpsxiso did not produce " ~ display(m, m.cue)
            ~ "; check that \"cue\" in the manifest matches iso.xml");

    runHooks(m, "post_iso");
    return true;
}
