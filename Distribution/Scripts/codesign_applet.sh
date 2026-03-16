#!/bin/sh

self_dir=$(/usr/bin/dirname "$0")
app_to_sign="$1"
identity="$2"

if test -z "$app_to_sign"; then
    echo "Usage: $0 <path/to/app> [identity]"
    echo ""
    echo "Arguments:"
    echo "  path/to/app  Path to the .app bundle to codesign"
    echo "  identity     (optional) Signing identity. Use '-' for ad-hoc signing"
    echo ""
    echo "Examples:"
    echo "  $0 MyApp.app"
    echo "  $0 MyApp.app 'TEAMID123'"
    echo ""
    exit 1
fi

# full path
app_to_sign=$(/bin/realpath "$app_to_sign")
app_id=$(/usr/bin/defaults read "$app_to_sign/Contents/Info.plist" CFBundleIdentifier)
if test "$?" != "0"; then
    echo "error: could not obtain bundle identifier for app at: $app_to_sign"
    exit 1
fi

echo "Removing quarantine xattr"
/usr/bin/xattr -dr 'com.apple.quarantine' "$app_to_sign" 2>/dev/null

entitlements_path="$self_dir/OMCApplet/OMCApplet.entitlements"
entitlements_path_root="$self_dir/OMCApplet.entitlements"

entitlements=""

is_developer_id="no"

if test -z "$identity" || test "$identity" = "-"; then
    identity="-"
    timestamp="--timestamp=none"
    sign_options=""
else
    if [ -f "${entitlements_path}" ]; then
        entitlements="--entitlements $entitlements_path"
    elif [ -f "${entitlements_path_root}" ]; then
        entitlements="--entitlements $entitlements_path_root"
    fi

    # Check if this is an Apple-issued Developer ID certificate
    # Developer ID certs have an anchor in Apple's CA chain
    if echo "$identity" | /usr/bin/grep -q "Developer ID"; then
        is_developer_id="yes"
        timestamp="--timestamp"
        sign_options="--options runtime"
    else
        # Self-signed or other non-Apple certs:
        # - No timestamp server (Apple's TSA won't service non-Apple certs)
        # - No hardened runtime (requires Gatekeeper trust)
        echo ""
        echo "NOTE: \"$identity\" does not appear to be an Apple Developer ID certificate."
        echo "The signed app will not pass Gatekeeper and may not launch without"
        echo "manual approval (right-click > Open, or System Settings > Privacy)."
        echo ""
        timestamp="--timestamp=none"
        sign_options=""
    fi
fi

refresh_app() {
    local app_path=$1
    echo "Refreshing bundle modification date"
    /usr/bin/touch -c "${app_path}"

    echo "Registering applet with Launch Services"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -f -R -trusted "${app_path}" 2>/dev/null
}

# Function to sign all executables in a directory recursively
sign_executables_in_dir() {
    local dir="$1"
    
    if test ! -d "$dir"; then
        return
    fi
    
    echo ""
    echo "Searching for executables in: $dir"
    echo "-----------------------------------"
    
    # Find all executable files (excluding symlinks to avoid double-signing)
    local exec_files=$(/usr/bin/find "$dir" -type f -perm +111 -print | /usr/bin/sort)
    
    if test -z "$exec_files"; then
        echo "No executables found"
        echo "-----------------------------------"
        return
    fi
    
    # Iterate over found files
    echo "$exec_files" | while IFS= read -r exec_file; do
        # Skip if it's not a Mach-O binary or executable script
        file_type=$(/usr/bin/file -b "$exec_file")
        echo "$file_type" | /usr/bin/grep -qE "(Mach-O|executable|script)"
        
        if test "$?" = "0"; then
            echo "Signing: $exec_file"
            /usr/bin/codesign --verbose --force $sign_options $timestamp --sign "$identity" "$exec_file"
            
            if test "$?" != "0"; then
                echo "warning: failed to sign $exec_file"
            fi
        fi
    done
    
    echo "-----------------------------------"
}

