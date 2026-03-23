#!/bin/bash
# AppletBuilder.new.create - Create a new applet from template

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

# ── Functions used only during applet creation ──

# Update creator code in PkgInfo and Info.plist
applet_set_creator_code() {
    local app_path="$1"
    local creator="$2"

    if [ -z "$creator" ] || [ ${#creator} -ne 4 ]; then
        return 1
    fi

    local pkginfo="$app_path/Contents/PkgInfo"
    if [ -f "$pkginfo" ]; then
        printf 'APPL%s' "$creator" > "$pkginfo"
    fi

    local plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        plist_write "$plist" "CFBundleSignature" "$creator"
    fi
}

# Install runtime binaries (executable + Abracode.framework) from AppletBuilder
applet_install_binaries() {
    local app_path="$1"
    local app_name="$2"

    local builder_exe="${OMC_APP_BUNDLE_PATH}/Contents/MacOS/$(/usr/bin/basename "${OMC_APP_BUNDLE_PATH%.app}")"
    local builder_fw="${OMC_APP_BUNDLE_PATH}/Contents/Frameworks/Abracode.framework"

    # Copy executable, renamed to match the applet
    /bin/mkdir -p "$app_path/Contents/MacOS"
    /bin/cp "$builder_exe" "$app_path/Contents/MacOS/$app_name"
    /bin/chmod +x "$app_path/Contents/MacOS/$app_name"

    # Copy framework if AppletBuilder's is newer or destination doesn't have one
    local dest_fw="$app_path/Contents/Frameworks/Abracode.framework"
    if [ -d "$builder_fw" ]; then
        local need_copy=0
        if [ ! -d "$dest_fw" ]; then
            need_copy=1
        else
            local src_ver=$(/usr/bin/plutil -extract CFBundleVersion raw "$builder_fw/Resources/Info.plist" 2>/dev/null)
            local dst_ver=$(/usr/bin/plutil -extract CFBundleVersion raw "$dest_fw/Resources/Info.plist" 2>/dev/null)
            if [ "$src_ver" != "$dst_ver" ]; then
                need_copy=1
            fi
        fi
        if [ "$need_copy" -eq 1 ]; then
            /bin/mkdir -p "$app_path/Contents/Frameworks"
            /bin/rm -rf "$dest_fw"
            /bin/cp -Rp "$builder_fw" "$dest_fw"
        fi
    fi
}

# Install Python runtime from AppletBuilder into target applet
applet_install_python() {
    local app_path="$1"
    local src="${OMC_APP_BUNDLE_PATH}/Contents/Library/Python"
    if [ -d "$src" ]; then
        /bin/mkdir -p "$app_path/Contents/Library"
        /bin/cp -Rp "$src" "$app_path/Contents/Library/Python"
    fi
}

# Remove stale .icns files that don't match the given name
applet_cleanup_icons() {
    local app_path="$1"
    local keep_name="$2"

    for old_icns in "$app_path/Contents/Resources/"*.icns; do
        [ ! -f "$old_icns" ] && continue
        local old_base=$(/usr/bin/basename "${old_icns%.icns}")
        if [ "$old_base" != "$keep_name" ]; then
            /bin/rm -f "$old_icns"
        fi
    done
}

# Read form values
template_tag="${OMC_ACTIONUI_VIEW_201_VALUE}"
template_path="${OMC_ACTIONUI_VIEW_202_VALUE}"
templates_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Templates"
icons_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Icons"

# Resolve template path from tag if not cloning
if [ "$template_tag" != "__clone__" ] && [ -z "$template_path" ]; then
    template_path="${templates_dir}/${template_tag}.applet"
fi
applet_name="${OMC_ACTIONUI_VIEW_203_VALUE}"
bundle_id="${OMC_ACTIONUI_VIEW_204_VALUE}"
custom_icon_path="${OMC_ACTIONUI_VIEW_206_VALUE}"
requires_python="${OMC_ACTIONUI_VIEW_208_VALUE}"
icon_tag="${OMC_ACTIONUI_VIEW_209_VALUE}"
dest_folder="${OMC_DLG_CHOOSE_FOLDER_PATH}"

# Resolve icon path
if [ "$icon_tag" = "__custom__" ]; then
    icon_path="$custom_icon_path"
elif [ -n "$icon_tag" ]; then
    icon_path="${icons_dir}/${icon_tag}.icon"
fi

# ── Validation ──

if [ -z "$applet_name" ]; then
    set_status "$NEW_STATUS_ID" "Applet name is required"
    exit 1
fi

if [ -z "$template_path" ] || [ ! -d "$template_path" ]; then
    set_status "$NEW_STATUS_ID" "Template .app not found: $template_path"
    exit 1
fi

if [ -z "$dest_folder" ] || [ ! -d "$dest_folder" ]; then
    set_status "$NEW_STATUS_ID" "Invalid destination folder"
    exit 1
fi

new_app_path="${dest_folder}/${applet_name}.app"

if [ -e "$new_app_path" ]; then
    set_status "$NEW_STATUS_ID" "Already exists: ${applet_name}.app"
    exit 1
fi

# ── Detect original name from template ──

original_name=$(plist_read "$template_path/Contents/Info.plist" CFBundleExecutable)
if [ -z "$original_name" ]; then
    original_name=$(/usr/bin/basename "${template_path%.app}")
fi

original_icon=$(plist_read "$template_path/Contents/Info.plist" CFBundleIconFile)

# ── Build the applet ──

set_status "$NEW_STATUS_ID" "Creating applet..."

# Copy and clean
/bin/cp -Rp "$template_path" "$new_app_path"
if [ $? -ne 0 ]; then
    set_status "$NEW_STATUS_ID" "Failed to copy template"
    exit 1
fi
/bin/rm -rf "$new_app_path/Contents/_CodeSignature" 2>/dev/null
/usr/bin/xattr -dr com.apple.quarantine "$new_app_path" 2>/dev/null

# Install runtime binaries
applet_install_binaries "$new_app_path" "$applet_name"

# Set creator to '????' (neutral for applets)
applet_set_creator_code "$new_app_path" "????"

# Install icon
icon_installed=0
if [ -n "$icon_path" ] && [ -e "$icon_path" ]; then
    applet_install_icon "$icon_path" "$new_app_path"
    if [ $? -eq 0 ]; then
        icon_installed=1
        icon_base=$(/usr/bin/basename "${icon_path%.*}")
        applet_cleanup_icons "$new_app_path" "$icon_base"
    fi
fi

# Icon files keep their original names (CFBundleIconName = asset name in Assets.car)

# Rename executable (may not exist in templates, but handle clones)
/bin/mv "$new_app_path/Contents/MacOS/$original_name" \
        "$new_app_path/Contents/MacOS/$applet_name" 2>/dev/null

# Full rename pipeline (plist, nibs, scripts, credits, URL scheme)
applet_rename_contents "$new_app_path" "$original_name" "$applet_name"

# Update bundle ID and remember prefix
if [ -z "$bundle_id" ]; then
    prefix=$(get_bundle_id_prefix)
    bundle_id="${prefix}${applet_name}"
fi
applet_set_bundle_id "$new_app_path" "$bundle_id"
save_bundle_id_prefix "$bundle_id"

# Install Python if needed
needs_python=0
if [ "$requires_python" = "1" ] || [ "$requires_python" = "true" ]; then
    needs_python=1
    # Replace .sh main script with .py
    scripts_dir="$new_app_path/Contents/Resources/Scripts"
    sh_script="$scripts_dir/${applet_name}.main.sh"
    py_script="$scripts_dir/${applet_name}.main.py"
    if [ -f "$sh_script" ]; then
        /bin/rm -f "$sh_script"
    fi
    if [ ! -f "$py_script" ]; then
        cat > "$py_script" << 'PYEOF'
#!/usr/bin/env python3
print("Hello from Python!")
PYEOF
        chmod +x "$py_script"
    fi
elif [ "$template_tag" = "__clone__" ]; then
    # For clones, detect Python usage from .py files in the template
    if /usr/bin/find "$new_app_path/Contents/Resources/Scripts" -name '*.py' -print -quit | /usr/bin/grep -q .; then
        needs_python=1
    fi
fi

if [ "$needs_python" -eq 1 ]; then
    applet_install_python "$new_app_path"
fi

# Finalize and codesign
applet_finalize "$new_app_path"
applet_codesign "$new_app_path" "-" > /dev/null 2>&1

# Close the New Applet window and open the project window
"$dialog_tool" "$window_uuid" omc_window omc_terminate_cancel
/usr/bin/open -a "$OMC_APP_BUNDLE_PATH" "$new_app_path"
