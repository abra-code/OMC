#!/bin/sh
# A .sh script runs with bash on Linux, as /bin/sh is bash on macOS (OMCPlatformShell.h): a dash
# would stop at [[ and write nothing
if [[ -n "$BASH_VERSION" ]]; then
    printf 'shell.script.bash\n' >> "$LAUNCHTEST_LOG"
fi
