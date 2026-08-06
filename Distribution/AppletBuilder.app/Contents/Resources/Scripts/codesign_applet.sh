#!/bin/sh

brief="no"
entitlements_search="yes"
list_code="no"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --brief)
            brief="yes"
            shift
            ;;
        --list-code)
            # Print every path this script would sign, one per line, and exit
            # without touching anything. Lets a caller check the same set.
            list_code="yes"
            shift
            ;;
        --no-entitlements-search)
            # The caller decides the entitlements and passes them explicitly.
            # Without this, a bundle signed from an arbitrary folder can pick up
            # a stray .entitlements file the user never saw. See the discovery
            # block below.
            entitlements_search="no"
            shift
            ;;
        *)
            break
            ;;
    esac
done

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
        # codesign_output is declared apart from its assignment on purpose, and
        # is the only place in this script that is: `local out=$(cmd)` runs the
        # substitution as part of `local`, so the next $? reads local's own
        # status - always 0 - and every signing failure would be swallowed.
        # Nothing may run between the assignment and the $? read, not even
        # another `local` that substitutes.
        local codesign_output
        codesign_output=$(/usr/bin/codesign "$@" 2>&1)
        local codesign_status=$?
        codesign_output=$(printf '%s\n' "$codesign_output" | /usr/bin/grep -v ': replacing existing signature$')
        if [ -n "$codesign_output" ]; then
            echo "$codesign_output"
        fi
        return $codesign_status
    fi
    /usr/bin/codesign "$@"
}

self_dir=$(/usr/bin/dirname "$0")
app_to_sign="$1"
identity="$2"
entitlements_override="$3"

if test -z "$app_to_sign"; then
    echo "Usage: $0 [--brief] [--no-entitlements-search] <path/to/app> [identity] [entitlements_file]"
    echo ""
    echo "Deep-signs the bundle regardless of its layout, replacing the deprecated"
    echo "'codesign --deep'. It signs every standalone Mach-O executable and library"
    echo "individually (wherever they live), then every nested code bundle"
    echo "(app/appex/framework/xpc/plugin/bundle/kext/qlgenerator/mdimporter) as a"
    echo "bundle, deepest-first, and finally the app bundle itself."
    echo ""
    echo "Arguments:"
    echo "  --brief            (optional) Print a compact summary instead of full output"
    echo "  --no-entitlements-search  (optional) Use only the entitlements_file argument;"
    echo "                     never look for a .entitlements file next to the bundle"
    echo "  --list-code        (optional) Print every path that would be signed and exit"
    echo "                     without modifying anything"
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
app_to_sign_arg="$app_to_sign"
app_to_sign=$(/bin/realpath "$app_to_sign" 2>/dev/null)
if [ -z "$app_to_sign" ] || [ ! -d "$app_to_sign" ]; then
    # stderr, not stdout: --list-code's caller redirects stdout to a file and
    # parses it as paths, so an error line there is read back as a bundle item.
    printf 'error: not a bundle directory: %s\n' "$app_to_sign_arg" >&2
    exit 1
fi

# The discovery passes, as functions so that everything which needs to know what
# this script would sign - the signing phases below and --list-code - agrees by
# construction. A caller that decides whether signing can be skipped has to
# inspect exactly this set; anything narrower would pass over code this script
# would have fixed.

# Every loose Mach-O anywhere in the bundle. The executable bit alone is not
# sufficient: many dynamic libraries and plugins (*.dylib, *.so, *.node) ship
# without it yet still contain Mach-O code that the notary service will flag if
# left unsigned. Executable *scripts* are filtered out - the notary service only
# inspects Mach-O, and a script's signature lives in an extended attribute that
# ordinary transport (zip, ditto, network copy) sheds anyway.
list_macho_files() {
    # A loop variable needs declaring as much as any other: `read` and `for`
    # assign at global scope otherwise, where they can clobber a caller's
    # variable of the same name. True even here, where the loop body runs in a
    # pipeline subshell - the subshell inherits the globals it would shadow.
    local file_path
    /usr/bin/find "$app_to_sign" -type f \( -perm +111 -o -name "*.dylib" -o -name "*.so" -o -name "*.node" \) ! -path "*/_CodeSignature/*" -print \
        | /usr/bin/sort \
        | while IFS= read -r file_path; do
            if /usr/bin/file -b "$file_path" | /usr/bin/grep -q "Mach-O"; then
                printf '%s\n' "$file_path"
            fi
        done
}

