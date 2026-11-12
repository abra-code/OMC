#!/bin/sh
# The window's END_OK_SUBCOMMAND_ID: logs the field's value the engine read from the window
printf 'window.ok:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$LAUNCHTEST_LOG"
