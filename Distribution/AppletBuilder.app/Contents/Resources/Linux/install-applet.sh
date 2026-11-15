#!/bin/bash
# install-applet.sh - checks and sets up, on this Linux machine and for the current user, what a
# Command Engine applet needs beyond Command Engine itself. AppletBuilder copies it into every applet
# it builds, as <Name>.app/Contents/Linux/install-applet.sh. Design: OMC's
# Private/linux-applet-install-design.md.
#
# Command Engine is assumed installed: the command-engine package and its Swift runtime package bring
# everything the engine's own programs need (Contents/Linux, Contents/Frameworks), so the applet starts.
# This script covers only what is the applet's own (owner, 2026-11-15: "it may cover ONLY optional
# libraries, not libraries required for launching the applet itself"); where Command Engine is not
# installed it says so and stops.
#
#   --check       says what the applet needs and whether it is there, changing nothing:
#                 - the libraries it loads by name and lists in its Info.plist
#                   (CommandEngineLinuxRequires: sonames, such as libwebkitgtk-6.0.so.4 for web pages);
#                 - the libraries its own programs link (ldd): the helpers it carries
#                   (Contents/Helpers), programs and libraries in Contents/Resources and
#                   Contents/Library (an embedded Python);
#                 - whether it is on the desktop's app list (its desktop entry), for this copy;
#                 - for an applet with file services: their list, and whether this desktop's file
#                   manager has the plug-in that shows them (GNOME Files, Dolphin, Thunar), or that
#                   this desktop has none.
#   --register    adds this copy to the desktop's app list and lists its file services (the engine's
#                 linux-app-entry.py and command-services.py, with the system's python3), then
#                 checks the file manager plug-in.
#   --unregister  takes it off again.
#   --status      for the engine's first-launch check (EntryPoints/Linux/OMCAppletMain.cpp,
#                 Platform/Linux/OMCDesktopRegistration.cpp): one word on standard output:
#                 "this" (this copy is on the app list), "moved" (the entry runs a program that is
#                 no longer there: the engine registers this copy without asking), "other" (another
#                 copy that is there owns it: nothing is done), "none" (not on the app list: the
#                 engine asks), or "declined" (not on it, and the user answered Never).
#   --decline     remembers the answer Never (do not ask again): the applet's setting CommandEngineDesktopPrompt =
#                 never, in its own settings domain (its bundle identifier; the Support folder's
#                 defaults tool). --register still works; the setting only stops the question.
#
# Exit status: 0 everything is there (--check) or done, 1 something is missing or a step failed,
# 2 bad arguments or not inside an applet bundle.

mode="$1"
if [ $# -ne 1 ]; then
    mode=""
fi
case "$mode" in
    --check|--register|--unregister|--status|--decline) ;;
    *)
        printf 'Usage: %s --check | --register | --unregister | --status | --decline\n' "$0" >&2
        exit 2
        ;;
esac

here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
bundle="${here%/Contents/Linux}"
if [ -z "$here" ] || [ "$bundle" = "$here" ] || [ ! -f "$bundle/Contents/Info.plist" ]; then
    printf 'Not inside an applet bundle (<Name>.app/Contents/Linux): %s\n' "$here" >&2
    exit 2
fi
info_plist="$bundle/Contents/Info.plist"
support="$bundle/Contents/Frameworks/Abracode.framework/Support"
plister="$support/plister"
# The applet's setting that stops the engine's first-launch question (--decline)
prompt_key="CommandEngineDesktopPrompt"
missing_count=0

name="$(/usr/bin/basename -- "$bundle" .app)"

# What the loader cannot give <file>, one per line: a library it cannot find ("libfoo.so.1"), or a
# version a system library is too old for ("GLIBC_2.42 (libc.so.6 is older)"). ldd's own output and
# its messages are read together.
missing_linked_libraries() { # <ELF file>
    local linked
    linked="$(/usr/bin/ldd -- "$1" 2>&1)"
    printf '%s\n' "$linked" | /usr/bin/sed -n \
        -e 's/^[[:space:]]*\([^[:space:]]*\) => not found.*/\1/p' \
        -e "s/^.*[[:space:]/]\([^[:space:]/]*\): version \`\([^']*\)' not found.*/\2 (\1 is older)/p"
}

