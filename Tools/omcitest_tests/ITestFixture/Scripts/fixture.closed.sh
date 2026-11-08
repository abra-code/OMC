#!/bin/bash
# The window's END_CANCEL_SUBCOMMAND_ID: runs as the window closes. The field shows the window's state.
# When the test names the ActionUI shell client (actionui_remote.path), it then reads the closed
# window through the ActionUI remote bridge after a moment, as a handler may: the window's model
# lasts until this command has ended.
if [ -n "$ITEST_WORK" ]; then
    printf 'closed:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/closed.txt"
    if [ -f "$ITEST_WORK/actionui_remote.path" ]; then
        client="$(/bin/cat "$ITEST_WORK/actionui_remote.path")"
        /bin/sleep 0.5
        . "$client"
        value="$(actionui_get_string 2 2>&1)"
        status=$?
        printf 'bridge:%s:%s\n' "$status" "$value" >> "$ITEST_WORK/closed.txt"
    fi
fi
