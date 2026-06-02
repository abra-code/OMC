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
    local src_exe_name="$(plist_read "$builder_path/Contents/Info.plist" CFBundleExecutable)"
    local dst_exe_name="$(plist_read "$target_path/Contents/Info.plist" CFBundleExecutable)"
    /bin/mkdir -p "$target_path/Contents/MacOS"
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

    local cmp=$(compare_versions "$src_version" "$dst_version")

    # Applet already has a newer Python than AppletBuilder (older builder).
    # Replacing would DOWNGRADE the runtime and likely break the applet's
    # scripts and site-packages — never do that automatically.
    if [ "$cmp" = "older" ]; then
        log "Applet has newer Python v${dst_version} than AppletBuilder (v${src_version}) — keeping the applet's runtime."
        log "Update AppletBuilder to manage this applet's Python."
        return
    fi

    # From here AppletBuilder's Python is newer than the applet's.
    local src_major=$(echo "$src_version" | /usr/bin/cut -d. -f1-2)
    local dst_major=$(echo "$dst_version" | /usr/bin/cut -d. -f1-2)

    if [ "$src_major" != "$dst_major" ]; then
        # Major/minor upgrade — confirm, since it may break dependencies.
        "$alert_tool" --level caution \
            --title "Python Version Change" \
            --ok "Upgrade" --cancel "Keep Current" \
            "Applet has Python ${dst_version}. AppletBuilder has newer Python ${src_version}. Upgrading may break dependencies. Upgrade?"

        if [ $? -eq 0 ]; then
            log "Upgrading Python: v${dst_version} -> v${src_version}"
            /bin/rm -rf "$dst_python"
            /bin/cp -Rp "$src_python" "$dst_python"
        else
            log "Keeping Python v${dst_version} (user choice)"
        fi
        return
    fi

    # Same major.minor, builder has newer patch — upgrade silently.
    log "Updating Python: v${dst_version} -> v${src_version}"
    /bin/rm -rf "$dst_python"
    /bin/cp -Rp "$src_python" "$dst_python"
}

# Remove any __pycache__ directories left behind during development
clean_pycache() {
    local target_path="$1"
    local count=$(/usr/bin/find "$target_path" -type d -name "__pycache__" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    if [ "$count" -gt 0 ]; then
        /usr/bin/find "$target_path" -type d -name "__pycache__" -exec /bin/rm -rf {} + 2>/dev/null
        log "Removed ${count} __pycache__ director$([ "$count" -eq 1 ] && echo "y" || echo "ies")"
    fi
}

# Thin universal binaries to a single architecture (selected in Build & Run picker).
# Must run before codesigning — modifying binaries invalidates their signatures.
thin_binaries() {
    local target_path="$1"
    local arch="$OMC_ACTIONUI_VIEW_404_VALUE"

    if [ -z "$arch" ] || [ "$arch" = "none" ]; then
        return
    fi

    log ""
    log "Thinning universal executables to ${arch}..."
    local thin_output=$(/bin/bash "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/thin_distribution.sh" --arch "$arch" "$target_path" 2>&1)
    log "$thin_output"
}

# Run all bundled validators (Command.plist, scripts, ActionUI JSON) against the
# target applet. Logs a per-file summary. Hard errors return 1 so the build
# aborts before codesigning a broken applet; warnings are reported but don't block.
validate_project() {
    local target_path="$1"
    local resources_dir="$target_path/Contents/Resources"
    local error_count=0
    local warning_count=0
    local report=""

    # "Treat Validation Warnings As Errors" toggle (Build & Run pane)
    local warnings_as_errors=0
    local waeval="$OMC_ACTIONUI_VIEW_405_VALUE"
    if [ "$waeval" = "1" ] || [ "$waeval" = "true" ]; then
        warnings_as_errors=1
    fi

    log ""
    log "Validating project..."

    # Command.plist — plutil -lint
    local cmd_plist="$resources_dir/Command.plist"
    if [ -f "$cmd_plist" ]; then
        local plist_out
        plist_out=$(/usr/bin/plutil -lint "$cmd_plist" 2>&1)
        if [ $? -eq 0 ]; then
            log "  Command.plist: OK"
        else
            log "  Command.plist: INVALID"
            error_count=$((error_count + 1))
            report="${report}Command.plist:
${plist_out}

"
        fi
    fi

    # Scripts — per-type syntax check (skips files with no validator)
    local scripts_dir="$resources_dir/Scripts"
    if [ -d "$scripts_dir" ]; then
        local script_ok=0
        local sf sname srci
        for sf in "$scripts_dir"/*; do
            [ ! -f "$sf" ] && continue
            sname=$(/usr/bin/basename "$sf")
            validate_script_file "$sf"
            srci=$?
            if [ "$srci" -eq 0 ]; then
                script_ok=$((script_ok + 1))
            elif [ "$srci" -ne 99 ]; then
                log "  Script ${sname}: SYNTAX ERROR"
                error_count=$((error_count + 1))
                report="${report}Script ${sname}:
${SCRIPT_VALIDATE_OUTPUT}

"
            fi
        done
        log "  Scripts: ${script_ok} OK"
    fi

    # ActionUI JSON — bundled verifier (rc 0 = valid, 2 = warnings, else errors)
    local verifier="${OMC_APP_BUNDLE_PATH}/Contents/Library/actionui_verifier/validate_actionui.py"
    if [ -f "$verifier" ] && [ -x "$python3" ]; then
        local jf jname vout vrc
        for jf in "$resources_dir/Base.lproj"/*.json "$resources_dir"/*.json; do
            [ ! -f "$jf" ] && continue
            jname=$(/usr/bin/basename "$jf")
            vout=$("$python3" "$verifier" "$jf" 2>&1)
            vrc=$?
            if [ "$vrc" -eq 0 ]; then
                log "  UI ${jname}: OK"
            elif [ "$vrc" -eq 2 ]; then
                log "  UI ${jname}: warnings"
                warning_count=$((warning_count + 1))
                report="${report}UI ${jname} (warnings):
${vout}

"
            else
                log "  UI ${jname}: VALIDATION ERROR"
                error_count=$((error_count + 1))
                report="${report}UI ${jname}:
${vout}

"
            fi
        done
    fi

    if [ "$error_count" -eq 0 ] && [ "$warning_count" -eq 0 ]; then
        log "Validation passed."
        return 0
    fi

    log "Validation: ${error_count} error(s), ${warning_count} warning(s)."
    if [ "$error_count" -gt 0 ]; then
        show_errors "Build halted — validation found ${error_count} error(s) and ${warning_count} warning(s):

${report}"
        return 1
    fi

    # Warnings only.
    if [ "$warnings_as_errors" -eq 1 ]; then
        log "  Treating warnings as errors."
        show_errors "Build halted — validation found ${warning_count} warning(s), treated as errors:

${report}"
        return 1
    fi

    # Surface warnings but let the build continue.
    show_errors "Validation found ${warning_count} warning(s); the build will continue:

${report}"
    return 0
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

if ! validate_project "$project_path"; then
    timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")
    log ""
    log "Build halted — fix validation errors and try again. (${timestamp})"
    exit 1
fi

update_framework "$project_path"
update_python "$project_path"
clean_pycache "$project_path"
thin_binaries "$project_path"
do_codesign "$project_path"
