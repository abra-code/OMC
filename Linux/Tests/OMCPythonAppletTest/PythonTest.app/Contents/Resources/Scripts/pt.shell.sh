#!/bin/sh
# A .sh command: its python3 is the embedded one (the engine puts the embedded bin folder first
# on PATH for every script when the applet has a Python)
printf 'sh.python3:%s\n' "$(python3 -c 'import os, sys; print(os.path.realpath(sys.executable))')" >> "$PYTHONTEST_LOG"
