#!/bin/bash
# thin_distribution.sh
# single-arch thinning from universal binaries
# Usage: ./thin_distribution.sh --arch arm64|x86_64 /path/to/AppOrDir
#   Without arguments: prints this help.

set -euo pipefail

ARCH=""
BINARIES_DIR=""

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
Usage: $0 --arch arm64|x86_64 /path/to/AppOrDir

Thin all universal/fat Mach-O binaries in the distribution to single architecture.

Example:
  $0 --arch=arm64 ./OMCApplet.app

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
                if [[ -z "$BINARIES_DIR" ]]; then
                    BINARIES_DIR="$1"
                    shift
                fi
                ;;
        esac
    done

    if [ -z "$BINARIES_DIR" ] || [ ! -d "$BINARIES_DIR" ]; then
        show_help
    fi
    
    if [ -z "$ARCH" ]; then
        show_help
    fi
}

thin_to_single_arch() {
    local arch="$1"
    echo "Thinning all universal Mach-O files to $arch ..."
    
    # Collect all candidate binary files
    local executable_files=$(/usr/bin/find "$BINARIES_DIR" -type f \( -name '*.dylib' -o -name '*.so' -o -perm +111 \))

    local thinned=0
    local file
    
    # Process each candidate file
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        
        # Check if file is a universal Mach-O binary
        local file_info=$(/usr/bin/file "$file" 2>/dev/null)
        
        local is_universal=$(echo "$file_info" | /usr/bin/grep -c "Mach-O.*universal")
        
        if [ "$is_universal" -gt 0 ]; then
            echo "  Thinning: $file"
            local tmp="$file.thin.tmp"
            
            set +e
            /usr/bin/lipo -thin "$arch" "$file" -output "$tmp" 2>/dev/null
            local lipo_result=$?
            set -e
            
            if [ $lipo_result -eq 0 ]; then
                /bin/mv "$tmp" "$file"
                ((thinned++))
            else
                echo "    Warning: lipo -thin $arch failed on $file (arch possibly missing)"
                /bin/rm -f "$tmp"
            fi
        fi
    done <<< "$executable_files"
    
    echo "  Thinned $thinned files to $arch."
    echo
}

main() {
    parse_arguments "$@"
    
    local initial_size=$(calc_size "$BINARIES_DIR")
    echo "Current size of $BINARIES_DIR: $initial_size"
    echo

    if [[ -n "$ARCH" ]]; then
        thin_to_single_arch "$ARCH"
    fi

    local final_size=$(calc_size "$BINARIES_DIR")
    echo "Final size of $BINARIES_DIR: $final_size"
    echo
}

main "$@"
