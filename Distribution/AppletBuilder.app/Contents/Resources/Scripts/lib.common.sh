#!/bin/bash
# lib.common.sh - Common base for AppletBuilder
#
# This is the foundation sourced by (almost) every AppletBuilder script:
# tool/env setup, control IDs, private-pasteboard state, and the core UI
# setters. Feature-specific helpers live in sibling libs that a script
# sources on top of this one only when it needs them:
#
#   lib.errors.sh    show_errors / show_reference output windows
#   lib.prefs.sh     defaults-domain preferences (bundle prefix, editor)
#   lib.tables.sh    refresh_{commands,scripts,uifiles}_table
#   lib.help.sh      ensure_help_docs_converted (Markdown -> HTML)
#   lib.plist.sh     plist_read / plist_write / plist_edit / unique_command_id
#   lib.validate.sh  validate_script_file
#   lib.build.sh     applet_* build / rename / icon / codesign pipeline
#
# echo "loading lib.common.sh"

[ -n "$__LIB_COMMON_SH" ] && return 0
__LIB_COMMON_SH=1

# ──────────────────────────────────────────────────────────────
# Dialog tool setup
# ──────────────────────────────────────────────────────────────

dialog_tool="$OMC_OMC_SUPPORT_PATH/omc_dialog_control"
next_cmd="$OMC_OMC_SUPPORT_PATH/omc_next_command"
pasteboard_tool="$OMC_OMC_SUPPORT_PATH/pasteboard"
python3="${OMC_APP_BUNDLE_PATH}/Contents/Library/Python/bin/python3"
window_uuid="${OMC_ACTIONUI_WINDOW_UUID:-$OMC_NIB_DLG_GUID}"
cmd_guid="$OMC_CURRENT_COMMAND_GUID"

# ──────────────────────────────────────────────────────────────
# Control IDs
# ──────────────────────────────────────────────────────────────

# Project window (TabView)
TAB_VIEW_ID=10
GENERAL_TAB_VIEW_ID=101
BUILD_RUN_TAB_VIEW_ID=102
COMMANDS_TAB_VIEW_ID=103
SCRIPTS_TAB_VIEW_ID=104
UI_FILES_TAB_VIEW_ID=105

# New Applet form
NEW_TYPE_PICKER_ID=201
NEW_TEMPLATE_PATH_ID=202
NEW_NAME_ID=203
NEW_BUNDLE_ID_ID=204
NEW_ICON_ID=206
NEW_CLONE_SOURCE_ROW_ID=207
NEW_PYTHON_TOGGLE_ID=208
NEW_ICON_PICKER_ID=209
NEW_CUSTOM_ICON_ROW_ID=210
NEW_HEADER_IMAGE_ID=211
NEW_HEADER_NAME_ID=212
NEW_STATUS_ID=220
NEW_CREATE_BTN_ID=221

# General form
GEN_NAME_ID=302
GEN_BUNDLE_ID_ID=303
GEN_VERSION_ID=305
GEN_MIN_OS_ID=306
GEN_ICON_IMAGE_ID=307
GEN_HEADER_NAME_ID=308
GEN_STATUS_ID=320

# Commands tab
CMD_TABLE_ID=501
CMD_DETAIL_ID=502
CMD_ADD_BTN_ID=511
CMD_REMOVE_BTN_ID=512
CMD_REVEAL_BTN_ID=514
CMD_VALIDATE_BTN_ID=520
CMD_SAVE_BTN_ID=523
CMD_EDITED_LABEL_ID=524
CMD_EXT_EDIT_BTN_ID=525
CMD_TOOLBAR_ID=526

# Scripts tab
SCRIPTS_TABLE_ID=601
SCRIPTS_DETAIL_ID=602
SCRIPTS_ADD_BTN_ID=611
SCRIPTS_REMOVE_BTN_ID=612
SCRIPTS_REVEAL_BTN_ID=614
SCRIPTS_VALIDATE_BTN_ID=620
SCRIPTS_SAVE_BTN_ID=623
SCRIPTS_EDITED_LABEL_ID=624
SCRIPTS_EXT_EDIT_BTN_ID=625
SCRIPTS_TOOLBAR_ID=626

