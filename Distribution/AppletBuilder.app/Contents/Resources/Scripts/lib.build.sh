#!/bin/bash
# lib.build.sh - Applet build / rename / icon / codesign pipeline
#
# Sources lib.common.sh (common base), lib.plist.sh (plist_read / plist_write),
# and lib.validate.sh (the per-file validators used by the build's validate phase).
#
# Output goes through the reporters defined in lib.common.sh (ab_log / ab_report /
# ab_confirm); a GUI handler overrides them to drive its windows, the agent CLI
# leaves the stderr defaults in place. Build options that the GUI reads from form
# controls arrive as shell variables the caller sets before invoking applet_build:
#
#   AB_IDENTITY            codesigning identity (default "-" ad-hoc)
#   AB_THIN_ARCH           thin universal binaries to this arch ("none"/empty = skip)
#   AB_FORCE_UPDATE        "1" = force Abracode.framework/executable refresh
#   AB_WARNINGS_AS_ERRORS  "1" = treat validation warnings as build-halting errors
#   AB_ASSUME_YES          "1" = answer ab_confirm prompts "yes" (e.g. Python upgrade)
#   AB_UPDATE_PYTHON       "1" = allow replacing an existing, working embedded Python
#                          with AppletBuilder's runtime (off by default; a missing or
#                          broken runtime is always (re)installed regardless). Replacing
#                          overwrites Contents/Library/Python wholesale and wipes any
#                          packages pip-installed into its site-packages — install
#                          third-party modules into Contents/Library/Packages instead.

[ -n "$__LIB_BUILD_SH" ] && return 0
__LIB_BUILD_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.plist.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.validate.sh"

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

    # A loop variable needs declaring as much as any other: `for` assigns at
    # global scope otherwise, leaving a stale path behind for any function that
    # reads a variable of the same name without declaring its own.
    local script

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
    # Declared, so it cannot leak into applet_recompile_nib, which reads a
    # variable of this name and does "rm -rf" on it. That function declares its
    # own, but a leaked path aimed at a recursive delete is not a risk to leave
    # standing on the assumption every future reader will remember to.
    local nib_dir
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
            "$python3" \
                "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/json_rename_value.py" \
                "$cmd_plist" "$old_name" "$new_name"
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

# ──────────────────────────────────────────────────────────────
# Build pipeline
#
# Validate the project, refresh the framework/executable/Python runtime from
# AppletBuilder, thin and codesign. Shared by the GUI Build & Run pane and the
# agent CLI; see the AB_* variables documented at the top of this file. All
# progress/error output goes through ab_log / ab_report / ab_confirm.
# ──────────────────────────────────────────────────────────────

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
    ab_log "Stripping quarantine attribute..."
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

# Copy the app executable from AppletBuilder to target (with proper name)
copy_executable() {
    local target_path="$1"
    local src_exe_name="$(plist_read "${OMC_APP_BUNDLE_PATH}/Contents/Info.plist" CFBundleExecutable)"
    local dst_exe_name="$(plist_read "$target_path/Contents/Info.plist" CFBundleExecutable)"
    /bin/mkdir -p "$target_path/Contents/MacOS"
    /bin/cp -p "${OMC_APP_BUNDLE_PATH}/Contents/MacOS/$src_exe_name" \
               "$target_path/Contents/MacOS/$dst_exe_name"
    ab_log "Executable updated: $dst_exe_name"
}