# Sign executables in Contents/Helpers if it exists
if test -d "$app_to_sign/Contents/Helpers"; then
    sign_executables_in_dir "$app_to_sign/Contents/Helpers"
fi

# Sign executables in Contents/Library if it exists
if test -d "$app_to_sign/Contents/Library"; then
    sign_executables_in_dir "$app_to_sign/Contents/Library"
fi

# Sign executables in Contents/Support if it exists
if test -d "$app_to_sign/Contents/Support"; then
    sign_executables_in_dir "$app_to_sign/Contents/Support"
fi

# Sign frameworks in Contents/Frameworks
if test -d "$app_to_sign/Contents/Frameworks"; then
    # Sign executables inside each framework first (e.g. Support tools)
    for fw in "$app_to_sign/Contents/Frameworks"/*.framework; do
        test -d "$fw" || continue
        sign_executables_in_dir "$fw/Versions/Current/Support"
    done

    echo ""
    echo "Signing frameworks in: $app_to_sign/Contents/Frameworks"
    echo "-----------------------------------"
    for fw in "$app_to_sign/Contents/Frameworks"/*.framework; do
        test -d "$fw" || continue
        fw_name=$(/usr/bin/basename "$fw")
        echo "Signing framework: $fw_name"
        /usr/bin/codesign --verbose --force $sign_options $timestamp --sign "$identity" "$fw"
        if test "$?" != "0"; then
            echo "warning: failed to sign $fw_name"
        fi
    done
    echo "-----------------------------------"
fi

echo ""

# Finally sign the app bundle itself
echo "Signing app bundle: $app_to_sign"
echo "/usr/bin/codesign --deep --verbose --force $sign_options $entitlements $timestamp --identifier $app_id --sign $identity $app_to_sign"
/usr/bin/codesign --deep --verbose --force $sign_options $entitlements $timestamp --identifier "$app_id" --sign "$identity" "$app_to_sign"

if test "$?" != "0"; then
    echo ""
    echo "error: failed to sign app bundle"
    exit 1
fi

refresh_app "$app_to_sign"

echo ""
echo "Verifying codesigned app:"
echo "-----------------------------------------"
/usr/bin/codesign --verify --display --verbose=4 "$app_to_sign" 2>&1

if test "$?" = "0"; then
    echo "-----------------------------------------"
    echo "✓ Code signature is valid (integrity check passed)"
else
    echo "-----------------------------------------"
    echo "✗ Code signature validation failed"
    exit 1
fi

echo ""
echo "Gatekeeper assessment:"
echo "-----------------------------------------"
spctl_output=$(/usr/sbin/spctl --assess --verbose=4 --type execute "$app_to_sign" 2>&1)
spctl_status=$?

echo "$spctl_output"
echo "-----------------------------------------"

if test "$spctl_status" = "0"; then
    echo "✓ App is accepted by Gatekeeper"
elif test "$identity" = "-"; then
    echo "⚠ Ad-hoc signed apps are not accepted by Gatekeeper (expected)"
    echo "  The app will run on this Mac"
elif test "$is_developer_id" = "yes"; then
    # Check if it's just a notarization issue
    if echo "$spctl_output" | /usr/bin/grep -qi "unnotarized"; then
        echo "⚠ App is signed with Developer ID but not notarized"
        echo "  The app will run on this Mac. For distribution, notarize with:"
        echo "  xcrun notarytool submit <path> --apple-id <ID> --team-id <TEAM>"
    else
        echo "✗ App is rejected by Gatekeeper (unexpected for Developer ID)"
        echo "  Check that the certificate is valid and not expired"
        exit 1
    fi
else
    echo "⚠ App is rejected by Gatekeeper (self-signed certificate)"
    echo "  To launch: right-click the app > Open, or allow it in"
    echo "  System Settings > Privacy & Security"
fi
