#!/bin/bash
# install.sh - installs a Command Engine applet from its download archive, on a Linux machine that may
# not have the system packages Command Engine applets need yet. make-applet-archive.sh puts it beside
# the applet; the user runs ./install.sh in a terminal in the unpacked folder.
#
# Steps:
#   1. The system packages: when the command-engine package (the system libraries Command Engine
#      applets need) of at least the applet's engine version, or the Swift runtime package its programs
#      load (command-engine-swift-<runtime version>, e.g. command-engine-swift-6.4) of at least the
#      Swift release they were built with, is missing, installs them with apt (Debian, Ubuntu) or
#      dnf (Fedora), which brings the system libraries they depend on. The package files come from --packages <folder>, else from
#      packages/ beside this script, else they are downloaded (curl or wget) from the release address
#      in install-info. When packages.sha256 is there, a file whose checksum does not match is refused.
#   2. Copies <Name>.app into ~/Applications (or --to <folder>), replacing an older copy there after
#      asking.
#   3. Runs the applet's own Contents/Linux/install-applet.sh: --install-packages (the libraries the
#      applet itself needs: a web view's WebKitGTK, ...), then --register (the app list, the file
#      managers' Services) unless --no-register.
# Asks before installing or replacing anything, unless --yes. Installing packages needs root: sudo in a
# terminal (pkexec without one), or run as root.
#
# Usage: install.sh [--yes] [--packages <folder>] [--to <folder>] [--no-register]
# Exit status: 0 installed, 1 a step failed or was declined, 2 bad arguments or an incomplete archive.

assume_yes=0
packages_given=""
destination=""
register=1
while [ $# -gt 0 ]; do
    case "$1" in
        --yes) assume_yes=1; shift ;;
        --no-register) register=0; shift ;;
        --packages|--to)
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                printf 'install.sh: %s needs a folder\n' "$1" >&2
                exit 2
            fi
            if [ "$1" = "--packages" ]; then
                packages_given="$2"
            else
                destination="$2"
            fi
            shift 2
            ;;
        -h|--help)
            printf 'Usage: %s [--yes] [--packages <folder>] [--to <folder>] [--no-register]\n' "$0"
            printf '  --yes          install and replace without asking\n'
            printf '  --packages     take the packages from this folder, not the download\n'
            printf '  --to           install the applet into this folder (default ~/Applications)\n'
            printf '  --no-register  do not add the applet to the app list and the Services menu\n'
            exit 0
            ;;
        *)
            printf 'Usage: %s [--yes] [--packages <folder>] [--to <folder>] [--no-register]\n' "$0" >&2
            exit 2
            ;;
    esac
done

here="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
info="$here/install-info"
read_info() { # <key>
    /usr/bin/sed -n "s/^$1=//p" "$info" 2>/dev/null | /usr/bin/head -n 1
}
applet_name="$(read_info applet_name)"
engine_version="$(read_info engine_version)"
runtime_version="$(read_info runtime_version)"
swift_version="$(read_info swift_version)"
architecture="$(read_info architecture)"
release_url="$(read_info release_url)"
if [ -z "$applet_name" ] || [ -z "$engine_version" ] || [ -z "$runtime_version" ] || [ -z "$swift_version" ] || [ -z "$architecture" ]; then
    printf 'install.sh: no complete install-info beside this script (%s): unpack the whole archive\n' "$info" >&2
    exit 2
fi
source_bundle="$here/$applet_name.app"
if [ ! -x "$source_bundle/Contents/Linux/install-applet.sh" ]; then
    printf 'install.sh: no %s.app with its install-applet.sh beside this script\n' "$applet_name" >&2
    exit 2
fi
machine="$(/usr/bin/uname -m)"
if [ "$machine" != "$architecture" ]; then
    printf '%s is built for %s; this machine is %s. Download the %s archive instead.\n' "$applet_name" "$architecture" "$machine" "$machine" >&2
    exit 1
fi

# Asks <question> in the terminal, or takes --yes; returns 0 for yes
confirm() { # <question>
    if [ "$assume_yes" -eq 1 ]; then
        return 0
    fi
    if [ ! -t 0 ]; then
        printf '%s Not done: run this in a terminal to be asked, or with --yes.\n' "$1"
        return 1
    fi
    local answer=""
    printf '%s [y/N] ' "$1"
    read -r answer
    case "$answer" in
        y|Y|yes|Yes) return 0 ;;
    esac
    return 1
}

# Whether version <have> is at least <need> (plain dotted numbers)
version_at_least() { # <have> <need>
    local lowest="$(printf '%s\n%s\n' "$1" "$2" | /usr/bin/sort -V | /usr/bin/head -n 1)"
    [ "$lowest" = "$2" ]
}

# The family of this distribution: "debian" (Debian, Ubuntu and their derivatives), "fedora", or nothing
family=""
if [ -f /etc/os-release ]; then
    ids="$(/usr/bin/sed -n 's/^ID=//p; s/^ID_LIKE=//p' /etc/os-release | /usr/bin/tr -d '"' | /usr/bin/tr '\n' ' ')"
    case " $ids " in
        *" debian "*|*" ubuntu "*) family="debian" ;;
        *" fedora "*) family="fedora" ;;
    esac
