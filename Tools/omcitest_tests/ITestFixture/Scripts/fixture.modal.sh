#!/bin/bash
# Runs after its blocking window was OK'd, with the values the window had: its field and all rows of
# its table (one per line, written here joined with "|"). When the test names the ActionUI shell
# client (actionui_remote.path), it also reads the closed window's field through the ActionUI
# remote bridge: this command's tasks start after the window closed, and still hold its model.
if [ -n "$ITEST_WORK" ]; then
    printf 'field:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" >> "$ITEST_WORK/modal.txt"
    printf 'rows:%s\n' "$(printf '%s\n' "$OMC_ACTIONUI_TABLE_7_COLUMN_1_ALL_ROWS" | /usr/bin/tr '\n' '|')" >> "$ITEST_WORK/modal.txt"
    if [ -f "$ITEST_WORK/actionui_remote.path" ]; then
        client="$(/bin/cat "$ITEST_WORK/actionui_remote.path")"
        . "$client"
        value="$(actionui_get_string 2 2>&1)"
        status=$?
        printf 'bridge:%s:%s\n' "$status" "$value" >> "$ITEST_WORK/modal.txt"
    fi
fi
