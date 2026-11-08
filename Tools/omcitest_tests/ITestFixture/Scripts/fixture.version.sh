#!/bin/bash
# Requires OMC 99: runs only when the version warning was answered with Try Anyway.
if [ -n "$ITEST_WORK" ]; then printf 'tried\n' >> "$ITEST_WORK/version.txt"; fi
