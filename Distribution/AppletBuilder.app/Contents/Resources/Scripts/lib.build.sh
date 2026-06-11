#!/bin/bash
# lib.build.sh - Applet build / rename / icon / codesign pipeline
#
# Sources lib.common.sh (common base) and lib.plist.sh (plist_read / plist_write).

[ -n "$__LIB_BUILD_SH" ] && return 0
__LIB_BUILD_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"

# Update bundle identifier
applet_set_bundle_id() {
    local app_path="$1"
    local bundle_id="$2"

    local plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        plist_write "$plist" "CFBundleIdentifier" "$bundle_id"
    fi
}

# Compile and install icon
applet_install_icon() {
    local icon_source="$1"
    local app_path="$2"

    if [ -z "$icon_source" ] || [ ! -e "$icon_source" ]; then
        return 1
    fi

    local icon_base=$(/usr/bin/basename "${icon_source%.*}")

    local resources_dir="$app_path/Contents/Resources"
    local temp_dir=$(/usr/bin/mktemp -d) || return 1

    /usr/bin/xcrun actool "$icon_source" \
        --compile "$temp_dir" \
        --app-icon "$icon_base" \
        --platform macosx \
        --target-device mac \
        --output-format human-readable-text \
        --minimum-deployment-target 14.6 \
        --output-partial-info-plist "$temp_dir/partial.plist" \
        > "$temp_dir/actool.log" 2>&1

    local success=0

    if [ -f "$temp_dir/Assets.car" ]; then
        /bin/cp "$temp_dir/Assets.car" "$resources_dir/Assets.car"
        success=1
    fi

    if [ -f "$temp_dir/$icon_base.icns" ]; then
        /bin/cp "$temp_dir/$icon_base.icns" "$resources_dir/$icon_base.icns"
        success=1
    fi

    local plist="$app_path/Contents/Info.plist"
    if [ -f "$plist" ]; then
        plist_write "$plist" "CFBundleIconFile" "$icon_base"
        plist_write "$plist" "CFBundleIconName" "$icon_base"
    fi

    /bin/rm -rf "$temp_dir"
    return $( [ $success -eq 1 ] && echo 0 || echo 1 )
}

# Recompile MainMenu.nib with new name
applet_recompile_nib() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local nib_dir="$app_path/Contents/Resources/Base.lproj/MainMenu.nib"
    local designable="$nib_dir/designable.nib"

    if [ ! -f "$designable" ]; then
        return 0
    fi

    /usr/bin/sed -i '' "s/$old_name/$new_name/g" "$designable"

    local temp_nib="$app_path/Contents/Resources/Base.lproj/temp.nib"
    /usr/bin/xcrun ibtool --compile "$temp_nib" --flatten NO "$nib_dir"

    /bin/rm -rf "$nib_dir"
    /bin/mv "$temp_nib" "$nib_dir"
}

# Finalize: touch + register with Launch Services
applet_finalize() {
    local app_path="$1"
    /usr/bin/touch -c "$app_path"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -f -R -trusted "$app_path" 2>/dev/null
}

