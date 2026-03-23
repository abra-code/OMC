#!/bin/bash
# update_appletbuilder.sh - Sync bundled resources in AppletBuilder.app
#
# Updates:
#   1. mistune (markdown-to-HTML converter)
#   2. OMC documentation
#   3. ActionUI documentation (from SPM package)
#
# Run from OMC project root or provide OMC_ROOT as argument

set -e

OMC_ROOT="${1:-$(cd "$(dirname "$0")" && pwd)}"
APPLET_BUILDER="$OMC_ROOT/Distribution/AppletBuilder.app"
DEST_DOCS="$APPLET_BUILDER/Contents/Resources/Documentation"
DEST_MISTUNE="$APPLET_BUILDER/Contents/Library/mistune"

# ActionUI location: local checkout next to OMC (matches Xcode project reference)
ACTIONUI_ROOT="$OMC_ROOT/../ActionUI"
ACTIONUI_DOCS="$ACTIONUI_ROOT/Documentation"

OMC_DOCS="$OMC_ROOT/Documentation"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

updated=0

echo "Updating AppletBuilder resources..."
echo ""

# ════════════════════════════════════════════════════════════
# 1. Mistune
# ════════════════════════════════════════════════════════════

echo "── Checking mistune ──"

bundled_version=""
if [ -f "$DEST_MISTUNE/__init__.py" ]; then
    bundled_version=$(grep '__version__' "$DEST_MISTUNE/__init__.py" | sed 's/.*"\(.*\)".*/\1/')
fi
echo "  Bundled version: ${bundled_version:-not installed}"

# Check latest version from PyPI
latest_version=$(curl -s "https://pypi.org/pypi/mistune/json" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])" 2>/dev/null || echo "")

if [ -n "$latest_version" ]; then
    echo "  Latest on PyPI:  $latest_version"
    if [ "$bundled_version" != "$latest_version" ]; then
        echo -e "  ${YELLOW}Update available: $bundled_version → $latest_version${NC}"
        read -p "  Install mistune $latest_version? [y/N] " answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            tmp_dir=$(mktemp -d)
            pip3 install --target="$tmp_dir" --no-deps mistune=="$latest_version" 2>/dev/null
            if [ -d "$tmp_dir/mistune" ]; then
                rm -rf "$DEST_MISTUNE"
                cp -R "$tmp_dir/mistune" "$DEST_MISTUNE"
                # Clean up bytecode
                find "$DEST_MISTUNE" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
                echo -e "  ${GREEN}Updated mistune to $latest_version${NC}"
                updated=1
            else
                echo -e "  ${RED}Failed to download mistune${NC}"
            fi
            rm -rf "$tmp_dir"
        else
            echo "  Skipped"
        fi
    else
        echo -e "  ${GREEN}Up to date${NC}"
    fi
else
    echo -e "  ${YELLOW}Could not check PyPI (no network?)${NC}"
fi

echo ""

# ════════════════════════════════════════════════════════════
# 2. OMC Documentation
# ════════════════════════════════════════════════════════════

echo "── Checking OMC documentation ──"

