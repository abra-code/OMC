#!/bin/bash
# thin_python_distribution.sh
# Optional thinning of a relocatable Python + optional single-arch slicing.
# Usage: ./thin_python_distribution.sh [--arch arm64|x86_64] /path/to/Python [component1 component2 ...]
#   Without arguments: prints this help.

set -uo pipefail

ARCH=""
PYTHON_DIR=""
COMPONENTS=()

calc_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        /usr/bin/du -shk "$dir" | /usr/bin/cut -f1 | /usr/bin/awk '{printf "%.2f MB\n", $1/1024}'
    else
        echo "0B"
    fi
}

show_help() {
    cat <<HELP
Usage: $0 [--arch arm64|x86_64] /path/to/Python [component1 component2 ...]

Removes potentially unneeded components (pure-Python modules + extensions).
The main build script already removes always-unneeded parts (tkinter, test suite, ensurepip, venv, etc.).

If --arch is given, thins ALL universal/fat Mach-O binaries in the distribution to single architecture.

Common optional removals (verify your app/scripts do not need them):

  ssl             - TLS/HTTPS support (~4MB _ssl.so + ssl.py)
  hashlib         - Accelerated modern crypto hashes (SHA3, BLAKE2, etc.; ~3MB _hashlib.so + hashlib.py)
  sqlite3         - SQLite database support (~1MB _sqlite3.so + sqlite3/ dir)
  curses          - Terminal handling (ncurses bindings); rarely used in GUI/desktop apps (~170KB _curses*.so + curses/ dir)
  xml             - XML parsers (dom/sax/etree); sizable if unused (~448KB + pyexpat.so)
  dbm             - Simple key-value databases (~36KB + _dbm/_gdbm.so)
  decimal         - High-precision decimal arithmetic (~353KB _decimal.so + decimal.py)
  ctypes          - Foreign function interface (calls C libraries; ~186KB _ctypes.so + ctypes/ dir)
  multiprocessing - Parallel execution (~408KB multiprocessing/ dir)
  unittest        - Testing framework (~284KB unittest/ dir)
  xmlrpc          - XML-RPC client/server (deprecated; ~88KB xmlrpc/ dir)
  pip             - Package manager (~20-30MB with deps) - also removes universalPip/uPip if installed
  setuptools      - Packaging tools
  certifi         - CA certificate bundle (breaks HTTPS verification if removed)
  include         - "include" headers for building some modules (not needed in sealed Python package)
  pyc             - all __pycache__ dirs + *.pyc / *.pyo files (useful after pip install)
  dist-info       - pip metadata directories (*.dist-info; created by pip install)

  codecs_east_asian - East-Asian text encodings (_codecs_jp/cn/hk/kr/tw.so; ~800KB total)

Any unknown component name is treated generically: removes matching directory, .py file, and related *.so extensions if found.

Note: Removing ssl/hashlib breaks HTTPS and modern crypto.
      Removing certifi breaks SSL certificate verification.

Example:
  $0 --arch=arm64 ./Python-3.14.2-universal ssl hashlib sqlite3 pip pyc
  $0 ./Python-3.14.2-arm64 xml curses decimal pyc

HELP
    exit 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --arch=*)
                ARCH="${1#*=}"
                if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
                    echo "Error: --arch must be 'arm64' or 'x86_64'"
                    exit 1
                fi
                shift
                ;;
            --arch)
                ARCH="$2"
                if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
                    echo "Error: --arch must be 'arm64' or 'x86_64'"
                    exit 1
                fi
                shift 2
                ;;
            *)
                if [[ -z "$PYTHON_DIR" ]]; then
                    PYTHON_DIR="$1"
                    shift
                else
                    # Remaining arguments are components
                    COMPONENTS+=("$1")
                    shift
                fi
                ;;
        esac
    done

    if [ -z "$PYTHON_DIR" ] || [ ! -d "$PYTHON_DIR" ]; then
        show_help
    fi
}

