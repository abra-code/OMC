#!/bin/bash
# update_appletbuilder.sh - Sync bundled resources in AppletBuilder.app
#
# Updates:
#   0. OMCApplet — builds universal (arm64 + x86_64) Release binary and Abracode.framework
#   1. ActionUI products (ActionUIViewer, ActionUIVerifier, ActionUIDocumentation) — built from SPM
#   2. mistune (markdown-to-HTML converter)
#   3. OMC documentation
#   4. ActionUI documentation (from built ActionUIDocumentation bundle)
#   5. Validates ElementTemplates.json against Elements/
#   6. Codesigns AppletBuilder.app (ad-hoc)
#
# Usage:
#   ./update_appletbuilder.sh [OMC_ROOT]
#   ./update_appletbuilder.sh --github [OMC_ROOT]
#
# Options:
#   --github    Clone ActionUI from github.com/abra-code/ActionUI
#               instead of using a local checkout next to OMC

# Parse options
USE_GITHUB=0
while [[ "$1" == --* ]]; do
    case "$1" in
        --github) USE_GITHUB=1; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

OMC_ROOT="${1:-$(cd "$(/usr/bin/dirname "$0")" && pwd)}"
APPLET_BUILDER="$OMC_ROOT/Distribution/AppletBuilder.app"
DEST_DOCS="$APPLET_BUILDER/Contents/Resources/Documentation"
DEST_MISTUNE="$APPLET_BUILDER/Contents/Library/mistune"
DEST_HELPERS="$APPLET_BUILDER/Contents/Helpers"
ACTIONUI_BUILD="$OMC_ROOT/.build/ActionUI"

if [ "$USE_GITHUB" -eq 1 ]; then
    ACTIONUI_ROOT="$OMC_ROOT/.build/ActionUI-source"
else
    # Local checkout next to OMC (matches Xcode project reference)
    ACTIONUI_ROOT="$OMC_ROOT/../ActionUI"
fi

ACTIONUI_DOCS="$ACTIONUI_ROOT/Documentation"
OMC_DOCS="$OMC_ROOT/Documentation"
OMC_WORKSPACE="$OMC_ROOT/OMC.xcworkspace"
OMCAPPLET_BUILD="$OMC_ROOT/.build/OMCApplet"
CODESIGN_SCRIPT="$OMC_ROOT/Distribution/Scripts/codesign_applet.sh"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Helper: compare two files, returns 0 if identical
files_match() {
    [ -f "$2" ] && /usr/bin/diff -q "$1" "$2" > /dev/null 2>&1
}

updated=0

echo "Updating AppletBuilder resources..."
echo ""

# ════════════════════════════════════════════════════════════
# 0. Build OMCApplet — Abracode.framework + binary (universal)
# ════════════════════════════════════════════════════════════

echo "── Building OMCApplet (universal) ──"

if [ ! -d "$OMC_WORKSPACE" ]; then
    echo -e "  ${RED}OMC workspace not found at: $OMC_WORKSPACE${NC}"
    exit 1
fi

echo "  Running xcodebuild..."
build_log_file=$(/usr/bin/mktemp)
/usr/bin/xcodebuild \
    -workspace "$OMC_WORKSPACE" \
    -scheme "OMC Distribution" \
    -configuration Release \
    -derivedDataPath "$OMCAPPLET_BUILD" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build > "$build_log_file" 2>&1
xcode_rc=$?

if [ "$xcode_rc" -ne 0 ]; then
    echo -e "  ${RED}OMCApplet build failed:${NC}"
    /bin/cat "$build_log_file"
    /bin/rm -f "$build_log_file"
    exit 1
fi
/bin/rm -f "$build_log_file"

OMCAPPLET_APP="$OMCAPPLET_BUILD/Build/Products/Release/OMCApplet.app"
if [ ! -d "$OMCAPPLET_APP" ]; then
    echo -e "  ${RED}Build succeeded but OMCApplet.app not found at: $OMCAPPLET_APP${NC}"
    exit 1
fi

# Copy Abracode.framework (built standalone alongside the app)
src_fw="$OMCAPPLET_BUILD/Build/Products/Release/Abracode.framework"
# Fall back to the copy embedded inside the app if the standalone isn't present
if [ ! -d "$src_fw" ]; then
    src_fw="$OMCAPPLET_APP/Contents/Frameworks/Abracode.framework"
fi
dst_fw="$APPLET_BUILDER/Contents/Frameworks/Abracode.framework"

if [ ! -d "$src_fw" ]; then
    echo -e "  ${RED}Abracode.framework not found in build output: $src_fw${NC}"
    exit 1
fi

/bin/rm -rf "$dst_fw"
/bin/cp -Rp "$src_fw" "$dst_fw"
echo -e "  ${GREEN}Updated: Abracode.framework${NC}"
updated=1

# Copy OMCApplet binary → AppletBuilder binary
src_bin="$OMCAPPLET_APP/Contents/MacOS/OMCApplet"
dst_bin="$APPLET_BUILDER/Contents/MacOS/AppletBuilder"