# Whether a seal-relative path sits in nested-code territory, i.e. matches one of
# the two rules a sealed rules2 marks "nested" at weight 10. Used both to
# classify loose files and to decide where one seal ends and another begins.
# Arguments: seal-relative path
_is_nested_code_path() {
    local seal_path="$1"
    case "$seal_path" in
        */*)
            case "$seal_path" in
                Frameworks/*|SharedFrameworks/*|PlugIns/*|Plug-ins/*|XPCServices/*|Helpers/*|MacOS/*|Library/Automator/*|Library/Spotlight/*|Library/LoginItems/*) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        # Directly at the seal's resource root: the "^[^/]+$" rule.
        *) return 0 ;;
    esac
}

# Whether a directory starts a seal of its own, which decides where the rules
# stop applying on behalf of the enclosing bundle and start applying on behalf of
# this one. Two conditions, both necessary:
#
#   1. It is structurally a bundle. Extension is not the test - codesign goes by
#      structure, and BBEdit's *.bblm language modules are sealed bundles under
#      an extension no list would guess.
#   2. Its enclosing seal treats it as nested code, or it already carries a seal
#      of its own. A bundle in plain-resource territory is NOT nested code: a
#      SwiftPM resource bundle under Contents/Resources (Foo_Foo.bundle, an
#      Info.plist and a PrivacyInfo.xcprivacy) is recorded by the enclosing seal
#      as ordinary per-file hashes, needs no signature, and ships unsigned inside
#      plenty of notarized apps. Demanding a certificate from one reports a
#      healthy app as broken.
#
# Arguments: on-disk path, path relative to the enclosing seal
_is_seal_owner() {
    local bundle_path="$1"
    local seal_path="$2"
    _is_nested_code_path "$seal_path" && return 0
    [ -d "$bundle_path/Contents/_CodeSignature" ] && return 0
    [ -d "$bundle_path/_CodeSignature" ] && return 0
    # A versioned framework keeps its seal one level down, per version. Missing
    # this location would drop an already-signed framework in plain-resource
    # territory out of discovery: the Mach-O pass would re-sign its library and
    # nothing would reseal the framework, leaving "nested code is modified or
    # invalid" behind an outer seal that still verifies.
    local version_seal
    for version_seal in "$bundle_path"/Versions/*/_CodeSignature; do
        [ -d "$version_seal" ] && return 0
    done
    return 1
}