# UI Files tab
UI_TABLE_ID=701
UI_DETAIL_ID=702
UI_ADD_BTN_ID=711
UI_REMOVE_BTN_ID=712
UI_REVEAL_BTN_ID=714
UI_VALIDATE_BTN_ID=720
UI_PRETTIFY_BTN_ID=721
UI_PREVIEW_BTN_ID=722
UI_SAVE_BTN_ID=723
UI_EDITED_LABEL_ID=724
UI_EXT_EDIT_BTN_ID=725
UI_TOOLBAR_ID=726
UI_TEMPLATE_PICKER_ID=728

# Services (in General tab)
SVC_TABLE_ID=330
SVC_MENU_TITLE_ID=331
SVC_COMMAND_PICKER_ID=332
SVC_INPUT_PICKER_ID=333
SVC_ADD_BTN_ID=334
SVC_REMOVE_BTN_ID=335
SVC_SAVE_BTN_ID=336
SVC_STATUS_ID=337

# New Command dialog
NEWCMD_NAME_ID=801
NEWCMD_COMMAND_ID_ID=802
NEWCMD_EXECUTION_ID=803
NEWCMD_ACTIVATION_ID=804
NEWCMD_SCRIPT_ID=805
NEWCMD_STATUS_ID=810
NEWCMD_CREATE_BTN_ID=811

# New Script dialog
NEWSCRIPT_NAME_ID=821
NEWSCRIPT_TYPE_ID=822
NEWSCRIPT_STATUS_ID=830
NEWSCRIPT_CREATE_BTN_ID=831

# New UI File dialog
NEWUI_NAME_ID=841
NEWUI_TYPE_ID=842
NEWUI_STATUS_ID=850
NEWUI_CREATE_BTN_ID=851

# Settings dialog
SETTINGS_EDITOR_PATH_ID=861
SETTINGS_EDITOR_NAME_ID=862

# Help Viewer
HELP_BACK_BTN_ID=901
HELP_FORWARD_BTN_ID=902
HELP_WEBVIEW_ID=910

# Build & Run
BUILD_IDENTITY_PICKER_ID=402
BUILD_THIN_PICKER_ID=404
BUILD_WARNINGS_AS_ERRORS_ID=405
BUILD_LOG_ID=401

# ──────────────────────────────────────────────────────────────
# State management (private pasteboards keyed by window UUID)
# ──────────────────────────────────────────────────────────────

# Pasteboard key names (suffixed with window_uuid)
PB_PROJECT_PATH="project_path_${window_uuid}"
PB_UIFILES_SELECTED="uifiles_selected_path_${window_uuid}"
PB_SCRIPTS_SELECTED="scripts_selected_path_${window_uuid}"
PB_CMD_SELECTED="cmd_selected_index_${window_uuid}"
PB_SVC_SELECTED="svc_selected_index_${window_uuid}"
PB_HELP_NAV_COUNT="help_nav_count_${window_uuid}"
PB_HELP_WENT_BACK="help_went_back_${window_uuid}"
PB_SCRIPTS_HASH="scripts_file_hash_${window_uuid}"
PB_CMD_HASH="cmd_file_hash_${window_uuid}"
PB_UIFILES_HASH="uifiles_file_hash_${window_uuid}"
PB_SCRIPTS_DIRTY="scripts_dirty_${window_uuid}"
PB_CMD_DIRTY="cmd_dirty_${window_uuid}"
PB_UIFILES_DIRTY="uifiles_dirty_${window_uuid}"
PB_PLIST_HASH="plist_hash_${window_uuid}"

pb_set() {
    "$pasteboard_tool" "$1" set "$2"
}

pb_get() {
    "$pasteboard_tool" "$1" get
}

save_project_path() {
    pb_set "$PB_PROJECT_PATH" "$1"
}

load_project_path() {
    pb_get "$PB_PROJECT_PATH"
}

# Resolve a project's command description file.
# OMC reads either Command.json or Command.plist, preferring Command.json when
# both exist; this mirrors that resolution. When neither file exists yet, the
# Command.json path is returned (the format new applets are created in), so
# callers that create the file land on the modern default.
# Usage: cmd_file=$(command_file_path "$project_path")
command_file_path() {
    local resources="$1/Contents/Resources"
    if [ -f "$resources/Command.json" ]; then
        echo "$resources/Command.json"
    elif [ -f "$resources/Command.plist" ]; then
        echo "$resources/Command.plist"
    else
        echo "$resources/Command.json"
    fi
}

# True (rc 0) when the given command file is JSON (by extension).
is_json_command_file() {
    case "$1" in
        *.json) return 0 ;;
        *) return 1 ;;
    esac
}