if [ ! -f "$src_bin" ]; then
    echo -e "  ${RED}OMCApplet binary not found: $src_bin${NC}"
    exit 1
fi

/bin/cp -p "$src_bin" "$dst_bin"
echo -e "  ${GREEN}Updated: MacOS/AppletBuilder (from OMCApplet binary)${NC}"
updated=1

echo ""

# ════════════════════════════════════════════════════════════
# 1. ActionUI Tools (build from SPM)
# ════════════════════════════════════════════════════════════

echo "── Building ActionUI tools ──"

if [ "$USE_GITHUB" -eq 1 ]; then
    if [ -d "$ACTIONUI_ROOT/.git" ]; then
        echo "  Updating ActionUI from GitHub..."
        /usr/bin/git -C "$ACTIONUI_ROOT" pull --quiet
    else
        echo "  Cloning ActionUI from GitHub..."
        /bin/mkdir -p "$(/usr/bin/dirname "$ACTIONUI_ROOT")"
        /usr/bin/git clone --quiet https://github.com/abra-code/ActionUI.git "$ACTIONUI_ROOT"
    fi
fi

if [ ! -d "$ACTIONUI_ROOT" ]; then
    echo -e "  ${RED}ActionUI not found at: $ACTIONUI_ROOT${NC}"
    if [ "$USE_GITHUB" -eq 0 ]; then
        echo "  Expected ActionUI checkout next to OMC"
        echo "  Or use --github to clone from GitHub"
    fi
    echo ""
else
    build_failed=0
    ACTIONUI_BUILD_ARM64="$ACTIONUI_BUILD/arm64"
    ACTIONUI_BUILD_X86="$ACTIONUI_BUILD/x86_64"

    # Executable products — built as universal binaries
    actionui_products=(ActionUIViewer ActionUIVerifier)

    for product in "${actionui_products[@]}"; do
        echo "  Building $product (universal)..."

        # Build for arm64
        /usr/bin/xcrun swift build --package-path "$ACTIONUI_ROOT" --scratch-path "$ACTIONUI_BUILD_ARM64" \
            --product "$product" --configuration release --arch arm64 2>/dev/null
        rc=$?
        if [ "$rc" -ne 0 ]; then
            echo -e "  ${RED}Failed to build $product (arm64)${NC}"
            build_failed=1
            continue
        fi

        # Build for x86_64
        /usr/bin/xcrun swift build --package-path "$ACTIONUI_ROOT" --scratch-path "$ACTIONUI_BUILD_X86" \
            --product "$product" --configuration release --arch x86_64 2>/dev/null
        rc=$?
        if [ "$rc" -ne 0 ]; then
            echo -e "  ${RED}Failed to build $product (x86_64)${NC}"
            build_failed=1
            continue
        fi

        # Create universal binary with lipo
        universal="$ACTIONUI_BUILD/$product"
        /usr/bin/lipo -create \
            "$ACTIONUI_BUILD_ARM64/release/$product" \
            "$ACTIONUI_BUILD_X86/release/$product" \
            -output "$universal"

        dst="$DEST_HELPERS/$product"
        if files_match "$universal" "$dst"; then
            echo -e "  ${GREEN}$product up to date${NC}"
        else
            /bin/mkdir -p "$DEST_HELPERS"
            /bin/cp "$universal" "$dst"
            echo -e "  ${GREEN}Updated: $product${NC}"
            updated=1
        fi
    done

    # Documentation bundle — built with the arm64 build (resources only, no arch dependency)
    echo "  Building ActionUIDocumentation..."
    /usr/bin/xcrun swift build --package-path "$ACTIONUI_ROOT" --scratch-path "$ACTIONUI_BUILD_ARM64" \
        --product ActionUIDocumentation --configuration release --arch arm64 2>/dev/null
    rc=$?
    if [ "$rc" -eq 0 ]; then
        # Find the built bundle
        ACTIONUI_DOC_BUNDLE=$(/usr/bin/find "$ACTIONUI_BUILD_ARM64" -name "ActionUI_ActionUIDocumentation.bundle" -type d 2>/dev/null | /usr/bin/head -1)
        if [ -n "$ACTIONUI_DOC_BUNDLE" ] && [ -d "$ACTIONUI_DOC_BUNDLE" ]; then
            ACTIONUI_DOCS="$ACTIONUI_DOC_BUNDLE"
            echo -e "  ${GREEN}ActionUIDocumentation built${NC}"
        else
            echo -e "  ${RED}ActionUIDocumentation bundle not found after build${NC}"
            build_failed=1
        fi
    else
        echo -e "  ${RED}Failed to build ActionUIDocumentation${NC}"
        build_failed=1
    fi

    if [ "$build_failed" -eq 1 ]; then
        echo -e "  ${RED}Some ActionUI products failed to build${NC}"
        exit 1
    fi
fi

echo ""

# ════════════════════════════════════════════════════════════
# 2. Mistune
# ════════════════════════════════════════════════════════════

echo "── Checking mistune ──"

bundled_version=""
if [ -f "$DEST_MISTUNE/__init__.py" ]; then
    bundled_version=$(/usr/bin/grep '__version__' "$DEST_MISTUNE/__init__.py" | /usr/bin/sed 's/.*"\(.*\)".*/\1/')