fi

# The installed upstream version of <package>, or nothing
installed_version() { # <package>
    local version=""
    if [ "$family" = "debian" ]; then
        local state="$(/usr/bin/dpkg-query -W -f='${db:Status-Abbrev} ${Version}' "$1" 2>/dev/null)"
        # Installed: "ii", or "hi" when held
        case "$state" in
            ?i*) version="${state##* }" ;;
        esac
    elif [ "$family" = "fedora" ]; then
        version="$(/usr/bin/rpm -q --qf '%{VERSION}' "$1" 2>/dev/null)"
        local rpm_status=$?
        if [ "$rpm_status" -ne 0 ]; then
            version=""
        fi
    fi
    # Debian's revision (-1) is not part of the upstream version
    printf '%s' "${version%-*}"
}

# 1. The command-engine and Swift runtime packages
engine_package="command-engine"
runtime_package="command-engine-swift-$runtime_version"
case "$architecture" in
    aarch64) deb_architecture="arm64" ;;
    x86_64) deb_architecture="amd64" ;;
    *) deb_architecture="$architecture" ;;
esac
if [ "$family" = "debian" ]; then
    engine_file="command-engine_${engine_version}-1_${deb_architecture}.deb"
    runtime_file="command-engine-swift-${runtime_version}_${swift_version}-1_${deb_architecture}.deb"
elif [ "$family" = "fedora" ]; then
    engine_file="command-engine-${engine_version}-1.${architecture}.rpm"
    runtime_file="command-engine-swift-${runtime_version}-${swift_version}-1.${architecture}.rpm"
else
    printf 'This installer knows Debian, Ubuntu and Fedora; this distribution is none of them.\n'
    printf 'Install the packages command-engine %s and command-engine-swift-%s with your package manager, then run\n' "$engine_version" "$runtime_version"
    printf '%s.app/Contents/Linux/install-applet.sh --check\n' "$applet_name"
    exit 1
fi

needed_files=()
have_engine="$(installed_version "$engine_package")"
if [ -z "$have_engine" ]; then
    printf 'The command-engine package (the system libraries Command Engine applets need) is not installed.\n'
    needed_files+=("$engine_file")
elif ! version_at_least "$have_engine" "$engine_version"; then
    printf 'The command-engine package %s is installed; %s needs %s or later.\n' "$have_engine" "$applet_name" "$engine_version"
    needed_files+=("$engine_file")
fi
have_runtime="$(installed_version "$runtime_package")"
if [ -z "$have_runtime" ]; then
    printf 'The Swift %s runtime (%s) is not installed.\n' "$runtime_version" "$runtime_package"
    needed_files+=("$runtime_file")
elif ! version_at_least "$have_runtime" "$swift_version"; then
    printf 'The Swift runtime %s is installed; %s needs %s or later.\n' "$have_runtime" "$applet_name" "$swift_version"
    needed_files+=("$runtime_file")
fi

