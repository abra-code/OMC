#!/bin/bash
# AppletBuilder.uifiles.template.copy - Copy element template JSON to clipboard

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

element_name="$OMC_ACTIONUI_VIEW_728_VALUE"

if [ -z "$element_name" ]; then
    exit 0
fi

template_file="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Documentation/Elements/${element_name}.json"

if [ ! -f "$template_file" ]; then
    set_value "$UI_EDITED_LABEL_ID" "Template not found: ${element_name}"
    exit 1
fi

content=$(/bin/cat "$template_file")

# Find the highest "id" in the currently edited JSON and replace the template's "id": 1
# with max_id + 1 so the pasted fragment won't conflict with existing IDs
edited_content="${OMC_ACTIONUI_VIEW_702_VALUE}"
next_id=1
if [ -n "$edited_content" ]; then
    max_id=$(echo "$edited_content" | /usr/bin/grep -o '"id"[[:space:]]*:[[:space:]]*[0-9]*' | /usr/bin/grep -o '[0-9]*$' | /usr/bin/sort -n | /usr/bin/tail -1)
    if [ -n "$max_id" ]; then
        next_id=$((max_id + 1))
    fi
fi

if [ "$next_id" -ne 1 ]; then
    content=$(echo "$content" | /usr/bin/sed "s/\"id\": 1/\"id\": ${next_id}/")
fi

export LANG="en_US.UTF-8"
echo "$content" | /usr/bin/pbcopy -pboard general

set_value "$UI_EDITED_LABEL_ID" "${element_name} (id: ${next_id}) copied — paste with ⌘V"