# Reduce a bundle-relative path to a path relative to the resource root of the
# INNERMOST seal that contains it.
#
# codesign seals every nested bundle separately, and each seal applies the same
# rules to its own contents. A file inside a nested bundle is therefore
# classified by THAT bundle's rules, not the outer app's:
# Sub.app/Contents/Helpers/LICENSE.txt is nested code of Sub.app exactly as
# Contents/Helpers/LICENSE.txt is nested code of the app. Treating the interior
# of a nested bundle as out of scope would leave the same defect one level down,
# where its own seal accepts a stale ad-hoc signature just as happily.
#
# Prints the empty string for a path no seal covers.
# Arguments: path relative to the outer bundle
_seal_relative_path() {
    local bundle_relative_path="$1"
    # An app-style bundle roots its resources at Contents/; anything beside it is
    # not sealed as a resource at all.
    local seal_path
    case "$bundle_relative_path" in
        Contents/*) seal_path="${bundle_relative_path#Contents/}" ;;
        *) return 0 ;;
    esac

    # absolute_path tracks on disk whatever remaining_path has consumed, so the
    # Info.plist probes below ask about the directory actually being crossed.
    local absolute_path="$app_to_sign/Contents"
    local remaining_path="$seal_path"
    local consumed_prefix=""
    local component rest_of_path version_name component_seal_path crossed_boundary
    while : ; do
        case "$remaining_path" in
            */*) component="${remaining_path%%/*}"; rest_of_path="${remaining_path#*/}" ;;
            *) break ;;
        esac
        absolute_path="$absolute_path/$component"
        component_seal_path="$consumed_prefix$component"
        crossed_boundary="no"
        # A versioned framework roots each version's resources at Versions/<v>/
        # and is sealed one version at a time.
        case "$rest_of_path" in
            Versions/*/*)
                version_name="${rest_of_path#Versions/}"
                version_name="${version_name%%/*}"
                if [ -f "$absolute_path/Versions/$version_name/Resources/Info.plist" ] && _is_seal_owner "$absolute_path" "$component_seal_path"; then
                    rest_of_path="${rest_of_path#"Versions/$version_name/"}"
                    absolute_path="$absolute_path/Versions/$version_name"
                    seal_path="$rest_of_path"
                    crossed_boundary="yes"
                fi
                ;;
        esac
        if [ "$crossed_boundary" = "no" ] && [ -f "$absolute_path/Contents/Info.plist" ] && _is_seal_owner "$absolute_path" "$component_seal_path"; then
            case "$rest_of_path" in
                Contents/*)
                    rest_of_path="${rest_of_path#Contents/}"
                    absolute_path="$absolute_path/Contents"
                    seal_path="$rest_of_path"
                    ;;
                # Beside the bundle's own Contents/: no seal covers it, and
                # codesign refuses to seal such a bundle at all ("unsealed
                # contents present in the bundle root"), which phase 3 reports.
                *) seal_path="" ;;
            esac
            crossed_boundary="yes"
        fi
        if [ "$crossed_boundary" = "no" ] && [ -f "$absolute_path/Resources/Info.plist" ] && _is_seal_owner "$absolute_path" "$component_seal_path"; then
            # Flat old-style framework: resources sit at the bundle root.
            seal_path="$rest_of_path"
            crossed_boundary="yes"
        fi
        if [ "$crossed_boundary" = "yes" ]; then
            consumed_prefix=""
        else
            consumed_prefix="$component_seal_path/"
        fi
        remaining_path="$rest_of_path"
    done
    printf '%s' "$seal_path"
}

# Whether $1 is a loose non-Mach-O file that its enclosing seal treats as nested
# code, and which therefore needs a signature of its own. Factored into a
# function on purpose: bash 3.2 (macOS /bin/sh) mishandles a literal `case`
# inside $(...) command substitution, so the classification cannot live inline in
# the candidate-building substitution below.
_is_nested_loose_file() {
    local file_path="$1"
    local bundle_relative_path="${file_path#"$app_to_sign"/}"
    [ "$bundle_relative_path" = "$file_path" ] && return 1
    local seal_path="$(_seal_relative_path "$bundle_relative_path")"
    [ -n "$seal_path" ] || return 1
    # The unanchored ".*\.dSYM($|/)" rule sits at weight 11, above both nested
    # rules, so debug symbols are a plain resource wherever they sit.
    case "$seal_path" in
        *.dSYM|*.dSYM/*) return 1 ;;
    esac
    # Outside a named code dir and not at the seal's own resource root, this is a
    # plain resource sealed by content hash (Resources/, and non-standard dirs
    # such as Support/).
    _is_nested_code_path "$seal_path" || return 1
    # At the seal's resource root the "^[^/]+$" rule applies, except to the few
    # names carrying their own rule at a higher weight. Info.plist and PkgInfo
    # are omitted outright; version.plist and embedded.provisionprofile are
    # sealed as plain resources; CodeResources is the code-signature namespace
    # and holds the stapled notarization ticket, which must never be re-signed.
    # These are anchored names, so Helpers/version.plist stays nested code.
    case "$seal_path" in
        Info.plist|PkgInfo|version.plist|embedded.provisionprofile|CodeResources) return 1 ;;
    esac
    # Skip Finder droppings; skip Mach-O (the Mach-O pass signs those).
    case "$(/usr/bin/basename "$file_path")" in
        .DS_Store) return 1 ;;
    esac
    if /usr/bin/file -b "$file_path" | /usr/bin/grep -q "Mach-O"; then
        return 1
    fi
    return 0
}

# Every loose NON-Mach-O file sitting in one of codesign's nested-code locations.
#
# codesign's default resource rules mark two sets of paths as NESTED CODE rather
# than as plain resources, both at weight 10 in the sealed rules2:
#   ^(Frameworks|SharedFrameworks|PlugIns|Plug-ins|XPCServices|Helpers|MacOS|
#     Library/(Automator|Spotlight|LoginItems))/
#   ^[^/]+$          - every item directly at the seal's resource root
# Every item matching either must carry its own signature before the
# enclosing bundle can be sealed - and that includes NON-code data files (license
# and notice text, data blobs) placed beside helper tools, e.g. in Contents/Helpers.
# `codesign --deep` does not sign such files, so a bundle that ships them fails to
# seal with "code object is not signed at all / In subcomponent: <file>".
#
# Signing them with the real identity is not optional busywork. A data file left
# carrying a stale ad-hoc signature still lets the bundle seal and still passes
# the notary service (Apple only enforces Developer ID on Mach-O), but Gatekeeper
# evaluates every nested item against its policy rules, and an ad-hoc signature
# has no certificate chain to match one with. The assessment then fails with a
# bare "rejected" and syspolicyd logs "rejecting due to lack of matching active
# rule" - once per such file. See Private/Design-nested-code-signing.md.
list_nested_loose_files() {
    local file_path
    /usr/bin/find "$app_to_sign" -type f ! -path "*/_CodeSignature/*" -print \
        | /usr/bin/sort \
        | while IFS= read -r file_path; do
            if _is_nested_loose_file "$file_path"; then
                printf '%s\n' "$file_path"
            fi
        done
}

# Every directory under the bundle that codesign could take for a nested bundle.
# Unordered, possibly with duplicates - the caller dedupes and filters.
#
# Found two ways because codesign recognises a bundle two ways. By extension,
# and by layout: BBEdit's *.bblm language modules are sealed bundles under an
# extension no list would guess, and found by name alone they go unsigned, after
# which the enclosing seal fails on them with "code object is not signed at all /
# In subcomponent: <bundle>".
_find_bundle_candidates() {
    local info_plist_path
    /usr/bin/find "$app_to_sign" -mindepth 1 -type d \( -name "*.app" -o -name "*.appex" -o -name "*.framework" -o -name "*.xpc" -o -name "*.plugin" -o -name "*.bundle" -o -name "*.kext" -o -name "*.qlgenerator" -o -name "*.mdimporter" \) -print
    /usr/bin/find "$app_to_sign" -mindepth 3 -type f -name "Info.plist" -path "*/Contents/Info.plist" -print \
        | while IFS= read -r info_plist_path; do
            local bundle_path="${info_plist_path%/Contents/Info.plist}"
            [ "$bundle_path" = "$app_to_sign" ] && continue
            # A stray Contents/Contents/Info.plist would otherwise derive the
            # app's own Contents directory as a bundle root.
            [ "$bundle_path" = "$app_to_sign/Contents" ] && continue
            printf '%s\n' "$bundle_path"
        done
}

