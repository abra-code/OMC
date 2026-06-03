#!/bin/bash
# lib.help.sh - Help documentation (Markdown -> HTML) for AppletBuilder
#
# Sources lib.common.sh for: python3

[ -n "$__LIB_HELP_SH" ] && return 0
__LIB_HELP_SH=1

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

HELP_HTML_DIR="/tmp/appletbuilder_help"

ensure_help_docs_converted() {
    local docs_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Documentation"
    local html_dir="$HELP_HTML_DIR"
    local needs_convert=0

    if [ ! -d "$html_dir" ]; then
        needs_convert=1
    else
        for src in "$docs_dir"/*.md "$docs_dir"/Schemas/*.md "$docs_dir"/Elements/*.json; do
            [ ! -f "$src" ] && continue
            local rel="${src#$docs_dir/}"
            local out
            case "$src" in
                *.md) out="$html_dir/${rel%.md}.html" ;;
                *)    out="$html_dir/$rel" ;;
            esac
            if [ ! -f "$out" ] || [ "$src" -nt "$out" ]; then
                needs_convert=1
                break
            fi
        done
    fi

    if [ "$needs_convert" -eq 1 ]; then
        "$python3" "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/md2html.py" --dir "$docs_dir" "$html_dir"
    fi
}
