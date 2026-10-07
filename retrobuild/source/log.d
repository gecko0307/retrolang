module log;

import std.stdio : stderr, writeln;

enum Verbosity
{
    quiet,   // errors only
    normal,
    verbose  // also print every external command line
}

Verbosity verbosity = Verbosity.normal;

/// Informational messages (stdout).
void info(string msg)
{
    if (verbosity >= Verbosity.normal)
        writeln("[INFO] ", msg);
}

/// Details shown only with --verbose (stdout).
void verbose(string msg)
{
    if (verbosity >= Verbosity.verbose)
        writeln("[INFO] ", msg);
}

/// Warnings (stderr), suppressed by --quiet.
void warning(string msg)
{
    if (verbosity >= Verbosity.normal)
        stderr.writeln("[WARNING] ", msg);
}

/// Errors (stderr), always shown.
void error(string msg)
{
    stderr.writeln("[ERROR] ", msg);
}