thin_to_single_arch() {
    local arch="$1"
    echo "Thinning all universal Mach-O files to $arch ..."
    
    # Collect all candidate binary files
    local executable_files=$(/usr/bin/find "$PYTHON_DIR" -type f \( -name '*.dylib' -o -name '*.so' -o -perm -u+x \))

    local thinned=0
    local failed=0
    local file
    
    # Process each candidate file
    while IFS= read -r file; do
        [ -z "$file" ] && continue

        local file_info=$(/usr/bin/file "$file" 2>/dev/null)

        local is_universal=$(echo "$file_info" | /usr/bin/grep -c "Mach-O.*universal")

        if [ "$is_universal" -gt 0 ]; then
            echo "  Thinning: $file"
            local tmp="$file.thin.tmp"

            /usr/bin/lipo -thin "$arch" "$file" -output "$tmp" 2>/dev/null
            local lipo_result=$?

            if [ $lipo_result -eq 0 ]; then
                # Checked, and counted only when it took: an unchecked mv left the
                # binary universal, left the .tmp beside it, and printed nothing, so
                # a caller saw a clean run over a file it had not thinned.
                /bin/mv "$tmp" "$file"
                local mv_result=$?
                if [ $mv_result -eq 0 ]; then
                    thinned=$((thinned + 1))
                else
                    echo "    Warning: lipo -thin $arch could not replace $file (mv exit $mv_result)"
                    /bin/rm -f "$tmp"
                    failed=$((failed + 1))
                fi
            else
                echo "    Warning: lipo -thin $arch failed on $file (arch possibly missing)"
                /bin/rm -f "$tmp"
                failed=$((failed + 1))
            fi
        fi
    done <<< "$executable_files"
    
    echo "  Thinned $thinned files to $arch."
    echo

    # A slice that could not be made is a FAILURE, not a note in passing. The caller
    # deletes the backup and reports success on this status, and a plan recording
    # arch: <x> would then describe a distribution that still carries both.
    if [ "$failed" -gt 0 ]; then
        echo "  $failed file(s) could not be thinned to $arch."
        return 1
    fi
    return 0
}

remove_component() {
    local comp="$1"
    local lib_dir="$2"
    local dynload="$3"
    local site_pkgs="$4"
    local removed=false
    
    echo "Processing component: $comp"

    # Remove all pyc precompiled objects
    if [[ "$comp" == "pyc" ]]; then
        echo "  Removing all __pycache__ directories and *.pyc/*.pyo files"
        /usr/bin/find "$PYTHON_DIR" -type d -name "__pycache__" -exec /bin/rm -rf {} +
        /usr/bin/find "$PYTHON_DIR" -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
        echo "  Bytecode cleanup complete."
        echo
        return
    fi

    # Remove include headers dir
    if [[ "$comp" == "include" ]]; then
        echo "  Removing $PYTHON_DIR/include"
        /bin/rm -rf "$PYTHON_DIR/include"
        echo
        return
    fi

    # Remove dist-info directories
    if [[ "$comp" == "dist-info" ]]; then
        local dist_info_dirs=$(/usr/bin/find "$PYTHON_DIR" -type d -name "*-*.dist-info" 2>/dev/null || echo "")
        if [ -n "$dist_info_dirs" ]; then
            local dir
            while IFS= read -r dir; do
                [ -z "$dir" ] && continue
                echo "  Removing dist-info: $dir"
                /bin/rm -rf "$dir"
            done <<< "$dist_info_dirs"
        fi
        echo
        return
    fi

    # Remove pydoc_data
    if [[ "$comp" == "pydoc" ]]; then
        if [ -d "$lib_dir/pydoc_data" ]; then
            echo "  Removing $lib_dir/pydoc_data"
            /bin/rm -rf "$lib_dir/pydoc_data"
            removed=true
        fi
    fi

    # Remove hashlib-related .so files (blake2, sha, md5, hmac)
    if [[ "$comp" == "hashlib" ]]; then
        local hashlib_removed=false
        local hashlib_so
        for hashlib_so in _blake2 _sha1 _sha2 _sha3 _md5 _hmac; do
            local so_file="$dynload/${hashlib_so}.cpython-314-darwin.so"
            if [ -f "$so_file" ]; then
                echo "  Removing: $so_file"
                /bin/rm -f "$so_file"
                hashlib_removed=true
            fi
        done
        if $hashlib_removed; then
            removed=true
        fi
    fi

    # Remove xml-related .so files (elementtree, pyexpat)
    if [[ "$comp" == "xml" ]]; then
        local xml_removed=false
        if [ -f "$dynload/_elementtree.cpython-314-darwin.so" ]; then
            echo "  Removing: $dynload/_elementtree.cpython-314-darwin.so"
            /bin/rm -f "$dynload/_elementtree.cpython-314-darwin.so"
            xml_removed=true
        fi
        if [ -f "$dynload/pyexpat.cpython-314-darwin.so" ]; then
            echo "  Removing: $dynload/pyexpat.cpython-314-darwin.so"
            /bin/rm -f "$dynload/pyexpat.cpython-314-darwin.so"
            xml_removed=true
        fi
        if $xml_removed; then
            removed=true
        fi
    fi

    # Remove _lsprof.cpython-314-darwin.so (profiling)
    if [[ "$comp" == "lsprof" ]]; then
        if [ -f "$dynload/_lsprof.cpython-314-darwin.so" ]; then
            echo "  Removing: $dynload/_lsprof.cpython-314-darwin.so"
            /bin/rm -f "$dynload/_lsprof.cpython-314-darwin.so"
            removed=true
        fi
    fi

    # Remove _statistics.cpython-314-darwin.so (statistics module)
    if [[ "$comp" == "statistics" ]]; then
        if [ -f "$dynload/_statistics.cpython-314-darwin.so" ]; then
            echo "  Removing: $dynload/_statistics.cpython-314-darwin.so"
            /bin/rm -f "$dynload/_statistics.cpython-314-darwin.so"
            removed=true
        fi
    fi

    # Remove East Asian codecs
    if [[ "$comp" == "codecs_east_asian" ]]; then
        local codec
        for codec in jp cn hk kr tw; do
            local codec_files
            codec_files=$(/usr/bin/find "$dynload" -maxdepth 1 -name "_codecs_${codec}*.so" 2>/dev/null || echo "")
            
            if [ -n "$codec_files" ]; then
                local codec_file
                while IFS= read -r codec_file; do
                    [ -z "$codec_file" ] && continue
                    echo "  Removing East-Asian codec extension: $codec_file"
                    /bin/rm -f "$codec_file"
                    removed=true
                done <<< "$codec_files"
            fi
        done
        
        if ! $removed; then
            echo "  No East-Asian codec extensions found."
        fi
        echo
        return
    fi

    # General component removal

    # Remove directory
    if [ -d "$lib_dir/$comp" ]; then
        echo "  Removing directory: $lib_dir/$comp"
        /bin/rm -rf "$lib_dir/$comp"
        removed=true
    fi

    # Remove .py file
    if [ -f "$lib_dir/${comp}.py" ]; then
        echo "  Removing module file: $lib_dir/${comp}.py"
        /bin/rm -f "$lib_dir/${comp}.py"
        removed=true
    fi

    # Remove related extensions
    local so_files=$(/usr/bin/find "$dynload" -maxdepth 1 -name "*${comp}*.so" 2>/dev/null || echo "")
    
    if [ -n "$so_files" ]; then
        local so_file
        while IFS= read -r so_file; do
            [ -z "$so_file" ] && continue
            echo "  Removing extension: $so_file"
            /bin/rm -f "$so_file"
            removed=true
        done <<< "$so_files"
    fi

    # Handle site-packages (for packages installed via pip)
    local site_items=$(/usr/bin/find "$site_pkgs" -maxdepth 1 -name "${comp}*" 2>/dev/null || echo "")
    
    if [ -n "$site_items" ]; then
        local item
        while IFS= read -r item; do
            [ -z "$item" ] && continue
            echo "  Removing site-packages item: $item"
            /bin/rm -rf "$item"
            removed=true
        done <<< "$site_items"
    fi
    
    # Special: if removing pip, also remove universalPip (installed conditionally in build)
    if [[ "$comp" == "pip" ]]; then
        local upip_items=$(/usr/bin/find "$site_pkgs" -maxdepth 1 -name "universalPip*" -o -name "uPip*" 2>/dev/null || echo "")
        if [ -n "$upip_items" ]; then
            local item
            while IFS= read -r item; do
                [ -z "$item" ] && continue
                echo "  Removing universalPip/uPip: $item (removed with pip)"
                /bin/rm -rf "$item"
                removed=true
            done <<< "$upip_items"
        fi
    fi

    # Handle SSL-specific cleanup
    if [[ "$comp" == "ssl" ]]; then
        if [ -f "$PYTHON_DIR/lib/libssl.dylib" ]; then
            echo "  Removing libssl.dylib"
            /bin/rm -f "$PYTHON_DIR/lib/libssl.dylib"
            removed=true
        fi
    fi

    if ! $removed; then
        echo "  No matching files found for '$comp'"
    fi
    echo
}

