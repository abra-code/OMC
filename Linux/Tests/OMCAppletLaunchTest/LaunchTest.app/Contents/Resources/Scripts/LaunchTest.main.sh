#!/bin/sh
# The main command: logs its file, if any. With no file it also takes a few seconds
# (LAUNCHTEST_MAIN_SECONDS), so the test can reach the running applet meanwhile.
printf 'main:%s\n' "$OMC_OBJ_PATH" >> "$LAUNCHTEST_LOG"
if [ -z "$OMC_OBJ_PATH" ] && [ -n "$LAUNCHTEST_MAIN_SECONDS" ]; then
    # Ended by the test (SIGTERM) with its sleep, which would otherwise outlive it
    /bin/sleep "$LAUNCHTEST_MAIN_SECONDS" &
    sleeper=$!
    trap 'kill "$sleeper" 2>/dev/null; exit 143' TERM
    wait "$sleeper"
fi