# The package that has <soname> on this distribution, for the libraries Command Engine applets load by
# name; empty for one it does not know
library_package() { # <soname>
    local family=""
    if [ -f /etc/os-release ]; then
        family="$(/usr/bin/sed -n 's/^ID=//p; s/^ID_LIKE=//p' /etc/os-release | /usr/bin/tr -d '"' | /usr/bin/tr '\n' ' ')"
    fi
    case " $family " in
        *" debian "*|*" ubuntu "*)
            case "$1" in
                libwebkitgtk-6.0.so.4) printf 'libwebkitgtk-6.0-4' ;;
                libshumate-1.0.so.1) printf 'libshumate-1.0-1' ;;
            esac
            ;;
        *" fedora "*)
            case "$1" in
                libwebkitgtk-6.0.so.4) printf 'webkitgtk6.0' ;;
                libshumate-1.0.so.1) printf 'libshumate' ;;
            esac
            ;;
    esac
}

# The data home desktop entries and services lists go to (as linux-app-entry.py takes it)
data_home="$HOME/.local/share"
case "$XDG_DATA_HOME" in
    /*) data_home="$XDG_DATA_HOME" ;;
esac

# Whether the applet has a file service as command-services.py counts one (the services it lists for
# the file managers): an NSServices item that sends files, by NSSendFileTypes or by NSSendTypes
# naming NSFilenamesPboardType or public.file-url. A text service is not for a file manager.
has_file_services() {
    local count
    count="$("$plister" get count "$info_plist" /NSServices 2>/dev/null)"
    local count_status=$?
    if [ "$count_status" -ne 0 ]; then
        return 1
    fi
    case "$count" in
        ""|*[!0-9]*) return 1 ;;
    esac
    local index=0
    while [ "$index" -lt "$count" ]; do
        local item="/NSServices/$index"
        local file_type="$("$plister" get value "$info_plist" "$item/NSSendFileTypes/0" 2>/dev/null)"
        if [ -n "$file_type" ]; then
            return 0
        fi
        local type_count="$("$plister" get count "$info_plist" "$item/NSSendTypes" 2>/dev/null)"
        case "$type_count" in
            ""|*[!0-9]*) type_count=0 ;;
        esac
        local type_index=0
        while [ "$type_index" -lt "$type_count" ]; do
            local send_type="$("$plister" get value "$info_plist" "$item/NSSendTypes/$type_index" 2>/dev/null)"
            case "$send_type" in
                NSFilenamesPboardType|public.file-url) return 0 ;;
            esac
            type_index=$((type_index + 1))
        done
        index=$((index + 1))
    done
    return 1
}

# This desktop's file manager plug-in for applet services: prints the file manager's name and the
# plug-in's package; returns 0 when the plug-in is installed, 1 when not, 2 when this desktop has no
# file manager Command Engine has a plug-in for
file_manager_plugin() {
    local desktop="$XDG_CURRENT_DESKTOP"
    local pattern
    case ":$desktop:" in
        *:GNOME:*|*:Unity:*|*:ubuntu:*)
            printf 'GNOME Files (package command-engine-files-nautilus)'
            pattern="nautilus/extensions-4/libcommand-services-nautilus.so"
            ;;
        *:KDE:*)
            printf 'Dolphin (package command-engine-files-dolphin)'
            pattern="qt6/plugins/kf6/kfileitemaction/command-services-dolphin.so"
            ;;
        *:XFCE:*)
            printf 'Thunar (package command-engine-files-thunar)'
            pattern="thunarx-3/libcommand-services-thunar.so"
            ;;
        *)
            printf '%s' "${desktop:-this desktop}"
            return 2
            ;;
    esac
    local plugin
    for plugin in /usr/lib/*/"$pattern" /usr/lib64/"$pattern" /usr/lib/"$pattern"; do
        if [ -f "$plugin" ]; then
            return 0
        fi
    done
    return 1
}

