#!/bin/sh
# A command that requires a macOS no system has (at least 99.0 and at most 10.1): on Linux the
# requirement is ignored and it runs
printf 'macos.ran\n' >> "$LAUNCHTEST_LOG"
