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
    # The status row too, or the previous run's verdict would sit next to this
    # error describing a run that never happened.
    ab_status_result "exclamationmark.triangle.fill" "orange" "Could not start - no writable ${TMPDIR:-/tmp}"
    exit 1
fi
# Replaces the traps ab_log_to_control just installed: this handler also drives
# the spinner, which must stop however the run ends.
ab_buildrun_traps

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
    ab_status_result "exclamationmark.triangle.fill" "orange" "No project loaded"
    exit 1
fi

app_name=$(/usr/bin/basename "$project_path")
tests_dir=$(applet_tests_dir "$project_path")

ab_status_busy "checkmark.diamond" "Testing ${app_name}..."
ab_log "Testing ${app_name}..."

if [ -z "$tests_dir" ] || [ ! -d "$tests_dir" ]; then
    ab_log ""
    ab_log "No Tests/ directory beside ${app_name} - there is nothing to run."
    ab_log "  Expected at: ${tests_dir:-<beside the applet>}"
    ab_log "  A suite is plain POSIX sh; the omctest guide, linked from Help, is the reference."
    ab_status_result "exclamationmark.triangle.fill" "orange" "No Tests directory beside ${app_name}"
    exit 1
fi

# Validate before running, exactly as "appletbuilder test" does. A bash 4-ism or
# a dangling COMMAND_ID is named here in one line; left to the suite it surfaces
# as a baffling mid-test handler failure. Both validators run even when the
# first one fails, so one pass reports everything wrong with the bundle.
validation_failed=0
validate_project "$project_path" || validation_failed=1
validate_info_content "$project_path" || validation_failed=1

if [ "$validation_failed" -ne 0 ]; then
    flush_report
    ab_log ""
    ab_log "No tests were run - fix the validation errors above. ($(/bin/date "+%Y-%m-%d %H:%M:%S"))"
    ab_status_result "xmark.octagon.fill" "red" "Validation failed - no tests were run"
    exit 1
fi

# Deliberately NOT flushed here. validate_project reports warnings through
# ab_report and still returns 0, so a flush at this point would stage them - and
# applet_run_tests can report too (a missing harness, a Tests/ directory removed
# since the check above). The second flush would then overwrite the first and the
# warnings would be lost, which is the exact failure the collect-then-flush
# design exists to avoid. One flush per exit path, and warnings ride along with
# whatever the run has to say.
applet_run_tests "$project_path"
status=$?
flush_report
timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")

# The runner already printed its own one-line tally, and ab_log_stream put it in
# the transcript; lift it from there rather than counting again. The pattern is
# anchored to the exact summary shape because other omctest: lines (a kept
# scratch path, "no test files matched") can follow it in the log.
summary=""
if [ -n "$AB_LOG_FILE" ] && [ -f "$AB_LOG_FILE" ]; then
    summary=$(/usr/bin/grep -E '^omctest: [0-9]+ passed, [0-9]+ failed, [0-9]+ files$' "$AB_LOG_FILE" | /usr/bin/tail -1)
    summary=${summary#omctest: }
fi

ab_log ""
if [ "$status" -eq 0 ]; then
    ab_log "Tests passed. (${timestamp})"
    ab_status_result "checkmark.circle.fill" "green" "Tests passed${summary:+ - ${summary}}"
elif [ "$status" -eq 2 ] && [ -z "$summary" ]; then
    # The suite exits 2 with no tally when it finds nothing to run - Tests/ holds
    # no *.test.sh, or the directory went away between the check above and the
    # run. Nothing ran, so nothing failed: that is the orange "never started"
    # case, not a red one. The wording covers both, and the suite's own line in
    # the transcript says which.
    ab_log "No tests were run - the suite found no test files. (${timestamp})"
    ab_status_result "exclamationmark.triangle.fill" "orange" "No test files found to run"
else
    ab_log "Tests FAILED (exit code: ${status}) (${timestamp})"
    ab_status_result "xmark.octagon.fill" "red" "Tests failed${summary:+ - ${summary}}"
fi

exit $status
