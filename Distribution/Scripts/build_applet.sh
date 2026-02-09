#!/bin/bash
# build_applet.sh
# Create new applet by copying + renaming from any OMC-style base .app

set -uo pipefail

# ──────────────────────────────────────────────────────────────
# Global variables
# ──────────────────────────────────────────────────────────────

BASE_APP=""
ICON_SOURCE=""
CREATOR_CODE=""
BUNDLE_ID=""
NEW_PATH=""
VERBOSE=0
ORIGINAL_NAME=""
NEW_APPLET_NAME=""
NEW_ICON_INSTALLED=0

# ──────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────

show_help() {
    cat << 'EOF'
Usage: build_applet.sh [options] <new_applet_name>

Options:
  --omc-applet=PATH          Base applet to copy from (default: script dir / OMCApplet.app)
  -i, --icon=PATH            Icon Composer .icon file to compile into Assets.car
  -c, --creator=XXXX         4-char creator code (updates PkgInfo & CFBundleSignature)
  -b, --bundle-id=ID         Full CFBundleIdentifier override (e.g. com.company.NewApplet)
  -v, --verbose              Print steps
  -h, --help                 Show this help
EOF
    exit 0
}

# ──────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────

log()  { [ $VERBOSE -eq 1 ] && echo "$@"; }
fail() { echo "Error: $*" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────
# Parse arguments & assign to global variables
# ──────────────────────────────────────────────────────────────

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --omc-applet=*) BASE_APP="${1#*=}" ; shift ;;
            -i|--icon=*)    ICON_SOURCE="${1#*=}" ; shift ;;
            -c|--creator=*) CREATOR_CODE="${1#*=}" ; shift ;;
            -b|--bundle-id=*) BUNDLE_ID="${1#*=}" ; shift ;;
            -v|--verbose)   VERBOSE=1 ; shift ;;
            -h|--help)      show_help ;;
            *)
                [ -n "$NEW_PATH" ] && fail "only one target name/path allowed"
                NEW_PATH="$1"
                shift
                ;;
        esac
    done

    [ -z "$NEW_PATH" ] && show_help

    if [ -n "$CREATOR_CODE" ] && [ ${#CREATOR_CODE} -ne 4 ]; then
        fail "Creator code must be exactly 4 characters"
    fi
}

# ──────────────────────────────────────────────────────────────
# Prepare paths & names
# ──────────────────────────────────────────────────────────────

prepare_paths() {
    if [ -z "$BASE_APP" ]; then
        local script_dir="$(/usr/bin/dirname "$(/bin/realpath "$0")")"
        BASE_APP="${script_dir}/OMCApplet.app"
    fi

    if [ ! -d "$BASE_APP" ]; then
        fail "base applet not found: $BASE_APP"
    fi

    # Detect original executable name
    local base_info="$BASE_APP/Contents/Info.plist"
    if [ ! -f "$base_info" ]; then
        fail "No Info.plist in base app"
    fi

    ORIGINAL_NAME=$(/usr/bin/plutil -extract CFBundleExecutable raw "$base_info" 2>/dev/null)
    if [ -z "$ORIGINAL_NAME" ]; then
        ORIGINAL_NAME=$(/usr/bin/basename "${BASE_APP%.app}")
        echo "Warning: Using folder-derived name: $ORIGINAL_NAME" >&2
    fi

    if [[ ! "$NEW_PATH" =~ \.app$ ]]; then
        NEW_PATH="${NEW_PATH}.app"
    fi
    if [[ "$NEW_PATH" != /* ]]; then
        NEW_PATH="$(/bin/pwd)/$NEW_PATH"
    fi

    NEW_APPLET_NAME="$(/usr/bin/basename "${NEW_PATH%.app}")"

    if [ -e "$NEW_PATH" ]; then
        fail "destination already exists: $NEW_PATH"
    fi
}

# ──────────────────────────────────────────────────────────────
# Copy base -> remove signature & quarantine
# ──────────────────────────────────────────────────────────────

copy_and_clean() {
    log "Copying base applet to $NEW_PATH"
    /bin/cp -Rp "$BASE_APP" "$NEW_PATH"

    if [ -d "$NEW_PATH/Contents/_CodeSignature" ]; then
        log "Removing embedded code signature"
        /bin/rm -rf "$NEW_PATH/Contents/_CodeSignature"
    fi

    log "Removing quarantine xattr"
    /usr/bin/xattr -dr com.apple.quarantine "$NEW_PATH" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────
# Compile and install new icon (if provided)
# ──────────────────────────────────────────────────────────────

handle_icon() {
    if [ -z "$ICON_SOURCE" ]; then
        return 0
    fi

    if [ ! -e "$ICON_SOURCE" ]; then
        echo "Warning: Icon file not found: $ICON_SOURCE" >&2
        return 0
    fi

    # Use basename of the icon file (without .icon)
    local icon_base=$(/usr/bin/basename "${ICON_SOURCE%.*}")

    local resources_dir="$NEW_PATH/Contents/Resources"
    local temp_dir=$(/usr/bin/mktemp -d)
    if [ $? -ne 0 ]; then
        echo "Warning: Cannot create temporary directory for actool" >&2
        return 0
    fi

    local log_file="$temp_dir/actool.log"

    log "Compiling icon $ICON_SOURCE -> Assets.car (log: $log_file)"

    /usr/bin/xcrun actool "$ICON_SOURCE" \
        --compile "$temp_dir" \
        --app-icon "$icon_base" \
        --platform macosx \
        --target-device mac \
        --output-format human-readable-text \
        --minimum-deployment-target 11.0 \
        --output-partial-info-plist "$temp_dir/partial.plist" \
        > "$log_file" 2>&1

    local actool_status=$?
    if [ $actool_status -ne 0 ]; then
        echo "actool failed (status $actool_status)" >&2
        echo "Last lines of log:" >&2
        tail -n 10 "$log_file" >&2 2>/dev/null
    else
        log "actool finished successfully"
    fi

    local install_success=0
    if [ -f "$temp_dir/Assets.car" ]; then
        log "Installing Assets.car"
        /bin/cp "$temp_dir/Assets.car" "$resources_dir/Assets.car"
        install_success=1
    else
        log "No Assets.car produced"
    fi

    if [ -f "$temp_dir/$icon_base.icns" ]; then
        log "Installing generated .icns as $icon_base.icns"
        /bin/cp "$temp_dir/$icon_base.icns" "$resources_dir/$icon_base.icns"
        install_success=1
    fi

    # Update Info.plist to match the icon name actool expects
    local plist="$NEW_PATH/Contents/Info.plist"
    if [ -f "$plist" ]; then
        /usr/bin/plutil -replace CFBundleIconFile -string "$icon_base" "$plist" 2>/dev/null
        /usr/bin/plutil -replace CFBundleIconName -string "$icon_base" "$plist" 2>/dev/null
        log "Updated CFBundleIconFile and CFBundleIconName to $icon_base"
    fi

    # Keep log on failure, clean up on success
    if [ $actool_status -ne 0 ]; then
        echo "Log preserved at: $log_file" >&2
    else
        /bin/rm -rf "$temp_dir"
    fi

    if [ $install_success -eq 1 ]; then
        NEW_ICON_INSTALLED=1
        # Delete original icns
        if [ "${icon_base}" != "${ORIGINAL_NAME}" ]; then
        	log "Removing $resources_dir/$ORIGINAL_NAME.icns"
            /bin/rm -f "$resources_dir/$ORIGINAL_NAME.icns"
        fi
        if [ "${icon_base}" != "${NEW_APPLET_NAME}" ]; then
        	log "Removing $resources_dir/$NEW_APPLET_NAME.icns"
	        /bin/rm -f "$resources_dir/$NEW_APPLET_NAME.icns"
	    fi
    fi
}

# ──────────────────────────────────────────────────────────────
# Rename executable & legacy icon (if present)
# ──────────────────────────────────────────────────────────────

rename_core_files() {
    log "Renaming executable: $ORIGINAL_NAME -> $NEW_APPLET_NAME"
    /bin/mv "$NEW_PATH/Contents/MacOS/$ORIGINAL_NAME" "$NEW_PATH/Contents/MacOS/$NEW_APPLET_NAME" 2>/dev/null

    if [ $NEW_ICON_INSTALLED -eq 1 ]; then
        log "Skipping legacy icon rename (new icon installed)"
        return 0
    fi

    local old_icns="$NEW_PATH/Contents/Resources/$ORIGINAL_NAME.icns"
    if [ -f "$old_icns" ]; then
        log "Renaming legacy icon: $ORIGINAL_NAME.icns -> $NEW_APPLET_NAME.icns"
        /bin/mv "$old_icns" "$NEW_PATH/Contents/Resources/$NEW_APPLET_NAME.icns" 2>/dev/null
    fi
}

# ──────────────────────────────────────────────────────────────
# Update creator code (PkgInfo + CFBundleSignature)
# ──────────────────────────────────────────────────────────────

update_creator_code() {
    if [ -z "$CREATOR_CODE" ]; then
        return 0
    fi

    local pkginfo="$NEW_PATH/Contents/PkgInfo"
    local plist="$NEW_PATH/Contents/Info.plist"

    if [ -f "$pkginfo" ]; then
        log "Updating creator code in PkgInfo -> $CREATOR_CODE"
        printf 'APPL%s' "$CREATOR_CODE" > "$pkginfo"
    fi

    if [ -f "$plist" ]; then
        log "Updating CFBundleSignature -> $CREATOR_CODE"
        /usr/bin/plutil -replace CFBundleSignature -string "$CREATOR_CODE" "$plist" 2>/dev/null
    fi
}

# ──────────────────────────────────────────────────────────────
# Update bundle identifier
# ──────────────────────────────────────────────────────────────

update_bundle_id() {
    local plist="$NEW_PATH/Contents/Info.plist"
    if [ ! -f "$plist" ]; then
        return 0
    fi

    local new_id
    if [ -n "$BUNDLE_ID" ]; then
        new_id="$BUNDLE_ID"
    else
        new_id="com.abracode.$NEW_APPLET_NAME"
    fi

    log "Setting CFBundleIdentifier -> $new_id"
    /usr/bin/plutil -replace CFBundleIdentifier -string "$new_id" "$plist" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────
# Update Info.plist keys
# ──────────────────────────────────────────────────────────────

update_info_plist() {
    local plist="$NEW_PATH/Contents/Info.plist"

    /usr/bin/plutil -replace CFBundleExecutable           -string "$NEW_APPLET_NAME" "$plist" 2>/dev/null
    /usr/bin/plutil -replace CFBundleName                 -string "$NEW_APPLET_NAME" "$plist" 2>/dev/null

    if [ $NEW_ICON_INSTALLED -eq 0 ]; then
        /usr/bin/plutil -replace CFBundleIconFile             -string "$NEW_APPLET_NAME" "$plist" 2>/dev/null
        /usr/bin/plutil -replace CFBundleIconName             -string "$NEW_APPLET_NAME" "$plist" 2>/dev/null
    fi

    /usr/bin/plutil -replace NSAppleEventsUsageDescription -string "$NEW_APPLET_NAME sends AppleEvents to other apps to provide functionality unique to this applet." "$plist" 2>/dev/null

    log "Updated Info.plist keys"
}

# ──────────────────────────────────────────────────────────────
# Recompile MainMenu.nib (if exists)
# ──────────────────────────────────────────────────────────────

recompile_nib() {
    local nib_dir="$NEW_PATH/Contents/Resources/Base.lproj/MainMenu.nib"
    local designable="$nib_dir/designable.nib"

    if [ ! -f "$designable" ]; then
        log "No designable.nib found — skipping nib update"
        return 0
    fi

    log "Replacing '$ORIGINAL_NAME' -> '$NEW_APPLET_NAME' in designable.nib"
    /usr/bin/sed -i '' "s/$ORIGINAL_NAME/$NEW_APPLET_NAME/g" "$designable"

    local temp_nib="$NEW_PATH/Contents/Resources/Base.lproj/temp.nib"

    log "Recompiling nib -> $temp_nib"
    /usr/bin/xcrun ibtool --compile "$temp_nib" --flatten NO "$nib_dir"

    log "Replacing original nib bundle"
    /bin/rm -rf "$nib_dir"
    /bin/mv "$temp_nib" "$nib_dir"
}

# ──────────────────────────────────────────────────────────────
# Final bundle refresh & registration
# ──────────────────────────────────────────────────────────────

finalize_bundle() {
    log "Refreshing bundle modification date"
    /usr/bin/touch -c "$NEW_PATH"

    log "Registering applet with Launch Services"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -f -R -trusted "$NEW_PATH" 2>/dev/null
}

# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    prepare_paths

    if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
        fail "Xcode command line tools not found. Run: xcode-select --install"
    fi

    copy_and_clean
    handle_icon
    rename_core_files
    update_creator_code
    update_bundle_id
    update_info_plist
    recompile_nib
    finalize_bundle

    echo "Created: $NEW_PATH"
    echo "Applet name: $NEW_APPLET_NAME (base: $ORIGINAL_NAME)"
    echo ""
    echo "Next step: sign the applet"
    echo "    ./codesign_applet.sh \"$NEW_PATH\""
    echo ""
}

main "$@"
