#!/bin/bash
# Preview an ActionUI view JSON with ActionUIViewer, or summarize a MainMenu.json
# menu-bar document (which is not a view and cannot be rendered).

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"

selected_path=$(pb_get "$PB_UIFILES_SELECTED")

if [ -z "$selected_path" ] || [ ! -f "$selected_path" ]; then
    set_value "$UI_EDITED_LABEL_ID" "No file selected"
    exit 0
fi

# Check JSON syntax before previewing
json_error=$("$python3" -m json.tool "$selected_path" 2>&1 >/dev/null)
if [ "$?" -ne 0 ]; then
    set_value "$UI_EDITED_LABEL_ID" "Invalid JSON"
    show_errors "Cannot preview — JSON syntax error in $(/usr/bin/basename "$selected_path"):

$json_error"
    exit 0
fi

# A menu-bar document (MainMenu.json) has a top-level JSON array; it describes
# the menu bar, not a view, so ActionUIViewer cannot render it. Show a textual
# menu summary in the reference window instead.
is_menubar=$("$python3" -c 'import json,sys; print("yes" if isinstance(json.load(open(sys.argv[1])),list) else "no")' "$selected_path" 2>/dev/null)
if [ "$is_menubar" = "yes" ]; then
    summary=$("$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/menubar_summary.py" "$selected_path" 2>&1)
    set_value "$UI_EDITED_LABEL_ID" "Menu bar (no view preview)"
    show_reference "$summary"
    exit 0
fi

viewer="${OMC_APP_BUNDLE_PATH}/Contents/Helpers/ActionUIViewer"
if [ -x "$viewer" ]; then
    "$viewer" "$selected_path" &
else
    set_value "$UI_EDITED_LABEL_ID" "ActionUIViewer not found"
fi
