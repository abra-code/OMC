#!/bin/bash
# AppletBuilder.buildrun.loaded - Populate the signing identity picker, and
# match the Embedded Python group to the applet in front of the user.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

# Build the options array as a JSON string
# Always include ad-hoc signing as first option
options='[{"title":"Sign to Run Locally (ad-hoc)","tag":"-"}'

# Query available codesigning identities
identities=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null)

while IFS= read -r line; do
    # Each line looks like:  1) HASH "Name (ID)"
    # Extract the quoted name
    if [[ "$line" =~ \"(.+)\" ]]; then
        identity_name="${BASH_REMATCH[1]}"

        # Skip identities not suitable for app codesigning
        case "$identity_name" in
            "Apple Configurator:"*) continue ;;
            *" Installer:"*) continue ;;
        esac

        # Escape any double quotes in identity name for JSON
        escaped_name=$(echo "$identity_name" | /usr/bin/sed 's/"/\\"/g')
        options="${options},{\"title\":\"${escaped_name}\",\"tag\":\"${escaped_name}\"}"
    fi
done <<< "$identities"

options="${options}]"

# Set the picker options
"$dialog_tool" "$window_uuid" "$BUILD_IDENTITY_PICKER_ID" omc_set_property "options" "$options"

# The Embedded Python group is only usable on an applet that has one. Asked here
# rather than left to the button, so "you cannot thin this applet" is visible
# before anyone ticks a box - and asked again after a build, which is the one
# operation that can install a runtime into an applet that had none.
ab_thin_python_availability "$(load_project_path)"

# Its answer is the group's state, not this handler's verdict: it returns 1 for an
# applet with no embedded Python, which is an ordinary applet, and the pane loaded
# perfectly well. Without this the load handler exits non-zero every time one is
# opened.
exit 0
