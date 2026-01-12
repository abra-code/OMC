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

entitlements_path="$self_dir/OMCApplet/OMCApplet.entitlements"
entitlements=""

if test -z "$identity"; then
    identity="-"
    timestamp="--timestamp=none"
    sign_options=""
else
	if [ -f "${entitlements_path}" ]; then
    	entitlements="--entitlements $entitlements_path"
    fi
    timestamp="--timestamp"
    sign_options="--options runtime"
fi

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

echo ""
echo "Verifying and validating codesigned app:"
echo "-----------------------------------------"
/usr/bin/codesign --verify --display --verbose=4 "$app_to_sign"

if test "$?" = "0"; then
    echo "-----------------------------------------"
    echo "✓ App signature is valid"
else
    echo "-----------------------------------------"
    echo "✗ App signature validation failed"
    exit 1
fi
