#!/bin/bash
# AppletBuilder.itest - GUI front end for the integration tests.
#
# The Integration Test button in the Build & Run pane. It validates the bundle,
# as the Test button does, then runs "appletbuilder itest <App.app>": every
# *.itest.sh in the Tests/ directory beside the applet, each against a fresh
# copy of the real applet launched for the test and driven over its bridge. The
# transcript goes into the pane's log control, next to the build log.
#
# Separate from Test on purpose: the omctest suites are quick and show nothing,
# while these launch the applet, open its windows, take the focus, and can run
# for minutes.
#
# A copy of the applet that is already running (from the Run button, or from
# another path) shares its preferences and anything it keeps under its bundle
# path, so the user is asked first: quit it, or cancel. The tests never run
# beside it.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

# -- UI reporters (override the stderr defaults from lib.common.sh) --

if ! ab_log_to_control "$BUILD_LOG_ID"; then
    set_value "$BUILD_LOG_ID" "Error: could not create a log file in ${TMPDIR:-/tmp}"
    ab_status_result "exclamationmark.triangle.fill" "orange" "Could not start - no writable ${TMPDIR:-/tmp}"
    exit 1
fi
ab_buildrun_traps

# Collected and shown once at the end, as in AppletBuilder.test.sh: show_errors
# keeps one report, so a second call would replace the first.
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

# Only the validation toggle applies; signing and thinning belong to the build.
AB_WARNINGS_AS_ERRORS=0
__wae="$OMC_ACTIONUI_VIEW_405_VALUE"
if [ "$__wae" = "1" ] || [ "$__wae" = "true" ]; then
    AB_WARNINGS_AS_ERRORS=1
fi

alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

# -- Run --

project_path=$(load_project_path)
if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    set_value "$BUILD_LOG_ID" "Error: No project loaded"
    ab_status_result "exclamationmark.triangle.fill" "orange" "No project loaded"
    exit 1
fi

app_name=$(/usr/bin/basename "$project_path")
tests_dir=$(applet_tests_dir "$project_path")

ab_status_busy "app.badge.checkmark" "Integration testing ${app_name}..."
ab_log "Integration testing ${app_name}..."

itest_files=$(applet_itest_files "$project_path")
if [ -z "$itest_files" ]; then
    ab_log ""
    ab_log "No integration tests (*.itest.sh) in the Tests/ directory beside ${app_name} - there is nothing to run."
    ab_log "  Expected in: ${tests_dir:-<beside the applet>}"
    ab_status_result "exclamationmark.triangle.fill" "orange" "No integration tests beside ${app_name}"
    exit 1
fi

# Validate first, as the Test button does: a dangling COMMAND_ID or a missing
# window description is named here in one line, instead of as a window that
# never opens in the middle of a test.
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

# An applet that shares AppletBuilder's bundle identifier would find AppletBuilder
# itself among its running copies, and "Quit and Test" would quit the host in the
# middle of this handler.
project_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$project_path/Contents/Info.plist" 2>/dev/null)
host_id=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "${OMC_APP_BUNDLE_PATH}/Contents/Info.plist" 2>/dev/null)
if [ -n "$project_id" ] && [ "$project_id" = "$host_id" ]; then
    ab_log ""
    ab_log "No tests were run - ${app_name} has AppletBuilder's own bundle identifier (${project_id}), so a test launch would run beside this AppletBuilder. Run \"appletbuilder itest\" from Terminal with AppletBuilder quit."
    ab_status_result "exclamationmark.triangle.fill" "orange" "Cannot test AppletBuilder from itself"
    exit 1
fi

