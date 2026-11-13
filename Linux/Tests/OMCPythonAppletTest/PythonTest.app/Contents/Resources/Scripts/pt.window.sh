#!/bin/sh
# The window command: its window opens; the script logs that it ran
printf 'window.command\n' >> "$PYTHONTEST_LOG"
