#!/bin/sh

brief="no"
if [ "$1" = "--brief" ]; then
    brief="yes"
    shift
fi

# Print only in default (non-brief) mode. Used for banners, dividers, blank-line
# spacers, and per-file progress that brief mode collapses into summaries.
verbose_echo() {
    if [ "$brief" != "yes" ]; then
        echo "$@"
    fi
}

# codesign is silent on success without --verbose (errors still go to stderr);
# brief mode drops --verbose from the signing invocations.
cs_verbose="--verbose"
if [ "$brief" = "yes" ]; then
    cs_verbose=""
fi

# Run codesign; in brief mode filter its routine "replacing existing
# signature" notes from the output while preserving the exit status.
run_codesign() {
    if [ "$brief" = "yes" ]; then
        local cs_out cs_rc
        cs_out=$(/usr/bin/codesign "$@" 2>&1)
        cs_rc=$?
        cs_out=$(printf '%s\n' "$cs_out" | /usr/bin/grep -v ': replacing existing signature$')
        if [ -n "$cs_out" ]; then
            echo "$cs_out"
        fi
        return $cs_rc
    fi
    /usr/bin/codesign "$@"
}

self_dir=$(/usr/bin/dirname "$0")
app_to_sign="$1"
identity="$2"
entitlements_override="$3"

if test -z "$app_to_sign"; then
    echo "Usage: $0 [--brief] <path/to/app> [identity] [entitlements_file]"
    echo ""
    echo "Deep-signs the bundle regardless of its layout, replacing the deprecated"
    echo "'codesign --deep'. It signs every standalone Mach-O executable and library"
    echo "individually (wherever they live), then every nested code bundle"
    echo "(app/appex/framework/xpc/plugin/bundle/kext/qlgenerator/mdimporter) as a"
    echo "bundle, deepest-first, and finally the app bundle itself."
    echo ""
    echo "Arguments:"
    echo "  --brief            (optional) Print a compact summary instead of full output"
    echo "  path/to/app        Path to the .app bundle to codesign"
    echo "  identity           (optional) Signing identity. Use '-' for ad-hoc signing"
    echo "  entitlements_file  (optional) Entitlements plist, overriding auto-discovery"
    echo ""
    echo "Examples:"
    echo "  $0 MyApp.app"
    echo "  $0 MyApp.app 'TEAMID123'"
    echo "  $0 --brief MyApp.app 'TEAMID123' MyApp.entitlements"
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

verbose_echo "Removing quarantine xattr"
/usr/bin/xattr -dr 'com.apple.quarantine' "$app_to_sign" 2>/dev/null

app_dir=$(/usr/bin/dirname "$app_to_sign")

# Look for entitlements:
# 1. OMCApplet.entitlements next to the applet being signed
# 2. First *.entitlements file next to the applet
# 3. Default fallback in directory next to this script
entitlements_file=""
if [ -n "$entitlements_override" ] && [ -f "$entitlements_override" ]; then
    entitlements_file="$entitlements_override"
elif [ -f "$app_dir/OMCApplet.entitlements" ]; then
    entitlements_file="$app_dir/OMCApplet.entitlements"