# True (rc 0) when a basename is the reserved command-description file.
# OMC reads the command list from Command.json (preferred) or Command.plist;
# neither is a UI file, so callers that enumerate Resources for UI use this to
# skip them. Usage: is_command_file_name "$(basename "$f")"
is_command_file_name() {
    case "$1" in
        Command.json|Command.plist) return 0 ;;
        *) return 1 ;;
    esac
}

cleanup_state() {
    pb_set "$PB_PROJECT_PATH" ""
    pb_set "$PB_UIFILES_SELECTED" ""
    pb_set "$PB_SCRIPTS_SELECTED" ""
    pb_set "$PB_CMD_SELECTED" ""
    pb_set "$PB_SVC_SELECTED" ""
    pb_set "$PB_HELP_NAV_COUNT" ""
    pb_set "$PB_HELP_WENT_BACK" ""
    pb_set "$PB_SCRIPTS_HASH" ""
    pb_set "$PB_CMD_HASH" ""
    pb_set "$PB_UIFILES_HASH" ""
    pb_set "$PB_SCRIPTS_DIRTY" ""
    pb_set "$PB_CMD_DIRTY" ""
    pb_set "$PB_UIFILES_DIRTY" ""
    pb_set "$PB_PLIST_HASH" ""
}

# Compute SHA-256 hash of a file (just the hash, no filename)
file_hash() {
    /usr/bin/shasum -a 256 "$1" 2>/dev/null | /usr/bin/cut -d ' ' -f 1
}

# Check if a file was modified externally since it was loaded.
# Usage: check_file_modified "$file_path" "$hash_pb_key"
# Returns: 0 = no conflict or user chose "Save Anyway"
#          1 = user chose "Reload from Disk"
#          2 = user chose "Cancel"
check_file_modified() {
    local file_path="$1"
    local hash_pb_key="$2"
    local stored_hash=$(pb_get "$hash_pb_key")
    if [ -z "$stored_hash" ]; then
        return 0
    fi
    local current_hash=$(file_hash "$file_path")
    if [ "$stored_hash" = "$current_hash" ]; then
        return 0
    fi
    local alert_tool="$OMC_OMC_SUPPORT_PATH/alert"
    "$alert_tool" --level caution \
        --title "File Modified Externally" \
        --ok "Save Anyway" \
        --cancel "Reload from Disk" \
        --other "Cancel" \
        "This file has been modified by another application since it was loaded into the editor."
    local choice=$?
    case $choice in
        0) return 0 ;;  # Save Anyway
        1) return 1 ;;  # Reload from Disk
        *)  return 2 ;;  # Cancel (or timeout)
    esac
}

# ──────────────────────────────────────────────────────────────
# UI helpers
# ──────────────────────────────────────────────────────────────

set_value() {
    local view_id="$1"
    local value="$2"
    "$dialog_tool" "$window_uuid" "$view_id" "$value"
}

set_status() {
    local view_id="$1"
    local message="$2"
    set_value "$view_id" "$message"
}

set_window_title() {
    local title="$1"
    "$dialog_tool" "$window_uuid" omc_window "$title"
}

set_enabled() {
    local view_id="$1"
    local enabled="$2"
    if [ "$enabled" = "1" ] || [ "$enabled" = "true" ]; then
        "$dialog_tool" "$window_uuid" "$view_id" omc_enable
    else
        "$dialog_tool" "$window_uuid" "$view_id" omc_disable
    fi
}

set_visible() {
    local view_id="$1"
    local visible="$2"
    if [ "$visible" = "1" ] || [ "$visible" = "true" ]; then
        "$dialog_tool" "$window_uuid" "$view_id" omc_show
    else
        "$dialog_tool" "$window_uuid" "$view_id" omc_hide
    fi
}