fi
echo "  Bundled version: ${bundled_version:-not installed}"

# Check latest version from PyPI
latest_version=$(/usr/bin/curl -s "https://pypi.org/pypi/mistune/json" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['info']['version'])" 2>/dev/null || echo "")

if [ -n "$latest_version" ]; then
    echo "  Latest on PyPI:  $latest_version"
    if [ "$bundled_version" != "$latest_version" ]; then
        echo -e "  ${YELLOW}Update available: $bundled_version → $latest_version${NC}"
        read -p "  Install mistune $latest_version? [y/N] " answer
        if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
            tmp_dir=$(/usr/bin/mktemp -d)
            /usr/bin/pip3 install --target="$tmp_dir" --no-deps mistune=="$latest_version" 2>/dev/null
            if [ -d "$tmp_dir/mistune" ]; then
                /bin/rm -rf "$DEST_MISTUNE"
                /bin/cp -R "$tmp_dir/mistune" "$DEST_MISTUNE"
                # Clean up bytecode
                /usr/bin/find "$DEST_MISTUNE" -name "__pycache__" -type d -exec /bin/rm -rf {} + 2>/dev/null
                echo -e "  ${GREEN}Updated mistune to $latest_version${NC}"
                updated=1
            else
                echo -e "  ${RED}Failed to download mistune${NC}"
            fi
            /bin/rm -rf "$tmp_dir"
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
# 3. OMC Documentation
# ════════════════════════════════════════════════════════════

echo "── Checking OMC documentation ──"

# Copy all files from OMC/Documentation to AppletBuilder
omc_updated=0
for src in "$OMC_DOCS"/*; do
    [ ! -f "$src" ] && continue
    name=$(/usr/bin/basename "$src")
    dst="$DEST_DOCS/$name"
    if files_match "$src" "$dst"; then
        :
    else
        /bin/cp "$src" "$dst"
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
# 4. ActionUI Documentation (from built ActionUIDocumentation bundle)
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
        if files_match "$src" "$dst"; then
            :
        else
            /bin/cp "$src" "$dst"
            echo -e "  ${GREEN}Updated: $doc${NC}"
            actionui_updated=1
            updated=1
        fi
    done

    # Copy Schemas directory
    if [ -d "$ACTIONUI_DOCS/Schemas" ]; then
        schemas_changed=0
        /bin/mkdir -p "$DEST_DOCS/Schemas"
        for src in "$ACTIONUI_DOCS/Schemas"/*; do
            [ ! -f "$src" ] && continue
            name=$(/usr/bin/basename "$src")
            dst="$DEST_DOCS/Schemas/$name"
            if files_match "$src" "$dst"; then
                :
            else
                /bin/cp "$src" "$dst"
                schemas_changed=1
            fi
        done
        # Remove files in dest that no longer exist in source
        for dst in "$DEST_DOCS/Schemas"/*; do
            [ ! -f "$dst" ] && continue
            name=$(/usr/bin/basename "$dst")
            if [ ! -f "$ACTIONUI_DOCS/Schemas/$name" ]; then
                /bin/rm "$dst"
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
        /bin/mkdir -p "$DEST_DOCS/Elements"
        for src in "$ACTIONUI_DOCS/Elements"/*; do
            [ ! -f "$src" ] && continue
            name=$(/usr/bin/basename "$src")
            dst="$DEST_DOCS/Elements/$name"
            if files_match "$src" "$dst"; then
                :
            else
                /bin/cp "$src" "$dst"
                elements_changed=1
            fi
        done
        # Remove files in dest that no longer exist in source
        for dst in "$DEST_DOCS/Elements"/*; do
            [ ! -f "$dst" ] && continue
            name=$(/usr/bin/basename "$dst")
            if [ ! -f "$ACTIONUI_DOCS/Elements/$name" ]; then
                /bin/rm "$dst"
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
# 5. Validate ElementTemplates.json against Elements/
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
        element_name=$(/usr/bin/basename "$element_file" .json)
        echo "$template_tags" | /usr/bin/grep -qx "$element_name"
        rc=$?
        if [ "$rc" -ne 0 ]; then
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
# 6. Codesign AppletBuilder.app (ad-hoc, for local execution)
# ════════════════════════════════════════════════════════════

echo "── Codesigning AppletBuilder.app ──"

if [ ! -f "$CODESIGN_SCRIPT" ]; then
    echo -e "  ${RED}codesign_applet.sh not found at: $CODESIGN_SCRIPT${NC}"
    exit 1
fi

"$CODESIGN_SCRIPT" "$APPLET_BUILDER" "-"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo -e "  ${RED}Codesigning failed${NC}"
    exit 1
fi

echo ""

# ════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════

if [ "$updated" -eq 1 ]; then
    echo -e "${GREEN}AppletBuilder resources updated.${NC}"
    echo "Clearing /tmp/appletbuilder_help/ to regenerate HTML help files."
    /bin/rm -rf /tmp/appletbuilder_help 2>/dev/null
else
    echo "Everything is up to date."
fi
