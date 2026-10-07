module manifest;

import std.algorithm : canFind;
import std.file : exists, getcwd, readText;
import std.path : absolutePath, buildNormalizedPath, buildPath, dirName, setExtension;

import toml;

import errors;

enum manifestFileName = "retrobuild.toml";

private immutable string[] knownToolNames = ["rlc", "mkpsxiso"];
private immutable string[] knownHookNames = [
    "pre_compile", "post_compile", "pre_iso", "post_iso", "pre_cu2", "post_cu2"
];

/// Project configuration. All paths are absolute and normalized after loading.
struct Manifest
{
    string baseDir;                 // directory all relative paths are resolved against
    string source     = "src/main.r";
    string executable = "iso/PSX.EXE";
    string isoXml     = "iso.xml";
    string cue        = "game.cue";
    string cu2;                     // derived from `cue` when not set
    string[] rlcArgs;
    string[string] toolPaths;       // [tools]
    string[][][string] hooks;       // [hooks]: hook name -> list of argv arrays
}

/// Loads the manifest. With an explicit path the file must exist; otherwise
/// ./retrobuild.toml is used if present, and defaults apply if it is not.
Manifest loadManifest(string explicitPath)
{
    string path;
    if (explicitPath.length)
    {
        path = buildNormalizedPath(absolutePath(explicitPath));
        if (!exists(path))
            throw new RetrobuildException("Manifest not found: " ~ explicitPath);
    }
    else
    {
        auto candidate = buildPath(getcwd(), manifestFileName);
        if (exists(candidate))
            path = candidate;
    }

    Manifest m;
    m.baseDir = path.length ? dirName(path) : getcwd();

    if (path.length)
        parseInto(m, path);

    if (m.cu2.length == 0)
        m.cu2 = setExtension(m.cue, ".cu2");

    // Resolve everything against the manifest directory once, so the rest of
    // the program never depends on the current directory.
    m.source     = resolve(m, m.source);
    m.executable = resolve(m, m.executable);
    m.isoXml     = resolve(m, m.isoXml);
    m.cue        = resolve(m, m.cue);
    m.cu2        = resolve(m, m.cu2);
    foreach (name; m.toolPaths.keys)
        m.toolPaths[name] = resolve(m, m.toolPaths[name]);

    return m;
}

private string resolve(ref const Manifest m, string p)
{
    return buildNormalizedPath(absolutePath(p, m.baseDir));
}

private void fail(string file, string msg)
{
    throw new RetrobuildException(file ~ ": " ~ msg);
}

private string asString(TOMLValue v, string key, string file)
{
    if (v.type != TOML_TYPE.STRING)
        fail(file, "\"" ~ key ~ "\" must be a string");
    return v.str;
}

private string[] asStringArray(TOMLValue v, string key, string file)
{
    if (v.type != TOML_TYPE.ARRAY)
        fail(file, "\"" ~ key ~ "\" must be an array of strings");
    string[] result;
    foreach (e; v.array)
    {
        if (e.type != TOML_TYPE.STRING)
            fail(file, "\"" ~ key ~ "\" must contain only strings");
        result ~= e.str;
    }
    return result;
}

private void parseInto(ref Manifest m, string file)
{
    TOMLDocument doc;
    try
        doc = parseTOML(readText(file));
    catch (Exception e)
        throw new RetrobuildException(file ~ ": " ~ e.msg);

    // Unknown keys are an error, to catch typos (spec, section 7).
    foreach (key, value; doc.table)
    {
        switch (key)
        {
            case "source":     m.source     = asString(value, key, file); break;
            case "executable": m.executable = asString(value, key, file); break;
            case "iso_xml":    m.isoXml     = asString(value, key, file); break;
            case "cue":        m.cue        = asString(value, key, file); break;
            case "cu2":        m.cu2        = asString(value, key, file); break;
            case "rlc_args":   m.rlcArgs    = asStringArray(value, key, file); break;

            case "tools":
                if (value.type != TOML_TYPE.TABLE)
                    fail(file, "\"tools\" must be a table");
                foreach (name, v; value.table)
                {
                    if (!knownToolNames.canFind(name))
                        fail(file, "unknown key \"tools." ~ name ~ "\"");
                    m.toolPaths[name] = asString(v, "tools." ~ name, file);
                }
                break;

            case "hooks":
                if (value.type != TOML_TYPE.TABLE)
                    fail(file, "\"hooks\" must be a table");
                foreach (name, v; value.table)
                {
                    if (!knownHookNames.canFind(name))
                        fail(file, "unknown key \"hooks." ~ name ~ "\"");
                    if (v.type != TOML_TYPE.ARRAY)
                        fail(file, "\"hooks." ~ name ~ "\" must be an array of argument arrays");
                    string[][] commands;
                    foreach (cmd; v.array)
                    {
                        auto argv = asStringArray(cmd, "hooks." ~ name, file);
                        if (argv.length == 0)
                            fail(file, "\"hooks." ~ name ~ "\" contains an empty command");
                        commands ~= argv;
                    }
                    m.hooks[name] = commands;
                }
                break;

            default:
                fail(file, "unknown key \"" ~ key ~ "\"");
                break;
        }
    }
}
