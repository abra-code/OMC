#!/bin/bash
# lib.create.sh - Create a new applet from a template (or by cloning one)
#
# The build pipeline lives in lib.build.sh; this lib adds the create-only helpers
# and the top-level applet_create_from_template orchestrator. Progress and errors
# go through the reporters from lib.common.sh (ab_log / ab_report): a GUI handler
# overrides them to drive its status field, the agent CLI keeps the stderr defaults.
#
# Codesigning honors the same knobs as the build pipeline:
#   AB_IDENTITY      signing identity (default "-" ad-hoc)
#   AB_NO_CODESIGN   "1" = skip codesigning entirely

[ -n "$__LIB_CREATE_SH" ] && return 0
__LIB_CREATE_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.prefs.sh"

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

# Create a new applet from a template (or clone an existing applet).
#
# Args:
#   1 template_path    .applet/.app to copy (for a clone, the source applet)
#   2 applet_name      new applet name (executable + script prefix)
#   3 dest_folder      directory to create <applet_name>.app in
#   4 bundle_id        CFBundleIdentifier; empty → remembered prefix + name
#   5 icon_path        .icon/.icns/image to install; empty → keep template icon
#   6 requires_python  "1"/"true" → embed Python and start from a .py main script
#   7 is_clone         "1" → source is an existing applet (auto-detect Python use)
#
# On success the applet is left at "$dest_folder/$applet_name.app" (the caller
# can compute that path). Returns 0 on success, 1 on any validation/copy failure.
applet_create_from_template() {
    local template_path="$1"
    local applet_name="$2"
    local dest_folder="$3"
    local bundle_id="$4"
    local icon_path="$5"
    local requires_python="$6"
    local is_clone="$7"

    # ── Validation ──
    if [ -z "$applet_name" ]; then
        ab_report "Applet name is required"
        return 1
    fi
    if [ -z "$template_path" ] || [ ! -d "$template_path" ]; then
        ab_report "Template .app not found: $template_path"
        return 1
    fi
    if [ -z "$dest_folder" ] || [ ! -d "$dest_folder" ]; then
        ab_report "Invalid destination folder: $dest_folder"
        return 1
    fi

    local new_app_path="${dest_folder}/${applet_name}.app"
    if [ -e "$new_app_path" ]; then
        ab_report "Already exists: ${applet_name}.app"
        return 1
    fi

    # ── Detect original name from template ──
    local original_name
    original_name=$(plist_read "$template_path/Contents/Info.plist" CFBundleExecutable)
    if [ -z "$original_name" ]; then
        original_name=$(/usr/bin/basename "${template_path%.app}")
    fi

    # ── Build the applet ──
    ab_log "Creating applet..."

    # Copy and clean
    /bin/cp -Rp "$template_path" "$new_app_path"
    if [ $? -ne 0 ]; then
        ab_report "Failed to copy template"
        return 1
    fi
    /bin/rm -rf "$new_app_path/Contents/_CodeSignature" 2>/dev/null
    /usr/bin/xattr -dr com.apple.quarantine "$new_app_path" 2>/dev/null

    # Install runtime binaries
    applet_install_binaries "$new_app_path" "$applet_name"

    # Set creator to '????' (neutral for applets)
    applet_set_creator_code "$new_app_path" "????"

    # Install icon
    if [ -n "$icon_path" ] && [ -e "$icon_path" ]; then
        applet_install_icon "$icon_path" "$new_app_path"
        if [ $? -eq 0 ]; then
            local icon_base
            icon_base=$(/usr/bin/basename "${icon_path%.*}")
            applet_cleanup_icons "$new_app_path" "$icon_base"
        fi
    fi

    # Rename executable (may not exist in templates, but handle clones)
    /bin/mv "$new_app_path/Contents/MacOS/$original_name" \
            "$new_app_path/Contents/MacOS/$applet_name" 2>/dev/null

    # Full rename pipeline (plist, nibs, scripts, credits, URL scheme)
    applet_rename_contents "$new_app_path" "$original_name" "$applet_name"

    # Update bundle ID and remember prefix
    if [ -z "$bundle_id" ]; then
        local prefix
        prefix=$(get_bundle_id_prefix)
        bundle_id="${prefix}${applet_name}"
    fi
    applet_set_bundle_id "$new_app_path" "$bundle_id"
    save_bundle_id_prefix "$bundle_id"

    # Install Python if needed
    local needs_python=0
    if [ "$requires_python" = "1" ] || [ "$requires_python" = "true" ]; then
        needs_python=1
        # Replace .sh main script with .py
        local scripts_dir="$new_app_path/Contents/Resources/Scripts"
        local sh_script="$scripts_dir/${applet_name}.main.sh"
        local py_script="$scripts_dir/${applet_name}.main.py"
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
    elif [ "$is_clone" = "1" ]; then
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
    if [ "$AB_NO_CODESIGN" != "1" ]; then
        local identity="$AB_IDENTITY"
        [ -z "$identity" ] && identity="-"
        applet_codesign "$new_app_path" "$identity" > /dev/null 2>&1
    fi

    return 0
}