remove_bin_scripts_for_component() {
    local comp="$1"
    local bin_dir="${PYTHON_DIR}/bin"
    
    if [ ! -d "$bin_dir" ]; then
        return
    fi
    
    # Special case: uPip is removed when pip is removed
    if [[ "$comp" == "pip" ]]; then
        if [ -e "$bin_dir/uPip" ]; then
            echo "  Removing bin script: uPip"
            /bin/rm -f "$bin_dir/uPip"
        fi
    fi
    
    # Get all files (excluding python*)
    local files=$(/usr/bin/find "$bin_dir" -maxdepth 1 -type f ! -name "python*" 2>/dev/null || echo "")
    # Get all symlinks (excluding python*)
    local symlinks=$(/usr/bin/find "$bin_dir" -maxdepth 1 -type l ! -name "python*" 2>/dev/null || echo "")
    
    # First pass: process actual files
    local file
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        
        local file_name=$(basename "$file")
        
        # Skip files without shebang
        local first_bytes=$(/usr/bin/head -c 2 "$file" 2>/dev/null || echo "")
        if [ "$first_bytes" != "#!" ]; then
            continue
        fi
        
        # Check if script imports the component
        local import_lines=$(/usr/bin/grep -E "^import |^from .* import" "$file" 2>/dev/null || echo "")
        
        if [ -n "$import_lines" ]; then
            local has_comp=$(/usr/bin/grep -qw "${comp}" <<< "$import_lines" && echo "yes" || echo "no")
            if [ "$has_comp" = "yes" ]; then
                echo "  Removing bin script: $file_name"
                /bin/rm -f "$file"
            fi
        fi
    done <<< "$files"
    
    # Second pass: clean up symlinks (now that target files may be removed)
    local link
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        
        local link_name=$(basename "$link")
        local target=$(/usr/bin/readlink "$link" 2>/dev/null || echo "")
        local link_dir=$(dirname "$link")
        
        # Remove broken symlinks (target doesn't exist)
        (cd "$link_dir" && [ ! -e "$target" ])
        if [ $? -eq 0 ]; then
            echo "  Removing broken symlink: $link_name -> $target"
            /bin/rm -f "$link"
        fi
    done <<< "$symlinks"
}

