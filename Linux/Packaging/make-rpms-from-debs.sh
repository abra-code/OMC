#!/bin/bash
# Linux/Packaging/make-rpms-from-debs.sh - makes the Fedora packages (.rpm) command-engine (the
# system libraries Command Engine applets need) and command-engine-swift-<runtime version> (the Swift
# runtime libraries they load) from their Debian packages, with the same files. Programs built on
# Debian 13 run on Fedora 45 (the release tests archive passed there on 2026-11-16), so one build
# feeds both formats, and the .deb scripts stay the one place that decides what goes in.
#
# - command-engine-swift-<runtime version>: the runtime .deb's files as they are. rpm's dependency
#   generator names what the libraries need from the system (glibc, libstdc++, libgcc); what they need of each
#   other is filtered out, and the package provides no sonames, so it never stands in for a Fedora
#   Swift package nor is satisfied by one.
# - command-engine: the command-engine .deb's files (README, /usr/sbin/command-engine-cleanup, the
#   records folder /var/lib/command-engine/applets with mode 1777). Its Requires are the sonames the
#   engine programs need (readelf NEEDED of the master applet's executable and support tools) that
#   neither the runtime package nor the bundle has, in rpm's form "libgtk-4.so.1()(64bit)", plus Fedora's
#   names for what the engine loads by name (librsvg2, glib-networking, adwaita-icon-theme) and
#   python3, and the runtime package of at least the products' Swift release. Its %post points at the
#   cleanup when more than one Swift runtime version is installed.
#
# Usage: make-rpms-from-debs.sh <products folder> <deb folder> <output folder>
#   The products folder is build-linux.sh's (command-engine-runtime, CommandApplet.app); the deb folder
#   holds the packages make-swift-runtime-deb.sh and make-engine-deb.sh made from those products.
#   Writes <output>/command-engine-swift-<runtime version>-<swift version>-1.<arch>.rpm and
#   <output>/command-engine-<engine version>-1.<arch>.rpm (the names install.sh looks for).
# Needs rpmbuild (Debian's rpm package is enough), dpkg-deb and readelf. Exit status: 0 made, 1 failed,
# 2 bad arguments.

umask 022

products="$1"
debs="$2"
output="$3"
if [ -z "$products" ] || [ -z "$debs" ] || [ -z "$output" ] || [ $# -ne 3 ]; then
    printf 'Usage: %s <products folder> <deb folder> <output folder>\n' "$0" >&2
    exit 2
fi
for tool in /usr/bin/rpmbuild /usr/bin/dpkg-deb /usr/bin/readelf /usr/bin/dpkg; do
    if [ ! -x "$tool" ]; then
        printf 'No %s\n' "$tool" >&2
        exit 1
    fi
done
script_folder="$(CDPATH= cd -P -- "$(/usr/bin/dirname -- "$0")" && pwd)"
omc_root="$(CDPATH= cd -P -- "$script_folder/../.." && pwd)"
runtime_info="$products/command-engine-runtime"
swift_version="$(/usr/bin/sed -n 's/^swift_version=//p' "$runtime_info" 2>/dev/null)"
runtime_version="$(/usr/bin/sed -n 's/^runtime_line=//p' "$runtime_info" 2>/dev/null)"
if [ -z "$swift_version" ] || [ -z "$runtime_version" ]; then
    printf 'No swift_version or runtime_line (the Swift runtime version) in %s: build the products with build-linux.sh\n' "$runtime_info" >&2
    exit 1
fi
engine_version="$(/usr/bin/sed -n 's/^OMC_BUNDLE_VERSION *= *\([0-9][0-9.]*\) *$/\1/p' "$omc_root/Common/OmcVersion.xcconfig")"
if [ -z "$engine_version" ]; then
    printf 'Cannot read OMC_BUNDLE_VERSION from %s\n' "$omc_root/Common/OmcVersion.xcconfig" >&2
    exit 1
fi
architecture="$(/usr/bin/uname -m)"
deb_architecture="$(/usr/bin/dpkg --print-architecture)"
if [ -z "$architecture" ] || [ -z "$deb_architecture" ]; then
    printf 'Cannot tell the architecture\n' >&2
    exit 1
fi
runtime_deb="$debs/command-engine-swift-${runtime_version}_${swift_version}-1_${deb_architecture}.deb"
engine_deb="$debs/command-engine_${engine_version}-1_${deb_architecture}.deb"
for deb in "$runtime_deb" "$engine_deb"; do
    if [ ! -f "$deb" ]; then
        printf 'No %s: make it with make-swift-runtime-deb.sh and make-engine-deb.sh from the same products\n' "$deb" >&2
        exit 1
    fi
done
master="$products/CommandApplet.app/Contents"
programs=("$master/Linux/CommandApplet")
for tool in omc_dialog_control omc_next_command plister b64 filt loco; do
    programs+=("$master/Frameworks/Command.framework/Support/$tool")
done
for program in "${programs[@]}"; do
    if [ ! -f "$program" ]; then
        printf 'No %s: build all products with build-linux.sh\n' "$program" >&2
        exit 1
    fi
done

/bin/mkdir -p -- "$output"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make %s\n' "$output" >&2
    exit 1
fi
output_given="$output"
output="$(CDPATH= cd -P -- "$output_given" && pwd)"
if [ -z "$output" ]; then
    printf 'Cannot enter %s\n' "$output_given" >&2
    exit 1
fi
# The work folder goes into the spec files and rpmbuild's own commands unquoted (its rm -rf of the
# build root among them), and rpm expands % in it: a space there would split a path, so refuse
case "$output" in
    *[[:space:]%]*)
        printf 'The output folder %s has a space or %% in its path, which rpmbuild cannot handle: choose another\n' "$output" >&2
        exit 1
        ;;