# Rename scripts to match new applet name
applet_rename_scripts() {
    local scripts_dir="$1"
    local old_name="$2"
    local new_name="$3"

    local old_lower=$(echo "$old_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
    local new_lower=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]')

    # Rename script files
    for script in "$scripts_dir"/*; do
        [ ! -f "$script" ] && continue
        local script_base=$(/usr/bin/basename "$script")
        if [[ "$script_base" == "${old_name}."* ]]; then
            local suffix="${script_base#${old_name}.}"
            /bin/mv "$script" "$scripts_dir/${new_name}.${suffix}"
        elif [[ "$script_base" == "${old_lower}."* ]]; then
            local suffix="${script_base#${old_lower}.}"
            /bin/mv "$script" "$scripts_dir/${new_lower}.${suffix}"
        fi
    done

    # Update script contents
    for script in "$scripts_dir"/*; do
        [ ! -f "$script" ] && continue
        /usr/bin/sed -i '' "s/${old_name}/${new_name}/g" "$script"
        if [ "$old_lower" != "$old_name" ]; then
            /usr/bin/sed -i '' "s/${old_lower}/${new_lower}/g" "$script"
        fi
    done
}

# Recompile all non-MainMenu nibs
applet_recompile_other_nibs() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local lproj_dir="$app_path/Contents/Resources/Base.lproj"
    for nib_dir in "$lproj_dir"/*.nib; do
        [ ! -d "$nib_dir" ] && continue
        local nib_base=$(/usr/bin/basename "${nib_dir%.nib}")
        [ "$nib_base" = "MainMenu" ] && continue
        local designable="$nib_dir/designable.nib"
        if [ -f "$designable" ]; then
            /usr/bin/sed -i '' "s/$old_name/$new_name/g" "$designable"
            local temp_nib="$lproj_dir/temp_recompile.nib"
            /usr/bin/xcrun ibtool --compile "$temp_nib" --flatten NO "$nib_dir" 2>/dev/null
            if [ -d "$temp_nib" ]; then
                /bin/rm -rf "$nib_dir"
                /bin/mv "$temp_nib" "$nib_dir"
            fi
        fi
    done
}

# Update Credits.rtf with new name
applet_update_credits() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local credits="$app_path/Contents/Resources/Credits.rtf"
    if [ -f "$credits" ]; then
        /usr/bin/sed -i '' "s/${old_name}/${new_name}/g" "$credits"
        local old_lower=$(echo "$old_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
        local new_lower=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]')
        if [ "$old_lower" != "$old_name" ]; then
            /usr/bin/sed -i '' "s/${old_lower}/${new_lower}/g" "$credits"
        fi
    fi
}

# Update URL scheme in Info.plist
applet_update_url_scheme() {
    local plist="$1"
    local new_name="$2"

    local url_scheme=$(echo "$new_name" | /usr/bin/tr '[:upper:]' '[:lower:]' | /usr/bin/tr ' ' '-' | /usr/bin/tr -cd 'a-z0-9-')
    /usr/bin/plutil -replace "CFBundleURLTypes.0.CFBundleURLName" -string "$new_name" "$plist" 2>/dev/null
    /usr/bin/plutil -replace "CFBundleURLTypes.0.CFBundleURLSchemes.0" -string "$url_scheme" "$plist" 2>/dev/null
}

# Full rename pipeline: renames all parts of an applet from old_name to new_name
# Does NOT rename the .app bundle directory or the executable — caller handles those
applet_rename_contents() {
    local app_path="$1"
    local old_name="$2"
    local new_name="$3"

    local plist="$app_path/Contents/Info.plist"

    # Update Info.plist
    plist_write "$plist" "CFBundleExecutable" "$new_name"
    plist_write "$plist" "CFBundleName" "$new_name"
    plist_write "$plist" "NSAppleEventsUsageDescription" \
        "$new_name sends AppleEvents to other apps to provide functionality unique to this applet."
    applet_update_url_scheme "$plist" "$new_name"

    # Recompile nibs
    applet_recompile_nib "$app_path" "$old_name" "$new_name"
    applet_recompile_other_nibs "$app_path" "$old_name" "$new_name"

    # Update the command file: rename any string value equal to the old app name
    # (NAME, window titles, …). Done per-format so it works for Command.json too.
    local cmd_plist=$(command_file_path "$app_path")
    if [ -f "$cmd_plist" ]; then
        if is_json_command_file "$cmd_plist"; then
            "$python3" - "$cmd_plist" "$old_name" "$new_name" <<'PY'
import json, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
def walk(o):
    if isinstance(o, dict):
        return {k: walk(v) for k, v in o.items()}
    if isinstance(o, list):
        return [walk(v) for v in o]
    return new if o == old else o
with open(path) as f:
    data = json.load(f)
with open(path, 'w') as f:
    json.dump(walk(data), f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
        else
            /usr/bin/sed -i '' "s|<string>${old_name}</string>|<string>${new_name}</string>|" "$cmd_plist"
        fi
    fi

    # Rename and update scripts
    applet_rename_scripts "$app_path/Contents/Resources/Scripts" "$old_name" "$new_name"

    # Update Credits.rtf
    applet_update_credits "$app_path" "$old_name" "$new_name"
}

# Ad-hoc codesign using the standalone script
applet_codesign() {
    local app_path="$1"
    local identity="$2"
    /bin/sh "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/codesign_applet.sh" "$app_path" "$identity"
}