# Install or update Abracode.framework and executable
update_framework() {
    local target_path="$1"
    local src_fw="${OMC_APP_BUNDLE_PATH}/Contents/Frameworks/Abracode.framework"
    local dst_fw="$target_path/Contents/Frameworks/Abracode.framework"
    local src_version=$(plist_read "$src_fw/Resources/Info.plist" CFBundleVersion)

    if [ ! -d "$dst_fw" ]; then
        ab_log "Abracode.framework missing — installing v${src_version}"
        /bin/mkdir -p "$target_path/Contents/Frameworks"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
        return
    fi

    local dst_version=$(plist_read "$dst_fw/Resources/Info.plist" CFBundleVersion)
    local force_update="$AB_FORCE_UPDATE"

    if [ "$force_update" = "1" ] || [ "$force_update" = "true" ]; then
        ab_log "Updating Abracode.framework: v${dst_version} -> v${src_version} (forced)"
        /bin/rm -rf "$dst_fw"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
        return
    fi

    local cmp=$(compare_versions "$src_version" "$dst_version")

    if [ "$cmp" = "newer" ]; then
        ab_log "Updating Abracode.framework: v${dst_version} -> v${src_version}"
        /bin/rm -rf "$dst_fw"
        /bin/cp -Rp "$src_fw" "$dst_fw"
        copy_executable "$target_path"
    else
        ab_log "Abracode.framework v${dst_version} is current"
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
    local src_python="${OMC_APP_BUNDLE_PATH}/Contents/Library/Python"
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
        ab_log "Python runtime missing — installing v${src_version}"
        /bin/mkdir -p "$target_path/Contents/Library"
        /bin/cp -Rp "$src_python" "$dst_python"
        return
    fi

    local dst_version=$(python_version "$dst_python")

    if [ -z "$dst_version" ]; then
        ab_log "Python runtime broken — reinstalling v${src_version}"
        /bin/rm -rf "$dst_python"
        /bin/cp -Rp "$src_python" "$dst_python"
        return
    fi

    if [ "$src_version" = "$dst_version" ]; then
        ab_log "Python v${dst_version} is current"
        return
    fi

    local cmp=$(compare_versions "$src_version" "$dst_version")

    # Applet already has a newer Python than AppletBuilder (older builder).
    # Replacing would DOWNGRADE the runtime and likely break the applet's
    # scripts and site-packages — never do that automatically.
    if [ "$cmp" = "older" ]; then
        ab_log "Applet has newer Python v${dst_version} than AppletBuilder (v${src_version}) — keeping the applet's runtime."
        ab_log "Update AppletBuilder to manage this applet's Python."
        return
    fi

    # Replacing a working runtime is opt-in: it overwrites Contents/Library/Python
    # wholesale, wiping anything pip-installed into its site-packages. Off by default
    # so inline-installed modules survive a rebuild. It is independent of the binary
    # refresh (AB_FORCE_UPDATE / --force): enable the "Update Embedded Python" build
    # option (CLI: --update-python) to allow it. The rebuild-safe place for
    # third-party modules is Contents/Library/Packages, which OMC adds to PYTHONPATH
    # and this build step never touches.
    if [ "${AB_UPDATE_PYTHON:-0}" != "1" ]; then
        ab_log "Embedded Python v${dst_version} kept (AppletBuilder has v${src_version}; enable \"Update Embedded Python\" to replace it)."
        return
    fi

    # From here AppletBuilder's Python is newer than the applet's.
    local src_major=$(echo "$src_version" | /usr/bin/cut -d. -f1-2)
    local dst_major=$(echo "$dst_version" | /usr/bin/cut -d. -f1-2)

    if [ "$src_major" != "$dst_major" ]; then
        # Major/minor upgrade — confirm, since it may break dependencies.
        if ab_confirm "Applet has Python ${dst_version}. AppletBuilder has newer Python ${src_version}. Upgrading may break dependencies. Upgrade?"; then
            ab_log "Upgrading Python: v${dst_version} -> v${src_version}"
            /bin/rm -rf "$dst_python"
            /bin/cp -Rp "$src_python" "$dst_python"
        else
            ab_log "Keeping Python v${dst_version} (user choice)"
        fi
        return
    fi

    # Same major.minor, builder has newer patch — upgrade silently.
    ab_log "Updating Python: v${dst_version} -> v${src_version}"
    /bin/rm -rf "$dst_python"
    /bin/cp -Rp "$src_python" "$dst_python"
}

# Install the OMC-supplied Python modules into an applet that has Python handlers.
#
# Contents/Library/Packages is the applet's own module directory: the engine prepends it to
# PYTHONPATH whenever the applet embeds Python, and update_python never touches it, so these
# survive a runtime upgrade that wipes Contents/Library/Python wholesale. A developer's own
# pip --target installs sit alongside them.
#
# Requires BOTH a Python handler and an embedded runtime. Without the runtime the engine does not
# put Packages on PYTHONPATH at all, so copying there would ship modules the applet cannot import.
# Overwrites unconditionally: these ship with OMC and are versioned with it, like the framework.
#
# Returns 1 when an applet that SHOULD have the modules could not get them, and applet_build halts
# on that. Signing an applet whose handlers will fail with ModuleNotFoundError on first run, after
# reporting "Build succeeded", is worse than refusing to sign it.
update_python_packages() {
    local target_path="$1"
    local src_packages="${OMC_APP_BUNDLE_PATH}/Contents/Library/Packages"
    local dst_packages="$target_path/Contents/Library/Packages"

    local _py_handlers
    _py_handlers=$(/usr/bin/find "$target_path/Contents/Resources/Scripts" -name "*.py" -print -quit 2>/dev/null)
    if [ -z "$_py_handlers" ]; then
        return
    fi

    if [ ! -d "$target_path/Contents/Library/Python" ]; then
        # External-interpreter applet. The engine only puts Packages on PYTHONPATH for an embedded
        # runtime, so the modules would be unimportable; say so rather than skipping in silence.
        ab_log "Python handlers but no embedded runtime - skipping OMC Python modules (they would not be importable)"
        return 0
    fi

    if [ ! -d "$src_packages" ]; then
        ab_report "Error: OMC Python modules not found at $src_packages"
        ab_report "       This AppletBuilder predates them; rerun update_appletbuilder.sh."
        return 1
    fi

    /bin/mkdir -p "$dst_packages"
    local _mkdir_rc=$?
    if [ "$_mkdir_rc" -ne 0 ]; then
        ab_report "Error: could not create $dst_packages"
        return 1
    fi

    local module
    local copied=0
    local failed=0
    local _cp_rc
    for module in actionui_remote.py omc.py; do
        if [ ! -f "$src_packages/$module" ]; then
            ab_report "Error: $module is missing from AppletBuilder; rerun update_appletbuilder.sh"
            failed=$((failed + 1))
            continue
        fi

        /bin/cp "$src_packages/$module" "$dst_packages/$module"
        _cp_rc=$?
        if [ "$_cp_rc" -ne 0 ]; then
            ab_report "Error: could not copy $module to $dst_packages"
            failed=$((failed + 1))
            continue
        fi
        copied=$((copied + 1))
    done

    if [ "$copied" -gt 0 ]; then
        ab_log "Installed $copied OMC Python module(s) into Contents/Library/Packages"
    fi

    if [ "$failed" -gt 0 ]; then
        return 1
    fi
    return 0
}

