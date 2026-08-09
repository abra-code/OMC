#!/bin/bash
# AppletBuilder.test - GUI front end for the omctest suite.
#
# The Test button in the Build & Run pane. It does exactly what "appletbuilder
# test <App.app>" does - validate the bundle, then run every *.test.sh in the
# Tests/ directory beside it - through the same shared pipeline code, and routes
# the whole transcript into the pane's log control, next to the build log.
#
# Tests are deliberately NOT part of the Build button: a developer mid-refactor
# has to be able to re-sign an applet whose tests are momentarily red. The
# scripted equivalent of "build after a green suite" is
# "appletbuilder build <App.app> --test".

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

# ── UI reporters (override the stderr defaults from lib.common.sh) ──

# Accumulate into the Build & Run log control (see ab_log_to_control). The
# stream variant matters here: the runner emits one line per check, so the pane
# would crawl if every one of them replaced the control's text.
if ! ab_log_to_control "$BUILD_LOG_ID"; then
    set_value "$BUILD_LOG_ID" "Error: could not create a log file in ${TMPDIR:-/tmp}"
    exit 1
fi

# Two validators run back to back below, and each reports independently. Calling
# show_errors twice in one handler would show only the second: it stages the text
# on ONE global pasteboard key and chains to the output window, which does not
# open until this handler exits - so the second call overwrites the first, and
# the report naming which script or JSON file is broken is lost. Collect instead,
# and open one window at the end.
report_text=""
ab_report() {
    report_text="${report_text}${report_text:+

}$1"
}

flush_report() {
    if [ -n "$report_text" ]; then
        show_errors "$report_text"
        report_text=""
    fi
}

# ── Options from the Build & Run controls ──
#
# Only the validation toggle applies to a test run; signing identity, thinning
# and the binary-refresh options all belong to the build.

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

app_name=$(/usr/bin/basename "$project_path")
tests_dir=$(applet_tests_dir "$project_path")

ab_log "Testing ${app_name}..."

if [ -z "$tests_dir" ] || [ ! -d "$tests_dir" ]; then
    ab_log ""
    ab_log "No Tests/ directory beside ${app_name} - there is nothing to run."
    ab_log "  Expected at: ${tests_dir:-<beside the applet>}"
    ab_log "  A suite is plain POSIX sh; the omctest guide, linked from Help, is the reference."
    exit 1
fi

# Validate before running, exactly as "appletbuilder test" does. A bash 4-ism or
# a dangling COMMAND_ID is named here in one line; left to the suite it surfaces
# as a baffling mid-test handler failure. Both validators run even when the
# first one fails, so one pass reports everything wrong with the bundle.
validation_failed=0
validate_project "$project_path" || validation_failed=1
validate_info_content "$project_path" || validation_failed=1
flush_report

if [ "$validation_failed" -ne 0 ]; then
    ab_log ""
    ab_log "No tests were run - fix the validation errors above. ($(/bin/date "+%Y-%m-%d %H:%M:%S"))"
    exit 1
fi

applet_run_tests "$project_path"
status=$?
flush_report
timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")

ab_log ""
if [ "$status" -eq 0 ]; then
    ab_log "Tests passed. (${timestamp})"
else
    ab_log "Tests FAILED (exit code: ${status}) (${timestamp})"
fi

exit $status
