#!/bin/bash
# AppletBuilder.scripts.add - Create a new script file

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
scripts_dir="$project_path/Contents/Resources/Scripts"
app_name=$(/usr/bin/basename "${project_path%.app}")
app_lower=$(echo "$app_name" | /usr/bin/tr '[:upper:]' '[:lower:]')

/bin/mkdir -p "$scripts_dir"

# Find a unique script name
base_name="${app_lower}.new.command"
script_path="$scripts_dir/${base_name}.sh"
counter=1
while [ -f "$script_path" ]; do
    script_path="$scripts_dir/${base_name}.${counter}.sh"
    counter=$((counter + 1))
done

# Create a template script
/bin/cat > "$script_path" << 'TEMPLATE'
#!/bin/bash
# New command script

# Source shared library if available
# source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.sh"

echo "New command"
TEMPLATE

/bin/chmod +x "$script_path"

# Refresh the scripts table
"$OMC_OMC_SUPPORT_PATH/omc_next_command" "${OMC_CURRENT_COMMAND_GUID}" "AppletBuilder.scripts.loaded"