# The ActionUI remote bridge's shell clients, into Contents/Library/Packages beside the Python
# one. Gated on a shell handler rather than on a Python runtime, because a shell handler needs no
# runtime - and it is the one kind of handler that can hold the bridge's token without showing it
# to `ps`, every Apple shell carrying CS_RESTRICT where python3 and node do not.
#
# Both files or neither: actionui_remote.zsh sources actionui_remote.sh from its own directory.
# Overwritten unconditionally, like the Python modules: these ship with OMC and version with it.
#
# Not fatal to a build. A shell handler that never touches the bridge - which is most of them -
# is not broken by their absence, so a missing client is reported and the build goes on. That is
# the opposite of update_python_packages, where the modules ARE the handler's imports.
update_shell_clients() {
    local target_path="$1"
    local src_packages="${OMC_APP_BUNDLE_PATH}/Contents/Library/Packages"
    local dst_packages="$target_path/Contents/Library/Packages"

    local _sh_handlers
    _sh_handlers=$(/usr/bin/find "$target_path/Contents/Resources/Scripts" \
                   \( -name "*.sh" -o -name "*.zsh" \) -print -quit 2>/dev/null)
    if [ -z "$_sh_handlers" ]; then
        return 0
    fi

    local client
    local missing=0
    for client in actionui_remote.sh actionui_remote.zsh; do
        if [ ! -f "$src_packages/$client" ]; then
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        ab_log "ActionUI shell client(s) missing from AppletBuilder - skipping (rerun update_appletbuilder.sh)"
        return 0
    fi

    /bin/mkdir -p "$dst_packages"
    local _mkdir_rc=$?
    if [ "$_mkdir_rc" -ne 0 ]; then
        ab_log "Could not create $dst_packages - skipping the ActionUI shell clients"
        return 0
    fi

    local copied=0
    local _cp_rc
    local _chmod_rc
    for client in actionui_remote.sh actionui_remote.zsh; do
        /bin/cp "$src_packages/$client" "$dst_packages/$client"
        _cp_rc=$?
        if [ "$_cp_rc" -ne 0 ]; then
            ab_log "Could not copy $client to $dst_packages"
            continue
        fi

        /bin/chmod 755 "$dst_packages/$client"
        _chmod_rc=$?
        if [ "$_chmod_rc" -ne 0 ]; then
            ab_log "Could not make $client executable in $dst_packages"
            continue
        fi
        copied=$((copied + 1))
    done

    if [ "$copied" -gt 0 ]; then
        ab_log "Installed $copied ActionUI shell client(s) into Contents/Library/Packages"
    fi
    return 0
}