if [ ${#needed_files[@]} -gt 0 ]; then
    # Where the files come from: --packages, packages/ beside this script, or a download
    package_folder=""
    if [ -n "$packages_given" ]; then
        package_folder="$(CDPATH= cd -P -- "$packages_given" 2>/dev/null && pwd)"
        if [ -z "$package_folder" ]; then
            printf 'No packages folder %s\n' "$packages_given" >&2
            exit 2
        fi
    elif [ -d "$here/packages" ]; then
        package_folder="$here/packages"
        # An archive made with only one format's packages (the .deb files, say) has not got this
        # machine's: then they are downloaded, checked against packages.sha256 all the same
        for file in "${needed_files[@]}"; do
            if [ ! -f "$package_folder/$file" ]; then
                printf 'No %s in %s: downloading instead.\n' "$file" "$package_folder"
                package_folder=""
                break
            fi
        done
    fi
    if [ -z "$package_folder" ]; then
        case "$release_url" in
            https://*) ;;
            *)
                printf 'No packages beside this script and no https release address in install-info: get %s and run with --packages <folder>\n' "${needed_files[*]}" >&2
                exit 1
                ;;
        esac
        downloader=""
        if [ -x /usr/bin/curl ]; then
            downloader="curl"
        elif [ -x /usr/bin/wget ]; then
            downloader="wget"
        else
            printf 'Neither curl nor wget is installed. Download these into a folder and run with --packages <folder>:\n' >&2
            for file in "${needed_files[@]}"; do
                printf '  %s/%s\n' "$release_url" "$file" >&2
            done
            exit 1
        fi
        if ! confirm "Download ${needed_files[*]} from $release_url?"; then
            exit 1
        fi
        package_folder="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/command-engine-packages.XXXXXX")"
        status=$?
        if [ "$status" -ne 0 ] || [ -z "$package_folder" ]; then
            printf 'Cannot make a download folder\n' >&2
            exit 1
        fi
        # The downloads go when the script ends, installed or not
        download_folder="$package_folder"
        trap '/bin/rm -rf -- "$download_folder"' EXIT
        for file in "${needed_files[@]}"; do
            printf 'Downloading %s\n' "$file"
            if [ "$downloader" = "curl" ]; then
                /usr/bin/curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error --output "$package_folder/$file" "$release_url/$file"
                status=$?
            else
                /usr/bin/wget --quiet --https-only --output-document="$package_folder/$file" "$release_url/$file"
                status=$?
            fi
            if [ "$status" -ne 0 ]; then
                printf 'Cannot download %s/%s (%s status %s)\n' "$release_url" "$file" "$downloader" "$status" >&2
                exit 1
            fi
        done
    fi

    for file in "${needed_files[@]}"; do
        if [ ! -f "$package_folder/$file" ]; then
            printf 'No %s in %s\n' "$file" "$package_folder" >&2
            exit 1
        fi
        # The checksum the archive was made with, when it has one for this file
        if [ -f "$here/packages.sha256" ]; then
            expected="$(/usr/bin/awk -v name="$file" '$2 == name { print $1 }' "$here/packages.sha256")"
            if [ -n "$expected" ]; then
                actual="$(/usr/bin/sha256sum -- "$package_folder/$file" | /usr/bin/cut -d ' ' -f 1)"
                if [ "$actual" != "$expected" ]; then
                    printf 'Refused: %s does not match the checksum this archive was made with\n' "$package_folder/$file" >&2
                    exit 1
                fi
                printf 'Checked: %s\n' "$file"
            else
                printf 'Not checked (no checksum for it in packages.sha256): %s\n' "$file"
            fi
        else
            printf 'Not checked (the archive has no packages.sha256): %s\n' "$file"
        fi
    done

    if [ "$family" = "debian" ]; then
        manager=(/usr/bin/apt-get install -y)
    else
        manager=(/usr/bin/dnf install -y)
    fi
    if [ ! -x "${manager[0]}" ]; then
        printf 'No %s here\n' "${manager[0]}" >&2
        exit 1
    fi
    install_paths=()
    for file in "${needed_files[@]}"; do
        install_paths+=("$package_folder/$file")
    done
    if ! confirm "Install ${needed_files[*]} (${manager[0]##*/}, as root)?"; then
        exit 1
    fi
    uid="$(/usr/bin/id -u)"
    runner=()
    if [ "$uid" = "0" ]; then
        runner=()
    elif [ -t 0 ] && [ -x /usr/bin/sudo ]; then
        runner=(/usr/bin/sudo)
    elif [ -x /usr/bin/pkexec ]; then
        runner=(/usr/bin/pkexec)
    else
        printf 'Installing needs root: run as root: %s %s\n' "${manager[*]}" "${install_paths[*]}" >&2
        exit 1
    fi
    "${runner[@]}" "${manager[@]}" "${install_paths[@]}"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'The installation failed (status %s). As root: %s %s\n' "$status" "${manager[*]}" "${install_paths[*]}" >&2
        exit 1
    fi
    printf 'Installed: %s\n' "${needed_files[*]}"
else
    printf 'The command-engine package %s and the Swift %s runtime are installed.\n' "$have_engine" "$runtime_version"
fi

# 2. The applet, into its folder
if [ -z "$destination" ]; then
    destination="$HOME/Applications"
fi
/bin/mkdir -p -- "$destination"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make %s\n' "$destination" >&2
    exit 1
fi
destination_folder="$(CDPATH= cd -P -- "$destination" && pwd)"
if [ -z "$destination_folder" ]; then
    printf 'Cannot enter %s\n' "$destination" >&2
    exit 1
fi
installed_bundle="$destination_folder/$applet_name.app"
if [ "$installed_bundle" = "$source_bundle" ]; then
    printf '%s.app is already in %s\n' "$applet_name" "$destination_folder"
else
    if [ -e "$installed_bundle" ] || [ -L "$installed_bundle" ]; then
        if ! confirm "Replace $installed_bundle?"; then
            exit 1
        fi
        /bin/rm -rf -- "$installed_bundle"
        status=$?
        if [ "$status" -ne 0 ]; then
            printf 'Cannot remove %s\n' "$installed_bundle" >&2
            exit 1
        fi
    fi
    /bin/cp -a -- "$source_bundle" "$installed_bundle"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy %s.app into %s\n' "$applet_name" "$destination_folder" >&2
        exit 1
    fi
    printf 'Copied %s.app into %s\n' "$applet_name" "$destination_folder"
fi

# 3. The applet's own libraries and its place on the desktop
applet_installer="$installed_bundle/Contents/Linux/install-applet.sh"
result=0
if [ "$assume_yes" -eq 1 ]; then
    /bin/bash "$applet_installer" --install-packages --yes
    status=$?
else
    /bin/bash "$applet_installer" --install-packages
    status=$?
fi
if [ "$status" -ne 0 ]; then
    printf 'Some libraries %s needs are still missing (above); it may start without them.\n' "$applet_name"
    result=1
fi
if [ "$register" -eq 1 ]; then
    /bin/bash "$applet_installer" --register
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Adding %s to the app list failed (above).\n' "$applet_name"
        result=1
    fi
fi
printf '%s is installed: %s\n' "$applet_name" "$installed_bundle"
exit "$result"
