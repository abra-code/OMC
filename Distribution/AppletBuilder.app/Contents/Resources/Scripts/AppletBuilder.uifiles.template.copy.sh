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
export LANG="en_US.UTF-8"
echo "$content" | /usr/bin/pbcopy -pboard general

set_value "$UI_EDITED_LABEL_ID" "${element_name} template copied — paste with ⌘V"
