#!/bin/bash
# The window's END_CANCEL_SUBCOMMAND_ID: runs as the window closes. The field shows the window's state.
if [ -n "$ITEST_WORK" ]; then printf 'closed:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/closed.txt"; fi
