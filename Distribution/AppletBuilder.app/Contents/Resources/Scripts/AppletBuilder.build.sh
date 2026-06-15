#!/bin/bash
# AppletBuilder.build - GUI front end for the build pipeline.
#
# The pipeline itself lives in lib.build.sh (applet_build + phases), shared with
# the agent CLI. This handler only wires the Build & Run pane to it: it routes the
# reporters to the log control / error window / alert, and reads the build options
# from the form controls into the AB_* variables the pipeline expects.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

# ── UI reporters (override the stderr defaults from lib.common.sh) ──

# Accumulate into the Build & Run log control. omc_dialog_control replaces the
# whole text each call, so we keep the running log in build_log.
build_log=""
ab_log() {
    if [ -z "$build_log" ]; then
        build_log="$1"
    else
        build_log="${build_log}
$1"
    fi
    set_value "$BUILD_LOG_ID" "$build_log"
}

ab_report() {
    show_errors "$1"
}

# Only the Python major-version upgrade asks for confirmation; present it as the
# original caution alert (rc 0 = "Upgrade").
ab_confirm() {
    "$alert_tool" --level caution \
        --title "Python Version Change" \
        --ok "Upgrade" --cancel "Keep Current" \
        "$1"
}

# ── Build options from the Build & Run controls ──

AB_IDENTITY="$OMC_ACTIONUI_VIEW_402_VALUE"        # signing identity ("" → ad-hoc)
AB_FORCE_UPDATE="$OMC_ACTIONUI_VIEW_403_VALUE"     # force framework/exe refresh
AB_THIN_ARCH="$OMC_ACTIONUI_VIEW_404_VALUE"        # thin to arch ("" / none → skip)
AB_WARNINGS_AS_ERRORS=0
__wae="$OMC_ACTIONUI_VIEW_405_VALUE"
if [ "$__wae" = "1" ] || [ "$__wae" = "true" ]; then
    AB_WARNINGS_AS_ERRORS=1
fi

# ── Run ──

project_path=$(load_project_path)
if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    set_value "$BUILD_LOG_ID" "Error: No project loaded"
    exit 1
fi

applet_build "$project_path"