check_and_remove_libcrypto() {
    local components=("$@")
    
    # Check if BOTH ssl and hashlib are being removed
    local removing_ssl=false
    local removing_hashlib=false
    local comp
    for comp in "${components[@]}"; do
        if [[ "$comp" == "ssl" ]]; then
            removing_ssl=true
        elif [[ "$comp" == "hashlib" ]]; then
            removing_hashlib=true
        fi
    done
    
    # Only remove libcrypto if both ssl and hashlib are being removed
    if $removing_ssl && $removing_hashlib; then
        if [ -f "$PYTHON_DIR/lib/libcrypto.dylib" ]; then
            echo "Removing libcrypto.dylib (both ssl and hashlib removed)"
            /bin/rm -f "$PYTHON_DIR/lib/libcrypto.dylib"
            echo
        fi
    fi
}

thin_components() {
    local components=("$@")
    local lib_dir=$(echo "${PYTHON_DIR}/lib/python"*)
    local site_pkgs="${lib_dir}/site-packages"
    local dynload="${lib_dir}/lib-dynload"
    
    echo "Thinning $PYTHON_DIR"
    echo
    
    local comp
    for comp in "${components[@]}"; do
        remove_component "$comp" "$lib_dir" "$dynload" "$site_pkgs"
        remove_bin_scripts_for_component "$comp"
    done
    
    check_and_remove_libcrypto "${components[@]}"
}

verify_no_broken_symlinks() {
    echo "Verifying no broken symlinks exist..."
    
    local broken_links=()
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        local target=$(/usr/bin/readlink "$link")
        local link_dir=$(dirname "$link")
        (cd "$link_dir" && [ ! -e "$target" ])
        if [ $? -eq 0 ]; then
            broken_links=("${broken_links[@]}" "$link")
        fi
    done < <(/usr/bin/find "$PYTHON_DIR" -type l 2>/dev/null || echo "")
    
    if [ ${#broken_links[@]} -gt 0 ]; then
        echo "  Found broken symlinks:"
        local link
        for link in "${broken_links[@]}"; do
            local target=$(/usr/bin/readlink "$link" 2>/dev/null || echo "?")
            echo "    $link -> $target"
        done
        echo
        echo "  ERROR: Broken symlinks found - this will cause Gatekeeper to reject the app"
        echo "  Please report this bug with details of which component caused this."
        exit 1
    fi
    
    echo "  No broken symlinks found."
    echo
}

main() {
    parse_arguments "$@"
    
    local initial_size=$(calc_size "$PYTHON_DIR")
    echo "Current size of $PYTHON_DIR: $initial_size"
    echo
        
    # Perform component removal if any components specified.
    #
    # Its status is folded into the return below, but be aware of what that is worth
    # today: remove_component reports a failed removal by echo and returns bare, and
    # thin_components ends on check_and_remove_libcrypto, so the only non-zero this
    # can currently carry is a hard error before any component is touched. A caller
    # that needs "the pyc really came out" cannot get it from this status yet.
    local comp_result=0
    if [ ${#COMPONENTS[@]} -gt 0 ]; then
        thin_components "${COMPONENTS[@]}"
        comp_result=$?
    fi

    # Perform architecture thinning if requested
    local arch_result=0
    if [[ -n "$ARCH" ]]; then
        thin_to_single_arch "$ARCH"
        arch_result=$?
    fi

    local final_size=$(calc_size "$PYTHON_DIR")
    echo "Final size of $PYTHON_DIR: $final_size"
    echo

    # Reported after the sizes, so the transcript still shows what the run did, but
    # reported: a caller that deletes its backup on a zero exit would otherwise call
    # a half-sliced distribution a success.
    if [ "$arch_result" -ne 0 ] || [ "$comp_result" -ne 0 ]; then
        return 1
    fi
    return 0
}

main "$@"
exit $?
