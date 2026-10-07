module errors;

/// Process exit codes (see spec, section 9).
enum ExitCode : int
{
    ok         = 0,
    failure    = 1, // invalid manifest, missing source or tool, I/O errors
    usage      = 2, // command-line usage error
    toolFailed = 3  // an external tool returned a non-zero exit code
}

/// The single error type used by Retrobuild. Carries the exit code to return.
class RetrobuildException : Exception
{
    int exitCode;

    this(string msg, int exitCode = ExitCode.failure,
         string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        this.exitCode = exitCode;
    }
}