# Order paths so a child comes before any parent that embeds it, which is the
# order they have to be sealed in. Deepest means most path components: tag each
# line with its count, sort descending, drop the tag.
_order_deepest_first() {
    /usr/bin/awk -F/ '{ printf "%05d\t%s\n", NF, $0 }' \
        | /usr/bin/sort -rn \
        | /usr/bin/cut -f2-
}

# Every nested code bundle, deepest-first.
#
# Kept by location, not just by name. A bundle sitting in plain-resource
# territory is not nested code and needs no signature of its own: a SwiftPM
# resource bundle under Contents/Resources is recorded by the enclosing seal as
# ordinary per-file hashes, and shipping apps notarize with them unsigned.
# Signing one anyway would give it a seal it never had, and demanding one from it
# would report a healthy app as broken. Filtering here rather than in the two
# consumers keeps the signing phase and --list-code agreeing by construction.
list_nested_bundles() {
    local bundle_path
    _find_bundle_candidates \
        | /usr/bin/sort -u \
        | while IFS= read -r bundle_path; do
            if _is_seal_owner "$bundle_path" "$(_seal_relative_path "${bundle_path#"$app_to_sign"/}")"; then
                printf '%s\n' "$bundle_path"
            fi
        done \
        | _order_deepest_first
}

# The subset of the above that phase 3 will actually put a signature on, which
# is what a caller checking "is this already signed" has to look at. Matching on
# name alone is not the same question: phase 3 skips a directory with no
# Info.plist, and signs a versioned framework one version directory at a time
# rather than at its root.
#
# The difference is not academic. A resource-only *.bundle - an Apple privacy
# manifest, a localized strings bundle - is named like a bundle, contains no
# code, and is never signed. Demanding a signature from it can never succeed, so
# listing it would block the skip permanently for the many apps that ship one.
# The dispatch below deliberately mirrors phase 3's; the two must agree.
list_signed_bundles() {
    local bundle_path
    list_nested_bundles | while IFS= read -r bundle_path; do
        case "$bundle_path" in
            *.framework)
                local is_versioned="no"
                local version_dir
                for version_dir in "$bundle_path"/Versions/*; do
                    if [ -f "$version_dir/Resources/Info.plist" ]; then
                        is_versioned="yes"
                        break
                    fi
                done
                if [ "$is_versioned" = "yes" ]; then
                    for version_dir in "$bundle_path"/Versions/*; do
                        if [ -d "$version_dir" ] && [ ! -L "$version_dir" ]; then
                            printf '%s\n' "$version_dir"
                        fi
                    done
                elif [ -f "$bundle_path/Resources/Info.plist" ]; then
                    printf '%s\n' "$bundle_path"
                fi
                ;;
            *)
                if [ -f "$bundle_path/Contents/Info.plist" ]; then
                    printf '%s\n' "$bundle_path"
                fi
                ;;
        esac
    done
}

# Read-only query, handled before anything with a side effect: no quarantine
# strip, no Info.plist requirement, no signing.
if [ "$list_code" = "yes" ]; then
    list_nested_loose_files
    list_macho_files
    list_signed_bundles
    exit 0
fi

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
#
# Steps 2 and 3 are guesses about a bundle whose folder we do not control, so
# --no-entitlements-search turns them off and makes the explicit argument the
# only source. Callers that sign arbitrary bundles should pass it: re-signing
# drops whatever entitlements the bundle already carried, and picking up an
# unrelated neighbouring file is worse than dropping them.
entitlements_file=""
if [ "$entitlements_search" = "no" ]; then
    if [ -n "$entitlements_override" ]; then
        if [ ! -f "$entitlements_override" ]; then
            echo "error: entitlements file not found: $entitlements_override"
            exit 1
        fi
        entitlements_file="$entitlements_override"
    fi
elif [ -n "$entitlements_override" ] && [ -f "$entitlements_override" ]; then
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

is_developer_id="no"

if test -z "$identity" || test "$identity" = "-"; then
    identity="-"
    timestamp="--timestamp=none"
    sign_options=""
    # Ad-hoc signing has never applied entitlements to anything, discovered or
    # otherwise. The invariant used to be implicit - the --entitlements flag was
    # only ever assembled inside the else branch below - so clear the file here
    # to keep it true now that the flag is built at the call site. The nested
    # entitlements cache is skipped for the same reason, so ad-hoc runs stay
    # byte-for-byte equivalent to what this script has always done.
    entitlements_file=""
else
    if [ -n "$entitlements_file" ]; then
        echo "Using entitlements: $entitlements_file"
    elif [ "$entitlements_search" = "no" ]; then
        # Only reported for callers that opted out of discovery; staying silent
        # here otherwise keeps the output identical to the shipped version.
        echo "No entitlements file: signing the outer bundle without entitlements."
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
    local app_path="$1"
    verbose_echo "Refreshing bundle modification date"
    /usr/bin/touch -c "${app_path}"

    verbose_echo "Registering applet with Launch Services"
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
        -f -R -trusted "${app_path}" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Generic deep signing (layout-independent replacement for `codesign --deep`).
#
# Passes, bottom-up (a nested item is always signed before whatever seals it):
#   Phase 1: sign loose NON-Mach-O files in nested-code locations (e.g. license
#            or data files placed beside helper tools in Contents/Helpers).
#   Phase 2: sign every loose Mach-O file anywhere in the bundle, individually.
#   Phase 3: sign every nested code bundle as a bundle, deepest-first, so a
#            child is always sealed before the parent that contains it.
#   Phase 4: sign the outer app bundle itself.
# ---------------------------------------------------------------------------

# Compute every candidate list up front so brief mode can report accurate counts
# before any signing starts.
nested_loose_files=$(list_nested_loose_files)
macho_files=$(list_macho_files)
nested_bundles=$(list_nested_bundles)

# ---- Entitlements cache --------------------------------------------------
#
# Signing replaces a signature rather than amending it, so every nested helper,
# framework and XPC service re-signed below would otherwise come out stripped of
# whatever entitlements it carried - a JIT-using helper silently losing
# allow-jit, correctly signed and notarized, crashing the first time it runs.
#
# The whole cache has to be built before any signing starts: phase 2 rewrites
# nested bundles' main executables before phase 3 reaches the bundles
# themselves, so reading entitlements lazily would read back the stripped ones.
# The outer bundle is not cached here - phase 4 applies the caller's choice.
ent_cache_dir=$(/usr/bin/mktemp -d /tmp/codesign_applet_ent.XXXXXX) || exit 1
# A signal handler that only cleans up and returns would resume signing with the
# cache gone, quietly stripping the entitlements from everything left to sign -
# and would make this script uninterruptible. Each signal cleans up and exits
# with the conventional 128+signo status.
trap '/bin/rm -rf "$ent_cache_dir"' EXIT
trap '/bin/rm -rf "$ent_cache_dir"; exit 129' HUP
trap '/bin/rm -rf "$ent_cache_dir"; exit 130' INT
trap '/bin/rm -rf "$ent_cache_dir"; exit 131' QUIT
trap '/bin/rm -rf "$ent_cache_dir"; exit 143' TERM

cache_entitlements() {
    local target_path="$1"
    local cache_file="$ent_cache_dir/$(printf '%s' "$target_path" | /sbin/md5 -q).entitlements"
    /usr/bin/codesign -d --entitlements - --xml "$target_path" > "$cache_file" 2>/dev/null
    if [ ! -s "$cache_file" ] || ! /usr/bin/grep -q '<key>' "$cache_file"; then
        /bin/rm -f "$cache_file"
    fi
}

# Print the cached entitlements file for a path, or nothing.
cached_entitlements() {
    local target_path="$1"
    local cache_file="$ent_cache_dir/$(printf '%s' "$target_path" | /sbin/md5 -q).entitlements"
    if [ -f "$cache_file" ]; then
        printf '%s' "$cache_file"
    fi
}

# Sign one nested item, carrying over whatever entitlements it already had.
sign_nested() {
    local target_path="$1"
    # Not named entitlements_file: that is the global holding the caller's choice
    # for the outer bundle, which phase 4 applies and this must not shadow.
    local carried_entitlements="$(cached_entitlements "$target_path")"
    if [ -n "$carried_entitlements" ]; then
        verbose_echo "  (carrying over entitlements from the existing signature)"
        run_codesign $cs_verbose --force $sign_options --entitlements "$carried_entitlements" $timestamp --sign "$identity" "$target_path"
    else
        run_codesign $cs_verbose --force $sign_options $timestamp --sign "$identity" "$target_path"
    fi
}

# Ad-hoc signing never applied entitlements to anything, so leaving the cache
# empty keeps that path behaving exactly as it always has - cached_entitlements
# finds nothing and every sign_nested call takes the plain branch.
if [ "$identity" != "-" ]; then
    # Read line by line rather than word-splitting: bundle paths contain spaces.
    printf '%s\n%s\n' "$macho_files" "$(list_signed_bundles)" \
        | while IFS= read -r cache_path; do
            [ -n "$cache_path" ] || continue
            cache_entitlements "$cache_path"
        done
fi

# ---- Phase 1: sign loose non-Mach-O files in nested (code) locations ------
#
# Runs BEFORE the Mach-O pass on purpose: signing the app's main executable seals
# the whole bundle, which fails if a nested loose file is still unsigned.
#
# These are data files, so there are no entitlements to carry over and
# sign_nested has nothing to look up - sign them directly. $sign_options still
# applies, so a Developer ID run stamps them with the hardened-runtime flag and a
# secure timestamp, exactly as it does for real code.
verbose_echo ""
verbose_echo "Signing loose non-code files in nested locations"
verbose_echo "-----------------------------------"

if [ -z "$nested_loose_files" ]; then
    nested_loose_count=0
else
    nested_loose_count=$(printf '%s\n' "$nested_loose_files" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
fi

if [ "$nested_loose_count" = "0" ]; then
    if [ "$brief" = "yes" ]; then
        echo "Signing 0 loose non-code files in nested locations"
    fi
else
    # Named, and reported in brief mode too. Nothing in a bundle's layout tells
    # you that dropping a README beside a helper tool turns it into a code
    # object, and the consequences are real in both directions: unsigned, the
    # bundle will not seal; signed, the signature can only live in extended
    # attributes that ordinary transport discards. A developer who did not
    # intend it should be told, once, exactly which files it applies to.
    echo "warning: $nested_loose_count non-code file(s) sit in code locations and will each be signed as their own code object:"
    printf '%s\n' "$nested_loose_files" | while IFS= read -r file_path; do
        printf '    %s\n' "${file_path#"$app_to_sign"/}"
    done
    echo "  codesign seals these locations as nested code, so every file in them needs a signature of its own."
    echo "  A non-Mach-O file can only carry one in extended attributes, which plain zip and tar discard;"
    echo "  deliver with ditto, a disk image or an installer package, and never run 'xattr -c' on the result."
    echo "  Moving such files to Contents/Resources avoids the special handling entirely."
    printf '%s\n' "$nested_loose_files" | while IFS= read -r file_path; do
        verbose_echo "Signing: $file_path"
        run_codesign $cs_verbose --force $sign_options $timestamp --sign "$identity" "$file_path"
        if test "$?" != "0"; then
            printf 'warning: failed to sign %s\n' "$file_path"
        fi
    done
fi

verbose_echo "-----------------------------------"

# ---- Phase 2: sign all loose Mach-O files --------------------------------
#
# Candidate files: regular files (never symlinks) anywhere under the app,
# excluding anything already inside a _CodeSignature seal directory. The
# executable bit alone is not sufficient: many dynamic libraries and plugins
# (*.dylib, *.so, *.node) ship without it yet still contain Mach-O code that the
# notary service will flag if left unsigned - so we match those extensions too.
verbose_echo ""
verbose_echo "Signing standalone Mach-O executables and libraries"
verbose_echo "-----------------------------------"

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
# by design - phase 3 re-signs those bundles and rewrites the seal, and an
# executable being signed twice costs nothing but a moment.
if [ -n "$macho_files" ]; then
    printf '%s\n' "$macho_files" | while IFS= read -r file_path; do
        verbose_echo "Signing: $file_path"
        sign_nested "$file_path"
        if test "$?" != "0"; then
            printf 'warning: failed to sign %s\n' "$file_path"
        fi
    done
fi

verbose_echo "-----------------------------------"

# ---- Phase 3: sign nested code bundles, deepest-first --------------------
#
# Discover every candidate bundle directory by recognised extension, then order
# them deepest-first (most path components first) so children are sealed before
# the parents that embed them.
verbose_echo ""
verbose_echo "Signing nested code bundles (deepest-first)"
verbose_echo "-----------------------------------"

# nested_bundles was computed once, above, from list_nested_bundles.

if [ -n "$nested_bundles" ]; then
    printf '%s\n' "$nested_bundles" | while IFS= read -r bundle_path; do
        bundle_name=$(/usr/bin/basename "$bundle_path")
        case "$bundle_path" in
            *.framework)
                # A framework is valid if it is versioned
                # (Versions/*/Resources/Info.plist) or a flat old-style bundle
                # (Resources/Info.plist directly). Detect which before signing.
                is_versioned="no"
                for version_dir in "$bundle_path"/Versions/*; do
                    if [ -f "$version_dir/Resources/Info.plist" ]; then
                        is_versioned="yes"
                        break
                    fi
                done
                if [ "$is_versioned" = "yes" ]; then
                    echo "Signing framework: $bundle_name"
                    # Sign each real version directory; skip symlinks such as
                    # Versions/Current, which just alias a real version.
                    for version_dir in "$bundle_path"/Versions/*; do
                        [ -d "$version_dir" ] || continue
                        if [ -L "$version_dir" ]; then
                            continue
                        fi
                        sign_nested "$version_dir"
                        if test "$?" != "0"; then
                            printf 'warning: failed to sign %s\n' "$version_dir"
                        fi
                    done
                elif [ -f "$bundle_path/Resources/Info.plist" ]; then
                    # Flat old-style framework: sign the bundle root directly.
                    echo "Signing bundle: $bundle_name"
                    sign_nested "$bundle_path"
                    if test "$?" != "0"; then
                        printf 'warning: failed to sign %s\n' "$bundle_name"
                    fi
                else
                    # Not a valid framework; its Mach-O contents were already
                    # signed in phase 2, so it is safe to leave the seal alone.
                    verbose_echo "Skipping invalid framework (no Info.plist): $bundle_path"
                fi
                ;;
            *)
                if [ -f "$bundle_path/Contents/Info.plist" ]; then
                    echo "Signing bundle: $bundle_name"
                    sign_nested "$bundle_path"
                    if test "$?" != "0"; then
                        printf 'warning: failed to sign %s\n' "$bundle_name"
                    fi
                else
                    # Missing Contents/Info.plist: not a real code bundle. Its
                    # Mach-O contents were already signed in phase 2.
                    verbose_echo "Skipping invalid bundle (no Contents/Info.plist): $bundle_path"
                fi
                ;;
        esac
    done
fi

verbose_echo "-----------------------------------"

verbose_echo ""

# ---- Phase 4: sign the outer app bundle ----------------------------------
# The generic phases above have already sealed all nested code, so the outer
# bundle no longer needs (or should use) `codesign --deep`.
echo "Signing app bundle: $app_to_sign"
# The entitlements path is quoted rather than folded into one variable with the
# other flags: a browsed-to file can sit under a folder with spaces in its name.
if [ -n "$entitlements_file" ]; then
    verbose_echo "/usr/bin/codesign $cs_verbose --force $sign_options --entitlements '$entitlements_file' $timestamp --identifier $app_id --sign $identity $app_to_sign"
    run_codesign $cs_verbose --force $sign_options --entitlements "$entitlements_file" $timestamp --identifier "$app_id" --sign "$identity" "$app_to_sign"
else
    verbose_echo "/usr/bin/codesign $cs_verbose --force $sign_options $timestamp --identifier $app_id --sign $identity $app_to_sign"
    run_codesign $cs_verbose --force $sign_options $timestamp --identifier "$app_id" --sign "$identity" "$app_to_sign"
fi

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