# Remove development junk from the applet.
#
# Must run immediately before codesigning: almost anything still present is
# sealed into CodeResources, and deleting it afterward invalidates the
# signature. (.DS_Store is the lone exception - codesign carries an omit rule
# for it - but nothing else on these lists is forgiven.)
#
# An OMC applet is edited in place - the .app bundle IS the project - and the
# copy that gets signed and notarized is made from it. So junk left here does
# not just clutter a working directory, it ships. Editor and agent config
# (.claude, .idea, .vscode), tool caches and Finder droppings are all removed
# outright; anything worth keeping belongs outside the bundle.
#
# .git is deliberately NOT swept: deleting a versioned applet's history during
# a routine build would be unrecoverable, which is a different order of harm
# than losing a settings file. It is reported instead, because a versioned
# applet still carries its whole repository into the signed copy.
#
# Returns 1 only when junk survived the sweep and AB_WARNINGS_AS_ERRORS is set;
# a surviving item is a permanent defect in the signed artifact, so that case
# halts the build rather than signing over it.
clean_build_junk() {
    local target_path="$1"

    # find descends nothing when handed a symlink as its start path, so a
    # symlinked project would sweep zero files and still report success - the
    # one false green this function's before/after accounting cannot catch.
    # Resolve to the physical path first. (The CLI's own `[ ! -d ]` guard
    # follows symlinks, so `appletbuilder build ~/link-to-MyApp.app` reaches
    # here.)
    target_path=$(cd "$target_path" >/dev/null 2>&1 && /bin/pwd -P)
    if [ -z "$target_path" ]; then
        ab_report "Error: could not resolve the project path to sweep for junk"
        return 1
    fi

    # Every pattern is quoted individually, and that - not the array - is what
    # keeps it literal: array construction globs like any other word expansion,
    # so a bare *.pyc here would expand against the current directory before
    # find saw it. Containers are listed before __pycache__ so nested junk
    # inside a swept container is not counted twice.
    local junk_dirs=( ".claude" ".idea" ".vscode" ".pytest_cache" ".mypy_cache" ".ruff_cache" "__pycache__" )
    # *.thin.tmp is thin_distribution.sh's scratch file, left beside a real
    # Mach-O if lipo is interrupted rather than merely failing.
    local junk_files=( ".DS_Store" "._*" "*.pyc" "*.pyo" "*.thin.tmp" "Thumbs.db" )
    # Losing one of these costs developer config rather than a regenerable
    # cache, and rm does not use the Trash, so name each path instead of
    # folding it into a count.
    local loud_dirs=" .claude .idea .vscode "

    local junk before after removed path
    local stuck=0
    local header=0

    # Counts are the difference between a scan before and a scan after the
    # delete, never the pre-scan alone: rm and -delete have their errors
    # discarded here, so a sweep that fails on a locked or root-owned path
    # would otherwise report success and let the junk be signed in anyway.
    for junk in "${junk_dirs[@]}"; do
        # -prune keeps find from descending into a directory it is about to
        # delete and then complaining about the paths that just vanished.
        # -type l alongside -type d for the same reason the file sweep needs it:
        # a symlink named __pycache__ or .claude is sealed just like a real
        # directory, and -type d walks straight past it. rm -rf on a symlink
        # removes the link, never the target.
        before=$(/usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$before" -eq 0 ] && continue
        if [ "$header" -eq 0 ]; then
            ab_log ""
            ab_log "Removing development junk..."
            header=1
        fi
        case "$loud_dirs" in
            *" $junk "*)
                /usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune 2>/dev/null | while read -r path; do
                    ab_log "  removing ${path#"$target_path"/}"
                done
                ;;
        esac
        /usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune -exec /bin/rm -rf {} + 2>/dev/null
        after=$(/usr/bin/find "$target_path" \( -type d -o -type l \) -name "$junk" -prune 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        removed=$((before - after))
        if [ "$removed" -gt 0 ]; then
            ab_log "Removed ${removed} ${junk} director$([ "$removed" -eq 1 ] && echo "y" || echo "ies")"
        fi
        if [ "$after" -gt 0 ]; then
            ab_log "WARNING: ${junk}: ${after} of ${before} could not be removed"
            stuck=$((stuck + after))
        fi
    done

    # -type l as well as -type f: a symlink named ._x or stale.pyc is junk that
    # gets sealed just the same, and -type f alone walks straight past it.
    # -iname because a Windows SMB client writes thumbs.db onto a
    # case-insensitive volume and -name "Thumbs.db" would miss it.
    for junk in "${junk_files[@]}"; do
        before=$(/usr/bin/find "$target_path" \( -type f -o -type l \) -iname "$junk" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$before" -eq 0 ] && continue
        if [ "$header" -eq 0 ]; then
            ab_log ""
            ab_log "Removing development junk..."
            header=1
        fi
        /usr/bin/find "$target_path" \( -type f -o -type l \) -iname "$junk" -delete 2>/dev/null
        after=$(/usr/bin/find "$target_path" \( -type f -o -type l \) -iname "$junk" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        removed=$((before - after))
        if [ "$removed" -gt 0 ]; then
            ab_log "Removed ${removed} ${junk} file$([ "$removed" -eq 1 ] && echo "" || echo "s")"
        fi
        if [ "$after" -gt 0 ]; then
            ab_log "WARNING: ${junk}: ${after} of ${before} could not be removed"
            stuck=$((stuck + after))
        fi
    done

    # Never deleted, only reported - losing a versioned applet's history to a
    # routine build is not a tradeoff this function gets to make for anyone.
    local vcs
    for vcs in ".git" ".svn"; do
        before=$(/usr/bin/find "$target_path" -type d -name "$vcs" -prune 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
        [ "$before" -eq 0 ] && continue
        # ab_log, not ab_report: this fires on every build of a versioned
        # applet, and in the GUI ab_report is an error window. A recurring
        # popup the developer learns to dismiss would devalue the one report
        # below that actually means the artifact is broken.
        ab_log "WARNING: ${vcs} left in place (not removed); it will be sealed into the signed copy"
    done

    if [ "$stuck" -gt 0 ]; then
        ab_report "WARNING: ${stuck} junk item(s) survived and will be signed into the applet"
        [ "$AB_WARNINGS_AS_ERRORS" = "1" ] && return 1
    fi
    return 0
}

# Thin universal binaries to a single architecture (AB_THIN_ARCH).
# Must run before codesigning — modifying binaries invalidates their signatures.
thin_binaries() {
    local target_path="$1"
    local arch="$AB_THIN_ARCH"

    if [ -z "$arch" ] || [ "$arch" = "none" ]; then
        return
    fi

    ab_log ""
    ab_log "Thinning universal executables to ${arch}..."
    local thin_output=$(/bin/bash "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/thin_distribution.sh" --arch "$arch" "$target_path" 2>&1)
    ab_log "$thin_output"
}

# Run all bundled validators (command file, scripts, ActionUI JSON) against the
# target applet. Logs a per-file summary. Hard errors return 1 so the build
# aborts before codesigning a broken applet; warnings are reported but don't block.
validate_project() {
    local target_path="$1"
    local resources_dir="$target_path/Contents/Resources"
    local error_count=0
    local warning_count=0
    local report=""

    ab_log ""
    ab_log "Validating project..."

    # Info.plist — plutil -lint
    local info_plist="$target_path/Contents/Info.plist"
    if [ -f "$info_plist" ]; then
        local info_out
        info_out=$(/usr/bin/plutil -lint "$info_plist" 2>&1)
        if [ $? -eq 0 ]; then
            ab_log "  Info.plist: OK"
        else
            ab_log "  Info.plist: INVALID"
            error_count=$((error_count + 1))
            report="${report}Info.plist:
${info_out}

"
        fi
    else
        ab_log "  Info.plist: MISSING"
        error_count=$((error_count + 1))
        report="${report}Info.plist: missing (Contents/Info.plist not found)

"
    fi

    # Command file (Command.json or Command.plist) — shared validator: fast syntax
    # gate, then the advanced command_verifier (Layer 1 + bundle Layer 2).
    local cmd_plist
    cmd_plist=$(command_file_path "$target_path")
    local cmd_label
    cmd_label=$(/usr/bin/basename "$cmd_plist")
    if [ -f "$cmd_plist" ]; then
        validate_command_file "$target_path"
        local cmd_vrc=$?
        if [ "$cmd_vrc" -eq 0 ]; then
            ab_log "  $cmd_label: OK"
        elif [ "$cmd_vrc" -eq 2 ]; then
            ab_log "  $cmd_label: warnings"
            warning_count=$((warning_count + 1))
            report="${report}${cmd_label} (warnings):
${COMMAND_VALIDATE_OUTPUT}

"
        elif [ "$cmd_vrc" -eq 3 ]; then
            ab_log "  $cmd_label: INVALID"
            error_count=$((error_count + 1))
            report="${report}${cmd_label}:
${COMMAND_VALIDATE_OUTPUT}

"
        else
            ab_log "  $cmd_label: VALIDATION ERROR"
            error_count=$((error_count + 1))
            report="${report}${cmd_label}:
${COMMAND_VALIDATE_OUTPUT}

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
                if [ -n "$SCRIPT_VALIDATE_WARNINGS" ]; then
                    ab_log "  Script ${sname}: warnings (bash 4+ syntax)"
                    warning_count=$((warning_count + 1))
                    report="${report}Script ${sname} (warnings — macOS ships bash 3.2; these constructs fail at runtime):
${SCRIPT_VALIDATE_WARNINGS}

"
                fi
            elif [ "$srci" -ne 99 ]; then
                ab_log "  Script ${sname}: SYNTAX ERROR"
                error_count=$((error_count + 1))
                report="${report}Script ${sname}:
${SCRIPT_VALIDATE_OUTPUT}

"
            fi
        done
        ab_log "  Scripts: ${script_ok} OK"
    fi

    # ActionUI JSON — bundled verifier (rc 0 = valid, 2 = warnings, else errors)
    # Only files matching the ActionUI heuristic (root dict with "type" elements)
    # are validated; unrelated JSON is skipped.
    local verifier="${OMC_APP_BUNDLE_PATH}/Contents/Library/actionui_verifier/validate_actionui.py"
    if [ -f "$verifier" ] && [ -x "$python3" ]; then
        local jf jname vrc
        local ui_ok=0
        # Scan every localized .lproj (Base.lproj / English.lproj / en.lproj / …)
        # plus the Resources root.
        for jf in "$resources_dir"/*.lproj/*.json "$resources_dir"/*.json; do
            [ ! -f "$jf" ] && continue
            if ! is_actionui_json "$jf"; then
                continue
            fi
            jname=$(/usr/bin/basename "$jf")
            validate_actionui_file "$jf"
            vrc=$?
            if [ "$vrc" -eq 0 ]; then
                ab_log "  UI ${jname}: OK"
                ui_ok=$((ui_ok + 1))
            elif [ "$vrc" -eq 2 ]; then
                ab_log "  UI ${jname}: warnings"
                ui_ok=$((ui_ok + 1))
                warning_count=$((warning_count + 1))
                report="${report}UI ${jname} (warnings):
${ACTIONUI_VALIDATE_OUTPUT}

"
            else
                ab_log "  UI ${jname}: VALIDATION ERROR"
                error_count=$((error_count + 1))
                report="${report}UI ${jname}:
${ACTIONUI_VALIDATE_OUTPUT}

"
            fi
        done
        ab_log "  ActionUI JSON: ${ui_ok} validated"
    fi

    # Build/profiling droppings — an LLVM coverage-instrumented binary dumps default.profraw
    # into its CWD at exit, so running one with CWD inside the bundle (a build script's verify
    # step, say) plants the file IN the bundle; ship nothing of the kind. Warned, not errored:
    # the applet still runs, it is just carrying dead weight.
    local droppings
    droppings=$(/usr/bin/find "$target_path" \( -name "*.profraw" -o -name "*.profdata" \) 2>/dev/null)
    if [ -n "$droppings" ]; then
        ab_log "  Profiling droppings: warning"
        warning_count=$((warning_count + 1))
        report="${report}Profiling droppings (delete before shipping; if they reappear, an instrumented binary is being run with CWD inside the bundle):
${droppings}

"
    fi

    # A nudge, never an error: it does not touch either counter, so it cannot
    # change the exit status here or halt a build. This runs inside
    # validate_project, which applet_build also calls, so the line appears
    # during a plain build of a test-less applet too - accepted, because one
    # advisory line is cheap and keeping the check in the shared path is what
    # makes the CLI and the GUI say the same thing.
    local tests_dir
    tests_dir=$(applet_tests_dir "$target_path")
    if [ -z "$tests_dir" ] || [ ! -d "$tests_dir" ]; then
        ab_log "  [INFO] no Tests/ directory - consider the Test button or 'appletbuilder test' (see omctest_guide.md)"
    fi

    finish_validation "Validation" "$error_count" "$warning_count" "$report"
}

# Sanity-check Info.plist *content* against the on-disk bundle. Runs AFTER the
# framework/executable are copied so CFBundleExecutable can be verified against
# the real binary. Missing executable / nib are errors (halt); icon problems are
# warnings (unless AB_WARNINGS_AS_ERRORS is on).
validate_info_content() {
    local target_path="$1"
    local contents_dir="$target_path/Contents"
    local resources_dir="$contents_dir/Resources"
    local info_plist="$contents_dir/Info.plist"
    local error_count=0
    local warning_count=0
    local report=""

    ab_log ""
    ab_log "Checking Info.plist content..."

    if [ ! -f "$info_plist" ]; then
        # Absence already reported by validate_project; nothing to check against.
        ab_log "  Info.plist: MISSING"
        return 0
    fi

    # CFBundleExecutable → Contents/MacOS/<exe> must exist (checked post-copy).
    local exe
    exe=$(plist_read "$info_plist" CFBundleExecutable)
    if [ -z "$exe" ]; then
        ab_log "  CFBundleExecutable: NOT SET"
        error_count=$((error_count + 1))
        report="${report}CFBundleExecutable: not set in Info.plist

"
    elif [ ! -f "$contents_dir/MacOS/$exe" ]; then
        ab_log "  CFBundleExecutable '${exe}': MISSING"
        error_count=$((error_count + 1))
        report="${report}CFBundleExecutable '${exe}': Contents/MacOS/${exe} not found

"
    else
        ab_log "  CFBundleExecutable '${exe}': OK"
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
            ab_log "  NSMainNibFile '${nib}': OK"
        else
            ab_log "  NSMainNibFile '${nib}': MISSING"
            error_count=$((error_count + 1))
            report="${report}NSMainNibFile '${nib}': ${nib_base}.nib not found in Resources, Base.lproj, or any .lproj

"
        fi
    fi

    # Menu source: a nib applet builds its bar from MainMenu.nib (NSMainNibFile,
    # checked above).  A nibless applet (OMC 5.1+) builds the standard macOS menu
    # bar (App/File/Edit/Format/Window/Help) programmatically; an optional
    # MainMenu.json layers additions/mutations/removals on top.  So when
    # NSMainNibFile is absent neither file is required — just note which menu
    # source is in effect (informational, no warning either way).
    if [ -z "$nib" ]; then
        local menu_json_found=""
        if [ -e "$resources_dir/MainMenu.json" ] || [ -e "$resources_dir/Base.lproj/MainMenu.json" ]; then
            menu_json_found="yes"
        else
            local mlproj
            for mlproj in "$resources_dir"/*.lproj; do
                [ -d "$mlproj" ] || continue
                if [ -e "$mlproj/MainMenu.json" ]; then
                    menu_json_found="yes"
                    break
                fi
            done
        fi
        if [ -n "$menu_json_found" ]; then
            ab_log "  Menu source: standard bar + MainMenu.json overrides"
        else
            ab_log "  Menu source: standard bar (programmatic; no MainMenu.json overrides)"
        fi
    fi

    # CFBundleIconFile → Resources/<icon>.icns should exist (warning only).
    local iconfile
    iconfile=$(plist_read "$info_plist" CFBundleIconFile)
    if [ -n "$iconfile" ]; then
        local icon_base="${iconfile%.icns}"
        if [ -f "$resources_dir/${icon_base}.icns" ]; then
            ab_log "  CFBundleIconFile '${iconfile}': OK"
        else
            ab_log "  CFBundleIconFile '${iconfile}': missing .icns"
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
            ab_log "  CFBundleIconName '${iconname}': Assets.car missing"
            warning_count=$((warning_count + 1))
            report="${report}CFBundleIconName '${iconname}' (warning): Assets.car not found in Resources

"
        elif [ -x /usr/bin/assetutil ]; then
            if /usr/bin/assetutil --info "$assets" 2>/dev/null | /usr/bin/grep -Fq "\"Name\" : \"${iconname}\""; then
                ab_log "  CFBundleIconName '${iconname}': OK"
            else
                ab_log "  CFBundleIconName '${iconname}': not found in Assets.car"
                warning_count=$((warning_count + 1))
                report="${report}CFBundleIconName '${iconname}' (warning): no asset named '${iconname}' found in Assets.car

"
            fi
        else
            # Assets.car present but no assetutil to inspect it — can't confirm.
            ab_log "  CFBundleIconName '${iconname}': Assets.car present (not inspected)"
        fi
    fi

    finish_validation "Info.plist content" "$error_count" "$warning_count" "$report"
}

# Summarize a validation phase and decide whether the build may continue.
# Args: label  error_count  warning_count  report_text
# Reads AB_WARNINGS_AS_ERRORS ("1" = treat warnings as errors).
# Returns 0 = passed / continue, 1 = halt the build.
finish_validation() {
    local label="$1"
    local errs="$2"
    local warns="$3"
    local rep="$4"

    if [ "$errs" -eq 0 ] && [ "$warns" -eq 0 ]; then
        ab_log "${label} passed."
        return 0
    fi

    ab_log "${label}: ${errs} error(s), ${warns} warning(s)."

    if [ "$errs" -gt 0 ]; then
        ab_report "Build halted — ${label} found ${errs} error(s) and ${warns} warning(s):

${rep}"
        return 1
    fi

    if [ "$AB_WARNINGS_AS_ERRORS" = "1" ]; then
        ab_log "  Treating warnings as errors."
        ab_report "Build halted — ${label} found ${warns} warning(s), treated as errors:

${rep}"
        return 1
    fi

    ab_report "${label} found ${warns} warning(s); the build will continue:

${rep}"
    return 0
}

# Codesign and report result. Reads AB_IDENTITY (default "-" ad-hoc).
do_codesign() {
    local target_path="$1"
    ab_log ""

    local identity="$AB_IDENTITY"
    if [ -z "$identity" ]; then
        identity="-"
    fi

    if [ "$identity" = "-" ]; then
        ab_log "Codesigning (ad-hoc)..."
    else
        ab_log "Codesigning with \"${identity}\"..."
    fi

    # log_output is declared apart from its assignment on purpose: `local x=$(cmd)`
    # runs the substitution as part of `local`, so the next $? reads local's own
    # status - always 0 - which reported every codesigning failure as "Build
    # succeeded" and returned 0 to applet_build, whose contract is to return 1
    # when signing fails. Nothing may run between the assignment and the $? read,
    # so the timestamp below is deliberately taken after it.
    local log_output
    log_output=$(applet_codesign "$target_path" "$identity" 2>&1)
    local status=$?
    local timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")

    ab_log ""
    ab_log "$log_output"
    ab_log ""
    if [ $status -eq 0 ]; then
        ab_log "Build succeeded. (${timestamp})"
    else
        ab_log "Build FAILED (exit code: ${status}) (${timestamp})"
    fi
    return $status
}

# Top-level build orchestrator. Validates, refreshes runtime, cleans junk, thins,
# codesigns.
# Reads the AB_* options documented at the top of this file. Returns 0 on success,
# 1 if the build is halted by validation or fails to codesign.
applet_build() {
    local project_path="$1"

    if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
        ab_report "Error: No project loaded"
        return 1
    fi

    local app_name
    app_name=$(/usr/bin/basename "$project_path")
    ab_log "Building ${app_name}..."

    strip_quarantine "$project_path"

    if ! validate_project "$project_path"; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted — fix validation errors and try again. (${ts})"
        return 1
    fi

    update_framework "$project_path"
    update_python "$project_path"

    update_python_packages "$project_path"
    local packages_rc=$?
    if [ "$packages_rc" -ne 0 ]; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted - the OMC Python modules could not be installed. (${ts})"
        return 1
    fi

    update_shell_clients "$project_path"

    thin_binaries "$project_path"

    if ! validate_info_content "$project_path"; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted — fix Info.plist and try again. (${ts})"
        return 1
    fi

    # --test, and only --test: tests are applet-authored code with arbitrary
    # runtime, and a developer mid-refactor must be able to rebuild an app whose
    # tests are momentarily red.
    #
    # Placed here on purpose - after the framework, executable and Python have
    # been refreshed, and before signing. That order is the point of running
    # them at all in a build: it tests the tool versions that will actually
    # ship, and it halts in the same place a validation error halts, so nothing
    # unsigned-but-broken ever reaches the signing step.
    if [ "$AB_RUN_TESTS" = "1" ]; then
        if ! applet_run_tests "$project_path"; then
            local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
            ab_log ""
            ab_log "Build halted - tests failed. (${ts})"
            return 1
        fi
    fi

    # Last thing before signing, deliberately. thin_binaries leaves a
    # *.thin.tmp beside a binary if lipo is interrupted, and applet-authored
    # tests are arbitrary code with write access to their own bundle - both
    # happen after the old call site, so sweeping earlier let their leavings
    # get sealed.
    if ! clean_build_junk "$project_path"; then
        local ts=$(/bin/date "+%Y-%m-%d %H:%M:%S")
        ab_log ""
        ab_log "Build halted - junk could not be removed and would be signed in. (${ts})"
        return 1
    fi

    do_codesign "$project_path"
}

# Where an applet's omctest suite lives: a Tests/ directory NEXT TO the bundle,
# never inside it (tests in the bundle would bloat the shipped app and dirty its
# code signature). Prints the path; returns non-zero if the parent directory
# cannot be resolved, in which case nothing is printed.
applet_tests_dir() { # <project-path>
    local parent
    parent=$(cd "$(/usr/bin/dirname "$1")" >/dev/null 2>&1 && pwd) || return 1
    [ -n "$parent" ] || return 1
    printf '%s/Tests\n' "$parent"
}

# Run the applet's omctest suite. Returns non-zero when the suite fails or when
# it was asked for and there is nothing to run.
applet_run_tests() {
    local project_path="$1"
    local tests_dir omctest_lib rc

    tests_dir=$(applet_tests_dir "$project_path")
    if [ -z "$tests_dir" ] || [ ! -d "$tests_dir" ]; then
        # Running tests is always an explicit request - the --test flag or the
        # Test button. Failing loudly beats a silent skip, which would let a
        # release flow believe tests had run.
        ab_report "No Tests/ directory beside the applet: ${tests_dir:-$project_path}"
        return 1
    fi

    omctest_lib="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Agents/omctest.sh"
    if [ ! -f "$omctest_lib" ]; then
        ab_report "The omctest harness is missing at $omctest_lib"
        return 1
    fi

    ab_log "Running tests..."
    export OMCTEST_RUNNER=1
    export OMCTEST_LIB="$omctest_lib"
    # shellcheck source=../Agents/omctest.sh
    source "$omctest_lib"

    # The suite reports for itself: per-check detail on stderr, one
    # machine-readable summary line on stdout. Merge both and hand the stream to
    # ab_log_stream, which is what puts the whole transcript in the GUI's log
    # pane while leaving the CLI's live stderr streaming exactly as it was.
    #
    # A ( ) SUBSHELL, not a { } group. On bash 3.2 - which is what /bin/sh is,
    # and what the engine runs handlers under - an EXIT trap set inside a brace
    # group used as a pipeline element never runs. omctest_run_suite's only
    # cleanup for the scratch tree it creates is exactly such a trap, so with a
    # brace group here every test run leaked a whole scratch tree (a stub
    # support/ directory and a copy of every fixture, per test file). zsh runs
    # the trap in both shapes, so this does not reproduce in an interactive
    # shell.
    ( omctest_run_suite "$project_path" "$tests_dir" 2>&1 ) | ab_log_stream
    # Read on the very next line: any command in between overwrites PIPESTATUS,
    # and plain $? here is the reader's status, not the suite's.
    rc=${PIPESTATUS[0]}
    # A missing or garbled status is a failure, not a pass: the alternative is
    # reporting green for a suite whose result was never read.
    case "$rc" in
        ''|*[!0-9]*) rc=1 ;;
    esac
    return "$rc"
}
