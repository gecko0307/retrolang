module exec;

import std.process: spawnProcess, wait, escapeShellCommand, Config, ProcessException;
import std.stdio: stdin, stdout, stderr;
import std.conv: to;

import errors;
import log;

/// Runs an external program directly (no shell) with the console streams
/// inherited, and returns its exit code. Throws only if it cannot be started.
int run(const(string)[] argv, string workDir = null)
{
    verbose("$ " ~ escapeShellCommand(argv));
    try
    {
        auto pid = spawnProcess(argv, stdin, stdout, stderr, null, Config.none, workDir);
        return wait(pid);
    }
    catch (ProcessException e)
    {
        throw new RetrobuildException("Cannot execute \"" ~ argv[0] ~ "\": " ~ e.msg);
    }
}

/// Like run(), but a non-zero exit code becomes a RetrobuildException
/// with ExitCode.toolFailed. `label` names the program in the message.
void runChecked(const(string)[] argv, string workDir, string label)
{
    int code = run(argv, workDir);
    if (code != 0)
        throw new RetrobuildException(
            label ~ " failed with exit code " ~ code.to!string, ExitCode.toolFailed);
}