else
    first_ent=$(/bin/ls "$app_dir"/*.entitlements 2>/dev/null | /usr/bin/head -1)
    if [ -n "$first_ent" ] && [ -f "$first_ent" ]; then
        entitlements_file="$first_ent"
    elif [ -f "$self_dir/OMCApplet.entitlements" ]; then
        entitlements_file="$self_dir/OMCApplet.entitlements"
    fi
fi

entitlements=""

is_developer_id="no"

if test -z "$identity" || test "$identity" = "-"; then
    identity="-"
    timestamp="--timestamp=none"
    sign_options=""
else
    if [ -n "$entitlements_file" ]; then
        echo "Using entitlements: $entitlements_file"
        entitlements="--entitlements $entitlements_file"
    fi

    # Check if this is an Apple-issued Developer ID certificate by resolving the
    # identity (team ID, fingerprint, or full name) to its certificate name in
    # the keychain, then checking for "Developer ID" in the result.
    full_cert_name=$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/grep "$identity" | /usr/bin/sed 's/.*"\(.*\)".*/\1/' | /usr/bin/head -1)
    developer_id_check=$(echo "$full_cert_name" | /usr/bin/grep "Developer ID")
    if test -n "$developer_id_check"; then
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
    verbose_echo "Refreshing bundle modification date"
    /usr/bin/touch -c "${app_path}"

    verbose_echo "Registering applet with Launch Services"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -f -R -trusted "${app_path}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Generic deep signing (layout-independent replacement for `codesign --deep`).
#
# Two passes, bottom-up:
#   Phase 1: sign every loose Mach-O file anywhere in the bundle, individually.
#   Phase 2: sign every nested code bundle as a bundle, deepest-first, so a
#            child is always sealed before the parent that contains it.
#   Phase 3: sign the outer app bundle itself.
# ---------------------------------------------------------------------------

# ---- Phase 1: sign all loose Mach-O files --------------------------------
#
# Candidate files: regular files (never symlinks) anywhere under the app,
# excluding anything already inside a _CodeSignature seal directory. The
# executable bit alone is not sufficient: many dynamic libraries and plugins
# (*.dylib, *.so, *.node) ship without it yet still contain Mach-O code that the
# notary service will flag if left unsigned - so we match those extensions too.
verbose_echo ""
verbose_echo "Signing standalone Mach-O executables and libraries"
verbose_echo "-----------------------------------"

# Filter the candidate list down to actual Mach-O files. Executable *scripts*
# are intentionally NOT signed: the notary service only inspects Mach-O code,
# and a script's signature is stored in an extended attribute that is shed by
# ordinary transport (zip, ditto, network copy), so signing them adds no
# notarization value and cannot survive delivery anyway. Compute the filtered
# list first so brief mode can report an accurate count before signing.
macho_files=$(/usr/bin/find "$app_to_sign" -type f \( -perm +111 -o -name "*.dylib" -o -name "*.so" -o -name "*.node" \) ! -path "*/_CodeSignature/*" -print | /usr/bin/sort | while IFS= read -r f; do
    if /usr/bin/file -b "$f" | /usr/bin/grep -q "Mach-O"; then
        printf '%s\n' "$f"
    fi
done)

if [ -z "$macho_files" ]; then
    macho_count=0
else
    macho_count=$(printf '%s\n' "$macho_files" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
fi

# Brief mode collapses the per-file log into a single summary line reporting the
# number of files that will actually be signed (the filtered Mach-O list).
if [ "$brief" = "yes" ]; then
    echo "Signing $macho_count Mach-O executables and libraries"
fi

# This pass may include each nested bundle's main executable; that is harmless
# by design - phase 2 re-signs those bundles and rewrites the seal, and an
# executable being signed twice costs nothing but a moment.
if [ -n "$macho_files" ]; then
    printf '%s\n' "$macho_files" | while IFS= read -r f; do
        verbose_echo "Signing: $f"
        run_codesign $cs_verbose --force $sign_options $timestamp --sign "$identity" "$f"
        if test "$?" != "0"; then
            echo "warning: failed to sign $f"
        fi
    done
fi

verbose_echo "-----------------------------------"

# ---- Phase 2: sign nested code bundles, deepest-first --------------------
#
# Discover every candidate bundle directory by recognised extension, then order
# them deepest-first (most path components first) so children are sealed before
# the parents that embed them.
verbose_echo ""
verbose_echo "Signing nested code bundles (deepest-first)"
verbose_echo "-----------------------------------"

nested_bundles=$(/usr/bin/find "$app_to_sign" -mindepth 1 -type d \( -name "*.app" -o -name "*.appex" -o -name "*.framework" -o -name "*.xpc" -o -name "*.plugin" -o -name "*.bundle" -o -name "*.kext" -o -name "*.qlgenerator" -o -name "*.mdimporter" \) -print | /usr/bin/awk -F/ '{ printf "%05d\t%s\n", NF, $0 }' | /usr/bin/sort -rn | /usr/bin/cut -f2-)

if [ -n "$nested_bundles" ]; then
    printf '%s\n' "$nested_bundles" | while IFS= read -r bundle; do
        bundle_name=$(/usr/bin/basename "$bundle")
        case "$bundle" in
            *.framework)
                # A framework is valid if it is versioned
                # (Versions/*/Resources/Info.plist) or a flat old-style bundle
                # (Resources/Info.plist directly). Detect which before signing.
                is_versioned="no"
                for verdir in "$bundle"/Versions/*; do
                    if [ -f "$verdir/Resources/Info.plist" ]; then
                        is_versioned="yes"
                        break
                    fi
                done
                if [ "$is_versioned" = "yes" ]; then
                    echo "Signing framework: $bundle_name"
                    # Sign each real version directory; skip symlinks such as
                    # Versions/Current, which just alias a real version.
                    for verdir in "$bundle"/Versions/*; do
                        [ -d "$verdir" ] || continue
                        if [ -L "$verdir" ]; then
                            continue
                        fi
                        run_codesign $cs_verbose --force $sign_options $timestamp --sign "$identity" "$verdir"
                        if test "$?" != "0"; then
                            echo "warning: failed to sign $verdir"
                        fi
                    done
                elif [ -f "$bundle/Resources/Info.plist" ]; then
                    # Flat old-style framework: sign the bundle root directly.
                    echo "Signing bundle: $bundle_name"
                    run_codesign $cs_verbose --force $sign_options $timestamp --sign "$identity" "$bundle"
                    if test "$?" != "0"; then
                        echo "warning: failed to sign $bundle_name"
                    fi
                else
                    # Not a valid framework; its Mach-O contents were already
                    # signed in phase 1, so it is safe to leave the seal alone.
                    verbose_echo "Skipping invalid framework (no Info.plist): $bundle"
                fi
                ;;
            *)
                if [ -f "$bundle/Contents/Info.plist" ]; then
                    echo "Signing bundle: $bundle_name"
                    run_codesign $cs_verbose --force $sign_options $timestamp --sign "$identity" "$bundle"
                    if test "$?" != "0"; then
                        echo "warning: failed to sign $bundle_name"
                    fi
                else
                    # Missing Contents/Info.plist: not a real code bundle. Its
                    # Mach-O contents were already signed in phase 1.
                    verbose_echo "Skipping invalid bundle (no Contents/Info.plist): $bundle"
                fi
                ;;
        esac
    done
fi

verbose_echo "-----------------------------------"

verbose_echo ""

# ---- Phase 3: sign the outer app bundle ----------------------------------
# The generic phases above have already sealed all nested code, so the outer
# bundle no longer needs (or should use) `codesign --deep`.
echo "Signing app bundle: $app_to_sign"
verbose_echo "/usr/bin/codesign $cs_verbose --force $sign_options $entitlements $timestamp --identifier $app_id --sign $identity $app_to_sign"
run_codesign $cs_verbose --force $sign_options $entitlements $timestamp --identifier "$app_id" --sign "$identity" "$app_to_sign"

if test "$?" != "0"; then
    verbose_echo ""
    echo "error: failed to sign app bundle"
    exit 1
fi

refresh_app "$app_to_sign"

verbose_echo ""
verbose_echo "Verifying codesigned app:"
verbose_echo "-----------------------------------------"
# --deep --strict makes the local verification approximate what the notary
# service checks: it walks every nested seal and rejects loose or invalid code.
if [ "$brief" = "yes" ]; then
    /usr/bin/codesign --verify --deep --strict "$app_to_sign" 2>&1
else
    /usr/bin/codesign --verify --deep --strict --display --verbose=4 "$app_to_sign" 2>&1
fi

if test "$?" = "0"; then
    verbose_echo "-----------------------------------------"
    echo "✓ Code signature is valid (integrity check passed)"
else
    verbose_echo "-----------------------------------------"
    echo "✗ Code signature validation failed"
    exit 1
fi

verbose_echo ""
verbose_echo "Gatekeeper assessment:"
verbose_echo "-----------------------------------------"
spctl_output=$(/usr/sbin/spctl --assess --verbose=4 --type execute "$app_to_sign" 2>&1)
spctl_status=$?

# In default mode always show the raw assessment; in brief mode only when it did
# not pass (errors/rejections are worth surfacing).
if [ "$brief" != "yes" ] || test "$spctl_status" != "0"; then
    echo "$spctl_output"
fi
verbose_echo "-----------------------------------------"

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
