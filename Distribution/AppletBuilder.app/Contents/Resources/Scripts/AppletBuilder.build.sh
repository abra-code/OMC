#!/bin/bash
# AppletBuilder.build - Update framework/runtime, codesign the project applet
# echo "[$(/usr/bin/basename "$0")]"
# env | sort

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.validate.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

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

# Strip the com.apple.quarantine attribute Gatekeeper attaches to files brought
# in from another machine (e.g. an applet codesigned locally elsewhere). Left in
# place it makes codesign / launch report the applet as "damaged". Best-effort
# and recursive over the whole bundle; runs before anything else.
strip_quarantine() {
    local target_path="$1"
    log "Stripping quarantine attribute..."
    /usr/bin/xattr -r -d com.apple.quarantine "$target_path" 2>/dev/null
    return 0
}

# Heuristic: return 0 (true) if a JSON file looks like an ActionUI declaration.
# ActionUI JSON has a root dictionary whose values are element dicts containing
# a "type" key.  Non-ActionUI JSON (e.g. Info.plist-style arrays, bare values,
# or unrelated dictionaries) will return 1.
is_actionui_json() {
    local file="$1"
    local checker="${OMC_APP_BUNDLE_PATH}/Contents/Library/actionui_verifier/is_actionui_json.py"
    "$python3" "$checker" "$file" 2>/dev/null
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

    log ""
    log "Validating project..."

    # Info.plist — plutil -lint
    local info_plist="$target_path/Contents/Info.plist"
    if [ -f "$info_plist" ]; then
        local info_out
        info_out=$(/usr/bin/plutil -lint "$info_plist" 2>&1)
        if [ $? -eq 0 ]; then
            log "  Info.plist: OK"
        else
            log "  Info.plist: INVALID"
            error_count=$((error_count + 1))
            report="${report}Info.plist:
${info_out}

"
        fi
    else
        log "  Info.plist: MISSING"
        error_count=$((error_count + 1))
        report="${report}Info.plist: missing (Contents/Info.plist not found)

"
    fi

    # Command file (Command.json or Command.plist) — fast syntax gate, then the
    # advanced command_verifier (Layer 1 key/type/enum/required/conditional +
    # Layer 2 bundle cross-references).
    local cmd_plist
    cmd_plist=$(command_file_path "$target_path")
    local cmd_label
    cmd_label=$(/usr/bin/basename "$cmd_plist")
    if [ -f "$cmd_plist" ]; then
        local plist_out
        if is_json_command_file "$cmd_plist"; then
            plist_out=$("$python3" -m json.tool "$cmd_plist" 2>&1 >/dev/null)
        else
            plist_out=$(/usr/bin/plutil -lint "$cmd_plist" 2>&1)
        fi
        if [ $? -ne 0 ]; then
            log "  $cmd_label: INVALID"
            error_count=$((error_count + 1))
            report="${report}${cmd_label}:
${plist_out}

"
        else
            local cmd_verifier="${OMC_APP_BUNDLE_PATH}/Contents/Library/command_verifier/validate_command_plist.py"
            if [ -f "$cmd_verifier" ] && [ -x "$python3" ]; then
                local cmd_vout cmd_vrc
                cmd_vout=$("$python3" "$cmd_verifier" "$target_path" 2>&1)   # bundle path → Layer 1 + 2
                cmd_vrc=$?
                if [ "$cmd_vrc" -eq 0 ]; then
                    log "  $cmd_label: OK"
                elif [ "$cmd_vrc" -eq 2 ]; then
                    log "  $cmd_label: warnings"
                    warning_count=$((warning_count + 1))
                    report="${report}${cmd_label} (warnings):
${cmd_vout}

"
                else
                    log "  $cmd_label: VALIDATION ERROR"
                    error_count=$((error_count + 1))
                    report="${report}${cmd_label}:
${cmd_vout}

"
                fi
            else
                log "  $cmd_label: OK"
            fi
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
                if [ -n "$SCRIPT_VALIDATE_WARNINGS" ]; then
                    log "  Script ${sname}: warnings (bash 4+ syntax)"
                    warning_count=$((warning_count + 1))
                    report="${report}Script ${sname} (warnings — macOS ships bash 3.2; these constructs fail at runtime):
${SCRIPT_VALIDATE_WARNINGS}

"
                fi
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
    # Only files matching the ActionUI heuristic (root dict with "type" elements)
    # are validated; unrelated JSON is skipped.
    local verifier="${OMC_APP_BUNDLE_PATH}/Contents/Library/actionui_verifier/validate_actionui.py"
    if [ -f "$verifier" ] && [ -x "$python3" ]; then
        local jf jname vout vrc
        local ui_ok=0
        # Scan every localized .lproj (Base.lproj / English.lproj / en.lproj / …)
        # plus the Resources root.
        for jf in "$resources_dir"/*.lproj/*.json "$resources_dir"/*.json; do
            [ ! -f "$jf" ] && continue
            if ! is_actionui_json "$jf"; then
                continue
            fi
            jname=$(/usr/bin/basename "$jf")
            vout=$("$python3" "$verifier" "$jf" 2>&1)
            vrc=$?
            if [ "$vrc" -eq 0 ]; then
                log "  UI ${jname}: OK"
                ui_ok=$((ui_ok + 1))
            elif [ "$vrc" -eq 2 ]; then
                log "  UI ${jname}: warnings"
                ui_ok=$((ui_ok + 1))
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
        log "  ActionUI JSON: ${ui_ok} validated"
    fi

    finish_validation "Validation" "$error_count" "$warning_count" "$report"
}

# Sanity-check Info.plist *content* against the on-disk bundle. Runs AFTER the
# framework/executable are copied so CFBundleExecutable can be verified against
# the real binary. Missing executable / nib are errors (halt); icon problems are
# warnings (unless "Treat Validation Warnings As Errors" is on).
validate_info_content() {
    local target_path="$1"
    local contents_dir="$target_path/Contents"
    local resources_dir="$contents_dir/Resources"
    local info_plist="$contents_dir/Info.plist"
    local error_count=0
    local warning_count=0
    local report=""

    log ""
    log "Checking Info.plist content..."

    if [ ! -f "$info_plist" ]; then
        # Absence already reported by validate_project; nothing to check against.
        log "  Info.plist: MISSING"
        return 0
    fi

    # CFBundleExecutable → Contents/MacOS/<exe> must exist (checked post-copy).
    local exe
    exe=$(plist_read "$info_plist" CFBundleExecutable)
    if [ -z "$exe" ]; then
        log "  CFBundleExecutable: NOT SET"
        error_count=$((error_count + 1))
        report="${report}CFBundleExecutable: not set in Info.plist

"
    elif [ ! -f "$contents_dir/MacOS/$exe" ]; then
        log "  CFBundleExecutable '${exe}': MISSING"
        error_count=$((error_count + 1))
        report="${report}CFBundleExecutable '${exe}': Contents/MacOS/${exe} not found

"
    else
        log "  CFBundleExecutable '${exe}': OK"
    fi

    # NSMainNibFile → matching .nib must exist in Resources, Base.lproj, or any
    # localized .lproj (English.lproj / en.lproj / …). Cocoa resolves the main nib
    # through the bundle's localization search, so a nib living in the development
    # region's .lproj is valid. Only checked when present (an app may use a
    # storyboard or no main nib).
    local nib
    nib=$(plist_read "$info_plist" NSMainNibFile)
    if [ -n "$nib" ]; then
        local nib_base="${nib%.nib}"
        local nib_found=""
        if [ -e "$resources_dir/${nib_base}.nib" ] || [ -e "$resources_dir/Base.lproj/${nib_base}.nib" ]; then
            nib_found="yes"
        else
            local lproj
            for lproj in "$resources_dir"/*.lproj; do
                [ -d "$lproj" ] || continue
                if [ -e "$lproj/${nib_base}.nib" ]; then
                    nib_found="yes"
                    break
                fi
            done
        fi
        if [ -n "$nib_found" ]; then
            log "  NSMainNibFile '${nib}': OK"
        else
            log "  NSMainNibFile '${nib}': MISSING"
            error_count=$((error_count + 1))
            report="${report}NSMainNibFile '${nib}': ${nib_base}.nib not found in Resources, Base.lproj, or any .lproj

"
        fi
    fi

    # CFBundleIconFile → Resources/<icon>.icns should exist (warning only).
    local iconfile
    iconfile=$(plist_read "$info_plist" CFBundleIconFile)
    if [ -n "$iconfile" ]; then
        local icon_base="${iconfile%.icns}"
        if [ -f "$resources_dir/${icon_base}.icns" ]; then
            log "  CFBundleIconFile '${iconfile}': OK"
        else
            log "  CFBundleIconFile '${iconfile}': missing .icns"
            warning_count=$((warning_count + 1))
            report="${report}CFBundleIconFile '${iconfile}' (warning): ${icon_base}.icns not found in Resources

"
        fi
    fi

    # CFBundleIconName → asset-catalog icon; requires Assets.car. When assetutil
    # is available we confirm the named asset is actually inside it (warning only).
    local iconname
    iconname=$(plist_read "$info_plist" CFBundleIconName)
    if [ -n "$iconname" ]; then
        local assets="$resources_dir/Assets.car"
        if [ ! -f "$assets" ]; then
            log "  CFBundleIconName '${iconname}': Assets.car missing"
            warning_count=$((warning_count + 1))
            report="${report}CFBundleIconName '${iconname}' (warning): Assets.car not found in Resources

"
        elif [ -x /usr/bin/assetutil ]; then
            if /usr/bin/assetutil --info "$assets" 2>/dev/null | /usr/bin/grep -Fq "\"Name\" : \"${iconname}\""; then
                log "  CFBundleIconName '${iconname}': OK"
            else
                log "  CFBundleIconName '${iconname}': not found in Assets.car"
                warning_count=$((warning_count + 1))
                report="${report}CFBundleIconName '${iconname}' (warning): no asset named '${iconname}' found in Assets.car

"
            fi
        else
            # Assets.car present but no assetutil to inspect it — can't confirm.
            log "  CFBundleIconName '${iconname}': Assets.car present (not inspected)"
        fi
    fi

    finish_validation "Info.plist content" "$error_count" "$warning_count" "$report"
}

# Summarize a validation phase and decide whether the build may continue.
# Args: label  error_count  warning_count  report_text
# Reads global WARNINGS_AS_ERRORS ("1" = treat warnings as errors).
# Returns 0 = passed / continue, 1 = halt the build.
finish_validation() {
    local label="$1"
    local errs="$2"
    local warns="$3"
    local rep="$4"

    if [ "$errs" -eq 0 ] && [ "$warns" -eq 0 ]; then
        log "${label} passed."
        return 0
    fi

    log "${label}: ${errs} error(s), ${warns} warning(s)."

    if [ "$errs" -gt 0 ]; then
        show_errors "Build halted — ${label} found ${errs} error(s) and ${warns} warning(s):

${rep}"
        return 1
    fi

    if [ "$WARNINGS_AS_ERRORS" = "1" ]; then
        log "  Treating warnings as errors."
        show_errors "Build halted — ${label} found ${warns} warning(s), treated as errors:

${rep}"
        return 1
    fi

    show_errors "${label} found ${warns} warning(s); the build will continue:

${rep}"
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

# "Treat Validation Warnings As Errors" toggle (Build & Run pane) — shared by
# every validation phase via finish_validation.
WARNINGS_AS_ERRORS=0
__wae="$OMC_ACTIONUI_VIEW_405_VALUE"
if [ "$__wae" = "1" ] || [ "$__wae" = "true" ]; then
    WARNINGS_AS_ERRORS=1
fi

strip_quarantine "$project_path"

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

if ! validate_info_content "$project_path"; then
    timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")
    log ""
    log "Build halted — fix Info.plist and try again. (${timestamp})"
    exit 1
fi

do_codesign "$project_path"