# Whose the desktop entry for <identifier> is: sets entry_file, entry_exec (its Exec line) and
# entry_state: "none" (no entry), "this" (it runs this copy), "moved" (it runs a program that is no
# longer there: this applet was moved or renamed) or "other" (another copy that is there).
# The entry is this copy's when the program it runs is in this bundle: its TryExec is the program's
# path (linux-app-entry.py writes it as it is, but for a backslash doubled), and its Exec starts with
# that path, in double quotes when the path has a space (escaped further when it has a $, `, " or
# backslash, which only TryExec then matches). Matched from the start: a copy at /a/Find.app is not
# one at /b/a/Find.app.
entry_owner() { # <identifier>
    entry_file="$data_home/applications/$1.desktop"
    entry_exec=""
    entry_state="none"
    local try_exec=""
    if [ -f "$entry_file" ]; then
        entry_exec="$(/usr/bin/sed -n 's/^Exec=//p' "$entry_file" | /usr/bin/head -n 1)"
        try_exec="$(/usr/bin/sed -n 's/^TryExec=//p' "$entry_file" | /usr/bin/head -n 1)"
    fi
    if [ -z "$entry_exec" ]; then
        return
    fi
    local program_folder="$bundle/Contents/Linux/"
    case "$try_exec" in
        "$program_folder"*) entry_state="this"; return ;;
    esac
    case "$entry_exec" in
        "$program_folder"*|"\"$program_folder"*) entry_state="this"; return ;;
    esac
    entry_state="other"
    # Only a TryExec names the program plainly: with a backslash doubled in it, it is not tested
    case "$try_exec" in
        /*\\*) ;;
        /*)
            if [ ! -e "$try_exec" ]; then
                entry_state="moved"
            fi
            ;;
    esac
}

check() {
    printf '%s (%s)\n' "$name" "$bundle"

    # Command Engine itself: its tools run only when its packages are installed
    if [ ! -x "$plister" ]; then
        printf 'No plister in %s: the engine framework is incomplete (an AppletBuilder build puts it back)\n' "$support"
        missing_count=$((missing_count + 1))
        return
    fi
    "$plister" get value "$info_plist" /CFBundleIdentifier > /dev/null 2>&1
    local engine_status=$?
    if [ "$engine_status" -eq 127 ] || [ "$engine_status" -eq 126 ]; then
        printf 'Command Engine is not installed here: install the command-engine package (with its Swift\n'
        printf 'runtime package) first; it brings everything the applet needs to start.\n'
        missing_count=$((missing_count + 1))
        return
    fi

    # Libraries loaded by name, from the applet's own list
    local ldconfig=/usr/sbin/ldconfig
    if [ ! -x "$ldconfig" ]; then
        ldconfig=/sbin/ldconfig
    fi
    local cache
    cache="$("$ldconfig" -p 2>/dev/null)"
    local index=0
    local soname
    while true; do
        soname="$("$plister" get value "$info_plist" "/CommandEngineLinuxRequires/$index" 2>/dev/null)"
        local get_status=$?
        if [ "$get_status" -ne 0 ] || [ -z "$soname" ]; then
            break
        fi
        # A cache line is "<tab><soname> (<flags>) => <path>": anchored on both sides, so that
        # libfoo.so.1 is neither libfoo.so.10 nor libxfoo.so.1
        case "$cache" in
            *$'\t'"$soname ("*) printf 'Required library %s: found\n' "$soname" ;;
            *)
                local package
                package="$(library_package "$soname")"
                if [ -n "$package" ]; then
                    printf 'Required library %s: MISSING (package %s)\n' "$soname" "$package"
                else
                    printf 'Required library %s: MISSING (no package known here; on Debian, apt-file search %s)\n' "$soname" "$soname"
                fi
                missing_count=$((missing_count + 1))
                ;;
        esac
        index=$((index + 1))
    done

    # The applet's own programs and libraries: everything in the bundle but the engine's
    # (Contents/Linux, Contents/Frameworks) that is an ELF file: a program (executable) or a shared
    # library (*.so, *.so.<n>), such as a helper tool or an embedded Python's modules
    # A library the bundle carries itself is not missing, though ldd alone may not find it (an
    # embedded Python's libpython3.so names libpython3.<minor>.so beside it, which Python has loaded)
    local bundle_libraries
    bundle_libraries=" $(/usr/bin/find "$bundle/Contents" -name '*.so*' -exec /usr/bin/basename {} \; 2>/dev/null | /usr/bin/tr '\n' ' ')"
    local missing=""
    local file
    while IFS= read -r -d '' file; do
        local magic
        magic="$(/usr/bin/head -c 4 -- "$file" 2>/dev/null | /usr/bin/od -An -c | /usr/bin/tr -d ' \n')"
        if [ "$magic" != "177ELF" ]; then
            continue
        fi
        local file_missing
        file_missing="$(missing_linked_libraries "$file")"
        local item
        while IFS= read -r item; do
            if [ -z "$item" ]; then
                continue
            fi
            case "$bundle_libraries" in
                *" $item "*) continue ;;
            esac
            missing="$missing$item (${file#"$bundle"/})"$'\n'
        done <<< "$file_missing"
    done < <(/usr/bin/find "$bundle/Contents" \( -path "$bundle/Contents/Linux" -o -path "$bundle/Contents/Frameworks" \) -prune \
                 -o -type f \( -perm -u+x -o -name '*.so' -o -name '*.so.*' \) -print0)
    if [ -n "$missing" ]; then
        printf 'Libraries the applet'"'"'s own programs link, MISSING:\n'
        printf '%s' "$missing" | /usr/bin/sed 's/^/  /'
        missing_count=$((missing_count + 1))
    fi

    # The desktop entry
    local identifier
    identifier="$("$plister" get value "$info_plist" /CFBundleIdentifier 2>/dev/null)"
    local id_status=$?
    if [ "$id_status" -ne 0 ] || [ -z "$identifier" ]; then
        printf 'No CFBundleIdentifier in %s\n' "$info_plist"
        missing_count=$((missing_count + 1))
        return
    fi
    entry_owner "$identifier"
    case "$entry_state" in
        none)
            printf 'App list: not added (install-applet.sh --register adds it)\n'
            missing_count=$((missing_count + 1))
            ;;
        this) printf 'App list: added (%s)\n' "$entry_file" ;;
        moved)
            printf 'App list: added for a copy that is no longer there (%s); --register adds this one\n' "$entry_exec"
            missing_count=$((missing_count + 1))
            ;;
        *)
            printf 'App list: added for another copy (%s)\n' "$entry_exec"
            missing_count=$((missing_count + 1))
            ;;
    esac

    # File services: only for an applet that has any
    has_file_services
    local services_status=$?
    if [ "$services_status" -ne 0 ]; then
        return
    fi
    local services_list="$data_home/command/services/$identifier.services"
    if [ -f "$services_list" ]; then
        printf 'File services: listed\n'
    else
        printf 'File services: not listed (install-applet.sh --register lists them)\n'
        missing_count=$((missing_count + 1))
    fi
    local plugin_text
    plugin_text="$(file_manager_plugin)"
    local plugin_status=$?
    case "$plugin_status" in
        0) printf 'File manager plug-in: %s, installed\n' "$plugin_text" ;;
        1)
            printf 'File manager plug-in: %s, NOT installed: the file manager shows no Services until it is\n' "$plugin_text"
            missing_count=$((missing_count + 1))
            ;;
        *) printf 'File manager plug-in: none for %s: its file manager shows no applet services\n' "$plugin_text" ;;
    esac
}

# Runs <script> <action> on the bundle with the system's python3, printing its output; returns its status
run_support_script() { # <script> <install|uninstall>
    if [ ! -x /usr/bin/python3 ]; then
        printf 'No /usr/bin/python3 (the python3 package), which %s needs\n' "$1"
        return 1
    fi
    /usr/bin/python3 -I "$support/$1" "$2" "$bundle" 2>&1
    return $?
}

case "$mode" in
    --check)
        check
        if [ "$missing_count" -ne 0 ]; then
            exit 1
        fi
        exit 0
        ;;
    --register)
        run_support_script linux-app-entry.py install
        status=$?
        if [ "$status" -ne 0 ]; then
            exit 1
        fi
        run_support_script command-services.py install
        status=$?
        if [ "$status" -ne 0 ]; then
            exit 1
        fi
        # The plug-in matters only to an applet with file services
        has_file_services
        services_status=$?
        if [ "$services_status" -ne 0 ]; then
            exit 0
        fi
        plugin_text="$(file_manager_plugin)"
        plugin_status=$?
        case "$plugin_status" in
            1) printf 'Note: the file manager shows no Services until %s is installed\n' "$plugin_text" ;;
            2) printf 'Note: %s has no file manager Command Engine has a plug-in for: no Services menu\n' "$plugin_text" ;;
        esac
        exit 0
        ;;
    --unregister)
        run_support_script command-services.py uninstall
        services_status=$?
        run_support_script linux-app-entry.py uninstall
        entry_status=$?
        if [ "$services_status" -ne 0 ] || [ "$entry_status" -ne 0 ]; then
            exit 1
        fi
        exit 0
        ;;
    --status|--decline)
        identifier="$("$plister" get value "$info_plist" /CFBundleIdentifier 2>/dev/null)"
        id_status=$?
        if [ "$id_status" -ne 0 ] || [ -z "$identifier" ]; then
            printf 'No CFBundleIdentifier in %s (or Command Engine is not installed)\n' "$info_plist" >&2
            exit 1
        fi
        if [ "$mode" = "--decline" ]; then
            "$support/defaults" write "$identifier" "$prompt_key" -string never
            exit $?
        fi
        entry_owner "$identifier"
        if [ "$entry_state" = "none" ]; then
            declined="$("$support/defaults" read "$identifier" "$prompt_key" 2>/dev/null)"
            if [ "$declined" = "never" ]; then
                entry_state="declined"
            fi
        fi
        printf '%s\n' "$entry_state"
        exit 0
        ;;
esac
