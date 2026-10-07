module tools;

import std.array: split;
import std.file: exists, isFile, thisExePath;
import std.path: absolutePath, buildNormalizedPath, buildPath, dirName, pathSeparator;
import std.process: environment;

import errors;
import log;

struct ToolInfo
{
    string name;      // executable name without suffix
    string envVar;    // explicit per-tool override
    string sdkSubdir; // directory inside the SDK root
}

immutable rlcTool      = ToolInfo("rlc",      "RETROLANG_RLC",      "rlc");
immutable mkpsxisoTool = ToolInfo("mkpsxiso", "RETROLANG_MKPSXISO", "mkpsxiso");

struct ToolLocation
{
    string path;   // absolute path, empty if not found
    string origin; // human-readable description of how it was found

    @property bool found() const { return path.length > 0; }
}

/// Adds the platform executable suffix.
string exeName(string name)
{
    version (Windows)
        return name ~ ".exe";
    else
        return name;
}

private bool isFileAt(string path)
{
    return exists(path) && isFile(path);
}

/// Candidate SDK roots. RETROLANG_HOME wins; otherwise the directory of the
/// retrobuild executable and its parent (so retrobuild may live either in the
/// SDK root or in a subdirectory such as <root>/retrobuild/).
private string[] sdkRoots()
{
    auto home = environment.get("RETROLANG_HOME", "");
    if (home.length)
        return [home];
    auto exeDir = dirName(thisExePath());
    return [exeDir, dirName(exeDir)];
}

private ToolLocation explicitLocation(string tool, string path, string origin)
{
    auto abs = buildNormalizedPath(absolutePath(path));
    if (!isFileAt(abs))
        throw new RetrobuildException(
            "\"" ~ tool ~ "\" is set by " ~ origin ~ " to \"" ~ path ~ "\", but that file does not exist");
    return ToolLocation(abs, origin);
}

/// Resolution order (spec, section 8):
///   1. [tools] entry in the manifest
///   2. per-tool environment variable
///   3. SDK root
///   4. PATH
ToolLocation findTool(in ToolInfo tool, in string[string] manifestPaths)
{
    if (auto p = tool.name in manifestPaths)
        return explicitLocation(tool.name, *p, "[tools] in the manifest");

    auto envPath = environment.get(tool.envVar, "");
    if (envPath.length)
        return explicitLocation(tool.name, envPath, "the " ~ tool.envVar ~ " environment variable");

    foreach (root; sdkRoots())
    {
        auto candidate = buildNormalizedPath(absolutePath(
            buildPath(root, tool.sdkSubdir, exeName(tool.name))));
        if (isFileAt(candidate))
            return ToolLocation(candidate, "the SDK root " ~ root);
    }

    foreach (dir; environment.get("PATH", "").split(pathSeparator))
    {
        if (dir.length == 0)
            continue;
        auto candidate = buildPath(dir, exeName(tool.name));
        if (isFileAt(candidate))
            return ToolLocation(buildNormalizedPath(absolutePath(candidate)), "PATH");
    }

    return ToolLocation.init;
}

/// Like findTool(), but logs the chosen location with --verbose.
/// Use for tools whose absence is not fatal.
ToolLocation optionalTool(in ToolInfo tool, in string[string] manifestPaths)
{
    auto loc = findTool(tool, manifestPaths);
    if (loc.found)
        verbose("Using " ~ tool.name ~ ": " ~ loc.path ~ " (from " ~ loc.origin ~ ")");
    return loc;
}

/// Like optionalTool(), but throws if the tool cannot be found.
ToolLocation requireTool(in ToolInfo tool, in string[string] manifestPaths)
{
    auto loc = optionalTool(tool, manifestPaths);
    if (!loc.found)
        throw new RetrobuildException(
            "\"" ~ tool.name ~ "\" not found. Searched: [tools] in the manifest, $"
            ~ tool.envVar ~ ", the SDK root ($RETROLANG_HOME or the retrobuild directory), PATH");
    return loc;
}
