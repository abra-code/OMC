#!/bin/bash
# AppletBuilder.build - Update framework/runtime, codesign the project applet
# echo "[$(/usr/bin/basename "$0")]"
# env | sort

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
builder_path="${OMC_APP_BUNDLE_PATH}"
build_log=""

log() {
    build_log="${build_log}
$1"
    set_value "$BUILD_LOG_ID" "$build_log"
}

# Compare two version strings: prints "newer", "older", or "same"
compare_versions() {
    local v1="$1"
    local v2="$2"
    local v1_major=$(echo "$v1" | /usr/bin/cut -d. -f1)
    local v1_minor=$(echo "$v1" | /usr/bin/cut -d. -f2)
    local v1_patch=$(echo "$v1" | /usr/bin/cut -d. -f3)
    local v2_major=$(echo "$v2" | /usr/bin/cut -d. -f1)
    local v2_minor=$(echo "$v2" | /usr/bin/cut -d. -f2)
    local v2_patch=$(echo "$v2" | /usr/bin/cut -d. -f3)
    v1_major=${v1_major:-0}; v1_minor=${v1_minor:-0}; v1_patch=${v1_patch:-0}
    v2_major=${v2_major:-0}; v2_minor=${v2_minor:-0}; v2_patch=${v2_patch:-0}

    if [ "$v1_major" -gt "$v2_major" ] 2>/dev/null; then echo "newer"; return; fi
    if [ "$v1_major" -lt "$v2_major" ] 2>/dev/null; then echo "older"; return; fi
    if [ "$v1_minor" -gt "$v2_minor" ] 2>/dev/null; then echo "newer"; return; fi
    if [ "$v1_minor" -lt "$v2_minor" ] 2>/dev/null; then echo "older"; return; fi
    if [ "$v1_patch" -gt "$v2_patch" ] 2>/dev/null; then echo "newer"; return; fi
    if [ "$v1_patch" -lt "$v2_patch" ] 2>/dev/null; then echo "older"; return; fi
    echo "same"
}

# Copy the app executable from builder to target (with proper name)
copy_executable() {
    local target_path="$1"
    local src_exe_name=$(plist_read "$builder_path/Contents/Info.plist" CFBundleExecutable)
    local dst_exe_name=$(plist_read "$target_path/Contents/Info.plist" CFBundleExecutable)
    /bin/cp -p "$builder_path/Contents/MacOS/$src_exe_name" \
               "$target_path/Contents/MacOS/$dst_exe_name"
    log "Executable updated: $dst_exe_name"
}

# Install or update Abracode.framework and executable
update_framework() {
    local target_path="$1"
    local src_fw="$builder_path/Contents/Frameworks/Abracode.framework"
    local dst_fw="$target_path/Contents/Frameworks/Abracode.framework"
    local src_version=$(plist_read "$src_fw/Resources/Info.plist" CFBundleVersion)

    if [ ! -d "$dst_fw" ]; then
        log "Abracode.framework missing — installing v${src_version}"
        /bin/mkdir -p "$target_path/Contents/Frameworks"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
        return
    fi

    local dst_version=$(plist_read "$dst_fw/Resources/Info.plist" CFBundleVersion)
    local force_update="$OMC_ACTIONUI_VIEW_403_VALUE"

    if [ "$force_update" = "1" ] || [ "$force_update" = "true" ]; then
        log "Updating Abracode.framework: v${dst_version} -> v${src_version} (forced)"
        /bin/rm -rf "$dst_fw"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
        return
    fi

    local cmp=$(compare_versions "$src_version" "$dst_version")

    if [ "$cmp" = "newer" ]; then
        log "Updating Abracode.framework: v${dst_version} -> v${src_version}"
        /bin/rm -rf "$dst_fw"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
    else
        log "Abracode.framework v${dst_version} is current"
    fi
}

# Get Python major.minor version string from a Python install directory
python_version() {
    local python_dir="$1"
    "$python_dir/bin/python3" --version 2>/dev/null | /usr/bin/awk '{print $2}'
}

# Install or update embedded Python runtime for Python applets
update_python() {
    local target_path="$1"
    local src_python="$builder_path/Contents/Library/Python"
    local dst_python="$target_path/Contents/Library/Python"

    # Check if target has Python scripts
    if ! /usr/bin/find "$target_path/Contents/Resources/Scripts" -name "*.py" -print -quit 2>/dev/null | /usr/bin/grep -q .; then
        return
    fi

    if [ ! -d "$src_python" ]; then
        return
    fi

    local src_version=$(python_version "$src_python")

    if [ ! -d "$dst_python" ]; then
        log "Python runtime missing — installing v${src_version}"
        /bin/mkdir -p "$target_path/Contents/Library"
        /bin/cp -Rp "$src_python" "$dst_python"
        return
    fi

    local dst_version=$(python_version "$dst_python")

    if [ -z "$dst_version" ]; then
        log "Python runtime broken — reinstalling v${src_version}"
        /bin/rm -rf "$dst_python"
        /bin/cp -Rp "$src_python" "$dst_python"
        return
    fi

    if [ "$src_version" = "$dst_version" ]; then
        log "Python v${dst_version} is current"
        return
    fi

    local src_major=$(echo "$src_version" | /usr/bin/cut -d. -f1-2)
    local dst_major=$(echo "$dst_version" | /usr/bin/cut -d. -f1-2)

    if [ "$src_major" != "$dst_major" ]; then
        # Major version change — ask user
        "$alert_tool" --level caution \
            --title "Python Version Change" \
            --ok "Replace" --cancel "Keep Current" \
            "Target applet has Python ${dst_version}. AppletBuilder has Python ${src_version}. Major version change may break dependencies. Replace?"

        if [ $? -eq 0 ]; then
            log "Replacing Python: v${dst_version} -> v${src_version}"
            /bin/rm -rf "$dst_python"
            /bin/cp -Rp "$src_python" "$dst_python"
        else
            log "Keeping Python v${dst_version} (user choice)"
        fi
        return
    fi

    # Same major — upgrade if src is newer
    local cmp=$(compare_versions "$src_version" "$dst_version")
    if [ "$cmp" = "newer" ]; then
        log "Updating Python: v${dst_version} -> v${src_version}"
        /bin/rm -rf "$dst_python"
        /bin/cp -Rp "$src_python" "$dst_python"
    else
        log "Python v${dst_version} is current"
    fi
}

# Codesign and report result
do_codesign() {
    local target_path="$1"
    log ""

    # Read selected signing identity from picker (tag value)
    local identity="$OMC_ACTIONUI_VIEW_402_VALUE"
    if [ -z "$identity" ]; then
        identity="-"
    fi

    if [ "$identity" = "-" ]; then
        log "Codesigning (ad-hoc)..."
    else
        log "Codesigning with \"${identity}\"..."
    fi

    local log_output=$(applet_codesign "$target_path" "$identity" 2>&1)
    local status=$?
    local timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")

    log ""
    log "$log_output"
    log ""
    if [ $status -eq 0 ]; then
        log "Build succeeded. (${timestamp})"
    else
        log "Build FAILED (exit code: ${status}) (${timestamp})"
    fi
    return $status
}

# ── Main ──

project_path=$(load_project_path)

if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    set_value "$BUILD_LOG_ID" "Error: No project loaded"
    exit 1
fi

app_name=$(/usr/bin/basename "$project_path")
build_log="Building ${app_name}..."
set_value "$BUILD_LOG_ID" "$build_log"

update_framework "$project_path"
update_python "$project_path"
do_codesign "$project_path"