# ──────────────────────────────────────────────────────────────
# Reporting (output indirection)
# ──────────────────────────────────────────────────────────────
#
# Shared pipeline code (lib.build.sh / lib.create.sh) reports through these three
# functions instead of touching the UI directly, so the same logic serves two
# front ends:
#
#   • GUI command handlers override them (after sourcing) to write to dialog
#     controls / show_errors windows / the alert tool — preserving exact UI behavior.
#   • The agent CLI leaves the defaults in place, so everything lands on stderr
#     (progress + error reports) and decisions are taken non-interactively.
#
# Override pattern (in a caller, AFTER sourcing the libs, BEFORE invoking a
# pipeline function — last definition wins):
#
#   ab_log()     { set_value "$SOME_LOG_ID" "$1"; }
#   ab_report()  { show_errors "$1"; }
#   ab_confirm() { "$alert_tool" --ok Yes --cancel No "$1"; }   # rc 0 = yes
#
# ab_log        — a progress / status line.
# ab_report     — a detailed (often multi-line) error or warning block.
# ab_confirm    — a yes/no question; return 0 for "yes", non-zero for "no".
#                 The agent default answers from $AB_ASSUME_YES (set by --force).
# ab_log_stream — a whole subprocess's line stream, read from stdin. Used for
#                 tools that report for themselves (the omctest runner) instead
#                 of calling ab_log per line.

ab_log() {
    printf '%s\n' "$1" >&2
}

ab_report() {
    printf '%s\n' "$1" >&2
}

ab_confirm() {
    [ "$AB_ASSUME_YES" = "1" ]
}

ab_log_stream() {
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s\n' "$line" >&2
    done
}

# ──────────────────────────────────────────────────────────────
# Appending log control (GUI reporters)
# ──────────────────────────────────────────────────────────────
#
# Point ab_log / ab_log_stream at a read-only TextEditor used as a running log
# (the Build & Run pane's). omc_dialog_control replaces a control's whole text on
# every call, so the transcript has to be kept somewhere and re-sent in full.
#
# It is kept in a FILE, not a shell variable, on purpose: ab_log_stream is fed by
# a pipeline and therefore runs in a subshell, so a variable appended to there
# would be lost the moment the pipeline ended - and the next ab_log in the parent
# would blank the control back to its pre-pipeline text.
#
# Usage, in a GUI handler after sourcing the libs:  ab_log_to_control "$BUILD_LOG_ID"
# It returns non-zero if it cannot create the file, and installs EXIT/INT/TERM
# traps to delete it - so a handler that wants its own traps must set them
# afterwards and call ab_log_control_cleanup itself.

# How many streamed lines to buffer before refreshing the control. One update per
# line would cost a fork and a full-text replace per line, and a test suite emits
# one line per check - hundreds - so the pane would crawl.
AB_LOG_FLUSH_LINES=20

ab_log_control_cleanup() {
    if [ -n "$AB_LOG_FILE" ]; then
        /bin/rm -f "$AB_LOG_FILE"
    fi
}

# Append one line to the transcript, newline-SEPARATED rather than
# newline-terminated: the file then holds exactly the text the control should
# show, with no trailing blank line - byte for byte what the older in-variable
# accumulator produced, including its "an empty first line stays empty" case.
ab_log_append() {
    if [ -s "$AB_LOG_FILE" ]; then
        printf '\n%s' "$1" >> "$AB_LOG_FILE"
    else
        printf '%s' "$1" >> "$AB_LOG_FILE"
    fi
}

# Push the transcript to the control through STDIN rather than argv. A whole test
# transcript as a command-line argument would eventually cross ARG_MAX, and the
# failure mode is silent: omc_dialog_control fails with E2BIG, every later flush
# fails identically, and the log just stops updating mid-run.
ab_log_flush() {
    "$dialog_tool" "$window_uuid" "$AB_LOG_VIEW_ID" omc_set_value_from_stdin < "$AB_LOG_FILE"
}

ab_log_to_control() {
    AB_LOG_VIEW_ID="$1"
    AB_LOG_FILE=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/appletbuilder.log.XXXXXX") || return 1
    # INT/TERM as well as EXIT: a test run lasts minutes, and a handler that is
    # signaled away (the window closed, the app quit) would otherwise leave the
    # file behind.
    trap 'ab_log_control_cleanup' EXIT
    trap 'ab_log_control_cleanup; exit 130' INT
    trap 'ab_log_control_cleanup; exit 143' TERM

    ab_log() {
        ab_log_append "$1"
        ab_log_flush
    }

    ab_log_stream() {
        local line
        local pending=0
        while IFS= read -r line || [ -n "$line" ]; do
            ab_log_append "$line"
            pending=$((pending + 1))
            if [ "$pending" -ge "$AB_LOG_FLUSH_LINES" ]; then
                ab_log_flush
                pending=0
            fi
        done
        if [ "$pending" -gt 0 ]; then
            ab_log_flush
        fi
        return 0
    }
}
