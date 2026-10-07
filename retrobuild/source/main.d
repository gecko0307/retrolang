module app;

import std.algorithm: canFind;
import std.file: FileException, chdir;
import std.getopt: GetOptException, GetoptResult, config, getopt;
import std.stdio: stderr, writeln;

import errors;
import log;
import manifest;
import pipeline;

enum versionString = "0.1.0";

private immutable string[] plannedCommands = ["cu2", "init", "clean", "doctor"];

private void printUsage()
{
    writeln(
`Retrobuild ` ~ versionString ~ ` - build automation tool for the RetroLang SDK

Usage: retrobuild [options] [command]

Commands:
  build (default)   Run the full pipeline
  compile           Compile the source into the executable only
  iso               Build the CD-ROM image from an existing executable

Options:
  -C <dir>          Run as if started in <dir>
  -m <file>         Use a specific manifest file
  -v, --verbose     Print every external command line
  -q, --quiet       Print errors only
      --no-iso      Skip the CD-ROM image stage
      --version     Print version and exit
  -h, --help        Show this help`);
}

int main(string[] args)
{
    try
        return run(args);
    catch (RetrobuildException e)
    {
        error(e.msg);
        return e.exitCode;
    }
    catch (Exception e)
    {
        error(e.msg);
        return ExitCode.failure;
    }
}

private int run(string[] args)
{
    string dir, manifestPath;
    bool beVerbose, beQuiet, showVersion, noIso;
    GetoptResult parsed;

    try
    {
        parsed = getopt(args, config.caseSensitive,
            "C",         "Run as if started in <dir>",    &dir,
            "m",         "Use a specific manifest file",  &manifestPath,
            "verbose|v", "Print every external command",  &beVerbose,
            "quiet|q",   "Print errors only",             &beQuiet,
            "no-iso",    "Skip the CD-ROM image stage",   &noIso,
            "version",   "Print version and exit",        &showVersion);
    }
    catch (GetOptException e)
        throw new RetrobuildException(e.msg ~ " (see --help)", ExitCode.usage);

    if (parsed.helpWanted)
    {
        printUsage();
        return ExitCode.ok;
    }
    if (showVersion)
    {
        writeln("retrobuild ", versionString);
        return ExitCode.ok;
    }
    if (beVerbose && beQuiet)
        throw new RetrobuildException("--verbose and --quiet are mutually exclusive", ExitCode.usage);

    verbosity = beVerbose ? Verbosity.verbose : beQuiet ? Verbosity.quiet : Verbosity.normal;

    // args[0] is the program name; the rest are positional arguments.
    string command = args.length > 1 ? args[1] : "build";
    if (args.length > 2)
        throw new RetrobuildException("Unexpected argument \"" ~ args[2] ~ "\" (see --help)", ExitCode.usage);

    if (plannedCommands.canFind(command))
        throw new RetrobuildException("Command \"" ~ command ~ "\" is not implemented yet", ExitCode.usage);
    if (!["build", "compile", "iso"].canFind(command))
        throw new RetrobuildException("Unknown command \"" ~ command ~ "\" (see --help)", ExitCode.usage);

    if (dir.length)
    {
        try
            chdir(dir);
        catch (FileException e)
            throw new RetrobuildException("Cannot change directory to \"" ~ dir ~ "\": " ~ e.msg);
    }

    auto m = loadManifest(manifestPath);

    switch (command)
    {
        case "compile":
            compileStage(m);
            break;

        case "iso":
            isoStage(m, true);
            break;

        case "build":
            compileStage(m);
            if (noIso)
                break;
            if (!isoStage(m, false))
                break; // mkpsxiso missing: warning already printed, compiled exe only
            // TODO: cu2 stage
            break;

        default:
            assert(0);
    }
    return ExitCode.ok;
}
