#!/bin/bash
# Runs only when its WARNING was answered with the Execute button.
if [ -n "$ITEST_WORK" ]; then printf 'warned\n' >> "$ITEST_WORK/warn.txt"; fi
