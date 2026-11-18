#!/bin/sh
printf 'did.launch\n' >> "$LAUNCHTEST_LOG"
# The data folder the engine names (OMC_APP_DATA_PATH), apart from the log, whose order run.sh checks
printf '%s\n' "$OMC_APP_DATA_PATH" > "$LAUNCHTEST_LOG.data"