# Copy all files from OMC/Documentation to AppletBuilder
omc_updated=0
for src in "$OMC_DOCS"/*; do
    [ ! -f "$src" ] && continue
    name=$(basename "$src")
    dst="$DEST_DOCS/$name"
    if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" > /dev/null 2>&1; then
        cp "$src" "$dst"
        echo -e "  ${GREEN}Updated: $name${NC}"
        omc_updated=1
        updated=1
    fi
done

if [ "$omc_updated" -eq 0 ]; then
    echo -e "  ${GREEN}All OMC docs up to date${NC}"
fi

echo ""

# ════════════════════════════════════════════════════════════
# 3. ActionUI Documentation (from SPM package)
# ════════════════════════════════════════════════════════════

echo "── Checking ActionUI documentation ──"

if [ ! -d "$ACTIONUI_DOCS" ]; then
    echo -e "  ${RED}ActionUI Documentation not found at: $ACTIONUI_DOCS${NC}"
    echo "  Expected ActionUI checkout at: $ACTIONUI_ROOT"
    echo ""
else
    # Files to copy from ActionUI Documentation
    actionui_doc_files=(
        "ActionUI-JSON-Guide.md"
        "ActionUI-Elements.md"
    )

    actionui_updated=0

    # Copy top-level doc files
    for doc in "${actionui_doc_files[@]}"; do
        src="$ACTIONUI_DOCS/$doc"
        dst="$DEST_DOCS/$doc"
        if [ ! -f "$src" ]; then
            echo -e "  ${YELLOW}Source missing: $doc${NC}"
            continue
        fi
        if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" > /dev/null 2>&1; then
            cp "$src" "$dst"
            echo -e "  ${GREEN}Updated: $doc${NC}"
            actionui_updated=1
            updated=1
        fi
    done

    # Copy Schemas directory
    if [ -d "$ACTIONUI_DOCS/Schemas" ]; then
        schemas_changed=0
        mkdir -p "$DEST_DOCS/Schemas"
        for src in "$ACTIONUI_DOCS/Schemas"/*; do
            [ ! -f "$src" ] && continue
            name=$(basename "$src")
            dst="$DEST_DOCS/Schemas/$name"
            if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" > /dev/null 2>&1; then
                cp "$src" "$dst"
                schemas_changed=1
            fi
        done
        # Remove files in dest that no longer exist in source
        for dst in "$DEST_DOCS/Schemas"/*; do
            [ ! -f "$dst" ] && continue
            name=$(basename "$dst")
            if [ ! -f "$ACTIONUI_DOCS/Schemas/$name" ]; then
                rm "$dst"
                schemas_changed=1
            fi
        done
        if [ "$schemas_changed" -eq 1 ]; then
            echo -e "  ${GREEN}Updated: Schemas/${NC}"
            actionui_updated=1
            updated=1
        fi
    fi

    # Copy Elements directory
    if [ -d "$ACTIONUI_DOCS/Elements" ]; then
        elements_changed=0
        mkdir -p "$DEST_DOCS/Elements"
        for src in "$ACTIONUI_DOCS/Elements"/*; do
            [ ! -f "$src" ] && continue
            name=$(basename "$src")
            dst="$DEST_DOCS/Elements/$name"
            if [ ! -f "$dst" ] || ! diff -q "$src" "$dst" > /dev/null 2>&1; then
                cp "$src" "$dst"
                elements_changed=1
            fi
        done
        # Remove files in dest that no longer exist in source
        for dst in "$DEST_DOCS/Elements"/*; do
            [ ! -f "$dst" ] && continue
            name=$(basename "$dst")
            if [ ! -f "$ACTIONUI_DOCS/Elements/$name" ]; then
                rm "$dst"
                elements_changed=1
            fi
        done
        if [ "$elements_changed" -eq 1 ]; then
            echo -e "  ${GREEN}Updated: Elements/${NC}"
            actionui_updated=1
            updated=1
        fi
    fi

    if [ "$actionui_updated" -eq 0 ]; then
        echo -e "  ${GREEN}All ActionUI docs up to date${NC}"
    fi
fi

echo ""

# ════════════════════════════════════════════════════════════
# 4. Validate ElementTemplates.json against Elements/
# ════════════════════════════════════════════════════════════

echo "── Validating element templates ──"

TEMPLATES_JSON="$APPLET_BUILDER/Contents/Resources/Base.lproj/ElementTemplates.json"
ELEMENTS_DIR="$DEST_DOCS/Elements"
template_errors=0

if [ -f "$TEMPLATES_JSON" ] && [ -d "$ELEMENTS_DIR" ]; then
    # Extract tags from ElementTemplates.json
    template_tags=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    items = json.load(f)
tags = sorted(set(item['tag'] for item in items if 'tag' in item))
for t in tags:
    print(t)
" "$TEMPLATES_JSON")

    # Check each tag has a matching .json file in Elements/
    while IFS= read -r tag; do
        if [ ! -f "$ELEMENTS_DIR/${tag}.json" ]; then
            echo -e "  ${RED}ElementTemplates.json references '${tag}' but Elements/${tag}.json does not exist${NC}"
            template_errors=1
        fi
    done <<< "$template_tags"

    # Check each .json file in Elements/ has a matching tag
    for element_file in "$ELEMENTS_DIR"/*.json; do
        [ ! -f "$element_file" ] && continue
        element_name=$(basename "$element_file" .json)
        if ! echo "$template_tags" | grep -qx "$element_name"; then
            echo -e "  ${RED}Elements/${element_name}.json exists but is not listed in ElementTemplates.json${NC}"
            template_errors=1
        fi
    done

    if [ "$template_errors" -eq 1 ]; then
        echo -e "  ${RED}ElementTemplates.json is out of sync with Elements/ directory${NC}"
        echo "  Update: $TEMPLATES_JSON"
        exit 1
    else
        echo -e "  ${GREEN}ElementTemplates.json is in sync with Elements/${NC}"
    fi
else
    if [ ! -f "$TEMPLATES_JSON" ]; then
        echo -e "  ${YELLOW}ElementTemplates.json not found${NC}"
    fi
    if [ ! -d "$ELEMENTS_DIR" ]; then
        echo -e "  ${YELLOW}Elements/ directory not found${NC}"
    fi
fi

echo ""

# ════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════

if [ "$updated" -eq 1 ]; then
    echo -e "${GREEN}AppletBuilder resources updated.${NC}"
    echo "Clearing /tmp/appletbuilder_help/ to regenerate HTML help files."
    rm -rf /tmp/appletbuilder_help 2>/dev/null || true
else
    echo "Everything is up to date."
fi
