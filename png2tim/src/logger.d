module logger;

import std.stdio;

void logDebug(A...)(A args)
{
    writeln("[Debug] ", args);
}

void logError(A...)(A args)
{
    writeln("[Error] ", args);
}
