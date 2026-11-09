#!/bin/bash
# The applet's main command, which opens the modeless window (Window.json) and runs at once after it
# opens: records the field's initial value and the window it ran for.
echo "main ran"
if [ -n "$ITEST_WORK" ]; then
    printf 'main:%s:%s\n' "$OMC_ACTIONUI_VIEW_2_VALUE" "$OMC_ACTIONUI_WINDOW_UUID" >> "$ITEST_WORK/main.txt"
fi
