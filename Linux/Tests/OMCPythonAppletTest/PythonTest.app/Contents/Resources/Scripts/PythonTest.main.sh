#!/bin/sh
# The main command: logs that it ran (the tests launch the applet with a URL, which skips it)
printf 'main\n' >> "$PYTHONTEST_LOG"