# A copy already running: ask, one copy at a time.
running=$(applet_running_instances "$project_path")
while [ -n "$running" ]; do
    running_pid=${running%% *}
    running_line=${running%%
*}
    running_path=${running_line#* }
    if [ "$running_path" = "$project_path" ]; then
        where=""
    else
        where=" from ${running_path}"
    fi
    "$alert_tool" --level caution --title "AppletBuilder" \
        --ok "Quit and Test" --cancel "Cancel" \
        "${app_name} is running${where}. The integration tests start their own copy, which would share its preferences and files. Quit the running copy first? It is asked as its Quit menu item would, so it may ask about unsaved work."
    answer=$?
    if [ "$answer" -ne 0 ]; then
        flush_report
        ab_log ""
        ab_log "No tests were run - ${app_name} is running (process ${running_pid}${where})."
        ab_status_result "exclamationmark.triangle.fill" "orange" "Canceled - ${app_name} is running"
        exit 1
    fi
    ab_log "Quitting the running ${app_name} (process ${running_pid}${where})..."
    applet_quit_instance "$running_pid" 60
    quit_status=$?
    if [ "$quit_status" -ne 0 ]; then
        flush_report
        ab_log ""
        ab_log "No tests were run - ${app_name} (process ${running_pid}) did not quit within a minute; it may be asking about unsaved work."
        ab_status_result "exclamationmark.triangle.fill" "orange" "${app_name} is still running - no tests were run"
        exit 1
    fi
    running=$(applet_running_instances "$project_path")
done

ab_log ""
ab_log "Running integration tests - the applet's windows open while they run..."

# The CLI does the run, so the button and "appletbuilder itest" cannot drift
# apart. The harness takes what AppletBuilder exports to this handler out of the
# applet's environment (omcitest.sh, _omcitest_unset_host_environment).
"${OMC_APP_BUNDLE_PATH}/Contents/Resources/Agents/appletbuilder" itest "$project_path" 2>&1 | ab_log_stream
status=${PIPESTATUS[0]}
case "$status" in
    ''|*[!0-9]*) status=1 ;;
esac
flush_report
timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")

summary=""
refused=""
no_launch=""
if [ -n "$AB_LOG_FILE" ] && [ -f "$AB_LOG_FILE" ]; then
    summary=$(/usr/bin/grep -E '^itest: [0-9]+ passed, [0-9]+ failed, [0-9]+ files$' "$AB_LOG_FILE" | /usr/bin/tail -1)
    summary=${summary#itest: }
    refused=$(/usr/bin/grep -m 1 'OMC test launch refused:' "$AB_LOG_FILE")
    no_launch=$(/usr/bin/grep -m 1 'the applet did not come up for the test' "$AB_LOG_FILE")
fi

ab_log ""
if [ "$status" -eq 0 ]; then
    ab_log "Integration tests passed. (${timestamp})"
    ab_status_result "checkmark.circle.fill" "green" "Integration tests passed${summary:+ - ${summary}}"
elif [ "$status" -eq 2 ] && [ -z "$summary" ]; then
    # As in AppletBuilder.test.sh: the CLI exits 2 with no tally when it finds
    # nothing to run (the Tests/ folder went away after the check above, or holds
    # no *.itest.sh any more). Nothing ran, so nothing failed.
    ab_log "No tests were run - no integration test files were found. (${timestamp})"
    ab_status_result "exclamationmark.triangle.fill" "orange" "No integration test files found to run"
elif [ -n "$refused" ]; then
    # The engine turns the test launch down for a build signed for distribution
    # or with the hardened runtime; the reason is in the transcript above.
    ab_log "The applet's signature does not allow test launches. Build it with \"Sign to Run Locally (ad-hoc)\" (or a development certificate) and run the tests again. (${timestamp})"
    ab_status_result "xmark.octagon.fill" "red" "Its signature does not allow test launches - build it signed to run locally"
elif [ -n "$no_launch" ]; then
    ab_log "The applet did not come up for the test; its output is above. An OMC engine older than 5.5 has no test launch: Build updates the applet's engine to AppletBuilder's. (${timestamp})"
    ab_status_result "xmark.octagon.fill" "red" "Integration tests failed - the applet did not come up${summary:+ - ${summary}}"
else
    ab_log "Integration tests FAILED (exit code: ${status}) (${timestamp})"
    ab_status_result "xmark.octagon.fill" "red" "Integration tests failed${summary:+ - ${summary}}"
fi

exit $status
