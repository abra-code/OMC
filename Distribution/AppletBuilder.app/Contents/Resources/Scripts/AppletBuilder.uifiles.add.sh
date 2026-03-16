#!/bin/bash
# AppletBuilder.uifiles.add - Create a new ActionUI JSON file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
resources_dir="$project_path/Contents/Resources"
lproj_dir="$resources_dir/Base.lproj"

/bin/mkdir -p "$lproj_dir"

# Find a unique filename
base_name="NewDialog"
json_path="$lproj_dir/${base_name}.json"
counter=1
while [ -f "$json_path" ]; do
    json_path="$lproj_dir/${base_name}${counter}.json"
    counter=$((counter + 1))
done

# Create a template ActionUI JSON
/bin/cat > "$json_path" << 'TEMPLATE'
{
  "type": "VStack",
  "properties": {
    "padding": 20
  },
  "children": [
    {
      "type": "Text",
      "properties": {
        "text": "New Dialog"
      }
    }
  ]
}
TEMPLATE

# Refresh the UI files table
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.uifiles.loaded"