esac
work="$(/usr/bin/mktemp -d "$output/rpms.XXXXXX")"
status=$?
if [ "$status" -ne 0 ] || [ -z "$work" ]; then
    printf 'Cannot make a work folder in %s\n' "$output" >&2
    exit 1
fi
/bin/mkdir -p "$work/runtime-root" "$work/engine-root" "$work/rpmdb" "$work/top"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot make the folders in %s\n' "$work" >&2
    exit 1
fi
for pair in "$runtime_deb:runtime-root" "$engine_deb:engine-root"; do
    /usr/bin/dpkg-deb -x "${pair%:*}" "$work/${pair##*:}"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot unpack %s\n' "${pair%:*}" >&2
        exit 1
    fi
done
runtime_folder="usr/lib/command-engine/swift-$runtime_version"
if [ ! -d "$work/runtime-root/$runtime_folder" ]; then
    printf 'No %s in %s\n' "$runtime_folder" "$runtime_deb" >&2
    exit 1
fi

# The runtime's own sonames: what its libraries need of each other is not a requirement
runtime_sonames=""
for library in "$work/runtime-root/$runtime_folder"/*.so*; do
    if [ -f "$library" ]; then
        runtime_sonames="$runtime_sonames ${library##*/}"
    fi
done
if [ -z "$runtime_sonames" ]; then
    printf 'No libraries in %s\n' "$runtime_deb" >&2
    exit 1
fi
exclude=""
for soname in $runtime_sonames; do
    escaped="$(printf '%s' "$soname" | /usr/bin/sed 's/[.+]/\\\\&/g')"
    if [ -n "$exclude" ]; then
        exclude="$exclude|$escaped"
    else
        exclude="$escaped"
    fi
done

# The engine's requires: the programs' NEEDED sonames that neither the runtime nor the bundle has
bundled=""
while IFS= read -r library; do
    bundled="$bundled ${library##*/}"
done < <(/usr/bin/find "$master" -name '*.so*' -type f)
needed=""
for program in "${programs[@]}"; do
    dynamic_section="$(/usr/bin/readelf -d -- "$program")"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'readelf could not read %s\n' "$program" >&2
        exit 1
    fi
    needed="$needed $(printf '%s\n' "$dynamic_section" | /usr/bin/sed -n 's/.*(NEEDED).*\[\(.*\)\]$/\1/p' | /usr/bin/tr '\n' ' ')"
done
requires=""
for soname in $(printf '%s\n' $needed | /usr/bin/sort -u); do
    case " $runtime_sonames $bundled " in
        *" $soname "*) continue ;;
    esac
    requires="${requires}Requires: ${soname}()(64bit)
