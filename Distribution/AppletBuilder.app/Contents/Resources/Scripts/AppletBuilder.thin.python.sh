#!/bin/bash
# AppletBuilder.thin.python - GUI front end for embedded-Python thinning.
#
# The Execute button in the Build & Run pane's Embedded Python Thinning group.
# The phase itself lives in lib.build.sh (applet_thin_python), shared with the
# agent CLI; this handler only wires the pane to it - routing the reporters to
# the log control / error window / alert, and turning the three checkboxes above
# the button into an action.
#
# Thinning is deliberately NOT part of the Build button. Removing modules from an
# interpreter is not something a routine rebuild should do behind a developer's
# back, and the plan half of the workflow exists precisely so the removal can be
# reviewed before it happens.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.errors.sh"
source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.build.sh"

alert_tool="$OMC_OMC_SUPPORT_PATH/alert"

# ── UI reporters (override the stderr defaults from lib.common.sh) ──

# Accumulate into the Build & Run log control (see ab_log_to_control). The stream
# variant matters here: the analyzer reports a line per traced entry point and
# the applier one per phase, so a full-text replace per line would make the pane
# crawl through a run that already takes minutes.
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

# At most one report is produced per run - every failure path in the phase
# reports and returns - so this can chain straight to the error window, the way
# the Build button does. AppletBuilder.test.sh's collect-then-flush is for a
# handler that runs two reporting validators back to back.
ab_report() {
    show_errors "$1"
}

# The removal is irreversible from the applet's point of view, so the phase asks
# before it happens (rc 0 = "Thin"). Caution rather than critical: the applier
# backs the interpreter up and restores it when verification fails, and a
# committed plan makes the whole thing repeatable.
ab_confirm() {
    "$alert_tool" --level caution \
        --title "Thin Embedded Python" \
        --ok "Thin" --cancel "Cancel" \
        "$1"
}

# ── Options from the Build & Run controls ──

# The three checkboxes in the pane's Embedded Python Thinning group, as the
# action the phase takes. They are a product, not a list, and this is the whole
# table:
#
#   Write Thinning Plan   -> plan             analyze, write the plan, change nothing
#   Apply Plan            -> apply            remove what the plan names
#   Apply + Dry Run       -> apply-dry        list what that would remove
#   Plan + Apply          -> plan-apply       both, for a copy just made
#   both + Dry Run        -> plan-apply-dry   write a plan, then preview it
#
# Dry Run is disabled while Apply is off (AppletBuilder.thin.python.changed keeps
# it that way), because there is no removal to preview; if it is somehow on, the
# plan-only rows above ignore it rather than failing.
thin_plan="$OMC_ACTIONUI_VIEW_412_VALUE"     # BUILD_THIN_PLAN_ID
thin_apply="$OMC_ACTIONUI_VIEW_414_VALUE"    # BUILD_THIN_APPLY_ID
thin_dry="$OMC_ACTIONUI_VIEW_415_VALUE"      # BUILD_THIN_DRY_RUN_ID

AB_THIN_PYTHON_ACTION=""
if is_on "$thin_plan" && is_on "$thin_apply"; then
    if is_on "$thin_dry"; then
        AB_THIN_PYTHON_ACTION="plan-apply-dry"
    else
        AB_THIN_PYTHON_ACTION="plan-apply"
    fi
elif is_on "$thin_apply"; then
    if is_on "$thin_dry"; then
        AB_THIN_PYTHON_ACTION="apply-dry"
    else
        AB_THIN_PYTHON_ACTION="apply"
    fi
elif is_on "$thin_plan"; then
    AB_THIN_PYTHON_ACTION="plan"
fi

# Shared with the build: thinning the applet to one architecture and leaving its
# interpreter universal would be half a job, so a plan written here records the
# same slice the Build button would keep.
AB_THIN_ARCH="$OMC_ACTIONUI_VIEW_404_VALUE"

# Not exposed in the pane. The plan beside the applet is what the workflow is
# built on, and verification after an apply is what makes a wrong plan
# recoverable - both belong to the CLI's advanced flags, not to a button.
AB_THIN_PLAN=""
AB_THIN_SKIP_VERIFY=0

# ── Run ──

project_path=$(load_project_path)
if [ -z "$project_path" ] || [ ! -d "$project_path" ]; then
    set_value "$BUILD_LOG_ID" "Error: No project loaded"
    ab_status_result "exclamationmark.triangle.fill" "orange" "No project loaded"
    exit 1
fi

app_name=$(/usr/bin/basename "$project_path")

# Neither box ticked is a question, not a failure: the button cannot know which
# of the two things it does was meant. (The changed handler disables the button
# in this state, so this is the belt to that pair of braces.)
if [ -z "$AB_THIN_PYTHON_ACTION" ]; then
    set_value "$BUILD_LOG_ID" "Nothing to do: tick Write Thinning Plan, Apply Plan, or both."
    ab_status_result "exclamationmark.triangle.fill" "orange" "Choose Write Thinning Plan or Apply Plan"
    exit 1
fi

case "$AB_THIN_PYTHON_ACTION" in
    plan) busy_message="Planning the thinning of ${app_name}..." ;;
    *)    busy_message="Thinning ${app_name}..." ;;
esac

ab_status_busy "scissors" "$busy_message"

applet_thin_python "$project_path"
status=$?

timestamp=$(/bin/date "+%Y-%m-%d %H:%M:%S")
ab_log ""

if [ "$status" -eq 0 ]; then
    case "$AB_THIN_PYTHON_ACTION" in
        plan)
            ab_log "Thinning plan written. (${timestamp})"
            ab_status_result "checkmark.circle.fill" "green" "Thinning plan written"
            ;;
        apply-dry|plan-apply-dry)
            ab_log "Dry run finished - nothing was removed. (${timestamp})"
            ab_status_result "checkmark.circle.fill" "green" "Dry run finished - nothing removed"
            ;;
        *)
            ab_log "Embedded Python thinned. (${timestamp})"
            ab_status_result "checkmark.circle.fill" "green" "Embedded Python thinned"
            ;;
    esac
elif [ "$status" -eq 2 ]; then
    # Declined at the confirmation. Nothing ran and nothing is wrong, so this is
    # the orange "never started" case rather than a red failure.
    ab_log "Thinning canceled. (${timestamp})"
    ab_status_result "exclamationmark.triangle.fill" "orange" "Thinning canceled"
else
    ab_log "Thinning FAILED (exit code: ${status}) (${timestamp})"
    ab_status_result "xmark.octagon.fill" "red" "Thinning failed"
fi

exit $status