"
done
if [ -z "$requires" ]; then
    printf 'The engine'"'"'s programs need no system library: something is wrong with %s\n' "$master" >&2
    exit 1
fi

/bin/cat > "$work/runtime.spec" <<SPEC
Name: command-engine-swift-$runtime_version
Version: $swift_version
Release: 1
Summary: Swift $runtime_version runtime libraries for Command Engine applets
License: Apache-2.0
AutoProv: no
%global __requires_exclude ^($exclude)
%global debug_package %{nil}
%global __strip /bin/true
%global __brp_strip /bin/true
%global __os_install_post %{nil}
# Two Swift runtime versions may hold identical library files (6.4 holding the 6.4.3 release beside an
# exact 6.4.3): no /usr/lib/.build-id links, which would clash between them
%global _build_id_links none

%description
The Swift runtime libraries, version $runtime_version, that Command Engine applets load, in
/$runtime_folder.

%install
/bin/mkdir -p %{buildroot}
/bin/cp -a $work/runtime-root/usr %{buildroot}/

%files
%dir /usr/lib/command-engine
/$runtime_folder
SPEC
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$work/runtime.spec" >&2
    exit 1
fi

/bin/cat > "$work/engine.spec" <<SPEC
Name: command-engine
Version: $engine_version
Release: 1
Summary: The system libraries Command Engine applets need
License: Proprietary
${requires}Requires: librsvg2
Requires: glib-networking
Requires: adwaita-icon-theme
Requires: python3
Requires: command-engine-swift-$runtime_version >= $swift_version-1
%global debug_package %{nil}

%description
Installs the system libraries every Command Engine applet uses (GTK 4, libadwaita, SVG icon
support, https) and the Swift $runtime_version runtime libraries they load, and command-engine-cleanup,
which removes the Swift runtime packages no applet uses. Applets themselves are bundles that run from any folder.

%install
/bin/mkdir -p %{buildroot}
/bin/cp -a $work/engine-root/usr $work/engine-root/var %{buildroot}/

%post
# More than one Swift runtime version installed: say how to remove the unused ones (rpm holds its database
# here, so the folders are counted, not the packages)
count=0
for folder in /usr/lib/command-engine/swift-*; do
    if [ -d "\$folder" ]; then
        count=\$((count + 1))
    fi
done
if [ "\$count" -gt 1 ]; then
    printf 'More than one Swift runtime for Command Engine applets is installed; "sudo command-engine-cleanup" removes the ones no applet uses (--list shows them).\n'
fi
exit 0

%files
/usr/share/doc/command-engine
%attr(0755,root,root) /usr/sbin/command-engine-cleanup
%dir /var/lib/command-engine
%attr(1777,root,root) %dir /var/lib/command-engine/applets
SPEC
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Cannot write %s\n' "$work/engine.spec" >&2
    exit 1
fi

for spec in runtime engine; do
    /usr/bin/rpmbuild --dbpath "$work/rpmdb" --define "_topdir $work/top" --target "$architecture-linux" -bb "$work/$spec.spec" > "$work/$spec-rpmbuild.log" 2>&1
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'rpmbuild of %s failed (status %s); its log: %s\n' "$spec" "$status" "$work/$spec-rpmbuild.log" >&2
        /usr/bin/tail -20 "$work/$spec-rpmbuild.log" >&2
        exit 1
    fi
done
runtime_rpm="command-engine-swift-$runtime_version-$swift_version-1.$architecture.rpm"
engine_rpm="command-engine-$engine_version-1.$architecture.rpm"
for rpm in "$runtime_rpm" "$engine_rpm"; do
    if [ ! -f "$work/top/RPMS/$architecture/$rpm" ]; then
        printf 'rpmbuild made no %s (see %s)\n' "$rpm" "$work/top/RPMS" >&2
        exit 1
    fi
    /bin/cp -- "$work/top/RPMS/$architecture/$rpm" "$output/$rpm"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Cannot copy %s into %s\n' "$rpm" "$output" >&2
        exit 1
    fi
done
/bin/rm -rf -- "$work"
printf 'Requires of command-engine:\n%s' "$requires"
printf 'The packages: %s %s\n' "$output/$runtime_rpm" "$output/$engine_rpm"
exit 0
