# Tests/appletbuilder.itest.sh - AppletBuilder through the real engine (appletbuilder itest, OMC 5.5).
#
# The omctest suites (*.test.sh) run AppletBuilder's handlers one at a time; this file launches
# AppletBuilder itself and drives its project window over the bridge: the launch's open panel, a
# project opened on an applet, the tabs' LoadableView handlers filling them, a command and a script
# selected in their tables, a script edited and saved through the editor, and the Build & Run
# buttons' first checks.
#
# The project is a copy of the "ActionUI Window" template in $ITEST_WORK, renamed Fixture; only
# that copy is ever written. Left out, because they would reach the developer's real state:
# - General's Save, New Applet's Create and its bundle id field, the external-editor setting and
#   Embedded Python Thinning all write AppletBuilder's defaults DOMAIN, which a test launch cannot
#   redirect (lib.prefs.sh). app.will.launch writes four editing settings there on every launch;
#   they are the values AppletBuilder always writes.
# - Build registers the applet it built with Launch Services (lsregister), and Run opens it
#   through /usr/bin/open.
# - Integration Test and Test are clicked only on a project with no Tests/ folder, so nothing is
#   launched or run from inside the test.
#
# AppletBuilder's own Integration Test button refuses to test AppletBuilder; run this from
# Terminal (appletbuilder itest Distribution/AppletBuilder.app) or with
# Tools/omcitest_tests/run_fixture.sh --app Distribution/AppletBuilder.app.

eval "$(/usr/bin/sed -n 's/^\([A-Z][A-Z0-9_]*_ID\)=\([0-9][0-9]*\)$/\1=\2/p' \
    "$ITEST_APP/Contents/Resources/Scripts/lib.common.sh")"
check "the view ids imported from lib.common.sh" "10 302 303 305 308 501 502 512 601 602 623 624 408 418 410 420" \
    "$TAB_VIEW_ID $GEN_NAME_ID $GEN_BUNDLE_ID_ID $GEN_VERSION_ID $GEN_HEADER_NAME_ID $CMD_TABLE_ID $CMD_DETAIL_ID $CMD_REMOVE_BTN_ID $SCRIPTS_TABLE_ID $SCRIPTS_DETAIL_ID $SCRIPTS_SAVE_BTN_ID $SCRIPTS_EDITED_LABEL_ID $BUILD_STATUS_ID $BUILD_ENGINE_VERSION_ID $BUILD_TEST_BTN_ID $BUILD_ITEST_BTN_ID"
# The project window's tabs, in AppletBuilder.json order (the TabView's value is the 0-based index).
COMMANDS_TAB=1
SCRIPTS_TAB=2
BUILD_RUN_TAB=4

rows() { # <window> <view-id> -> the table's rows (JSON)
    itest_call actionui.getRows "{\"window\": \"$1\", \"viewID\": $2}"
}
property() { # <window> <view-id> <name> -> the view's property (JSON)
    itest_call actionui.getProperty "{\"window\": \"$1\", \"viewID\": $2, \"name\": \"$3\"}"
}
select_row() { # <window> <view-id> <0-based index>: selects it without firing the table's action
    itest_call actionui.selectRow "{\"window\": \"$1\", \"viewID\": $2, \"index\": $3}" > /dev/null
}
has_rows() { # <window> <view-id>
    case "$(rows "$1" "$2" 2>/dev/null)" in
        ''|'[]') return 1 ;;
    esac
    return 0
}
value_is_set() { # <window> <view-id>
    [ -n "$(itest_value "$1" "$2" 2>/dev/null)" ]
}
# Waits up to <seconds> for <command...> to succeed: a tab's LoadableView handlers run when the tab
# shows, after the command that showed it has ended.
wait_until() { # <seconds> <command...>
    local _deadline=$(( SECONDS + $1 ))
    shift
    while [ "$SECONDS" -lt "$_deadline" ]; do
        "$@" && return 0
        /bin/sleep 0.25
    done
    "$@"
}
show_tab() { # <window> <0-based index>
    itest_set_value "$1" "$TAB_VIEW_ID" "$2" > /dev/null
    itest_wait_idle 60
}

# The project: the template a user would start from, renamed the way the create pipeline names
# the command and its handler (as the omctest suites' ab_make_project does).
FIXTURE="$ITEST_WORK/Fixture.app"
/bin/cp -Rp "$ITEST_APP/Contents/Resources/Templates/ActionUI Window.applet" "$FIXTURE"
check "the fixture project was copied from the template" "0" "$?"
/usr/bin/plutil -replace CFBundleName -string Fixture "$FIXTURE/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string com.omc.applet.Fixture "$FIXTURE/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string 1.0 "$FIXTURE/Contents/Info.plist"
/usr/bin/plutil -replace COMMAND_LIST.0.NAME -string Fixture "$FIXTURE/Contents/Resources/Command.json"
/bin/mv "$FIXTURE/Contents/Resources/Scripts/ActionUI Window.main.sh" "$FIXTURE/Contents/Resources/Scripts/Fixture.main.sh"
check "and named Fixture" "Fixture" "$(/usr/bin/plutil -extract CFBundleName raw -o - "$FIXTURE/Contents/Info.plist")"

section "A bare launch asks for an applet to open"
# AppletBuilder's main command takes a folder (an applet); with none the engine asks, and with no
# answer queued the harness cancels the panel, so no window opens.
itest_wait_idle 60
check "an open panel" "open" "$(itest_panel last kind)"
check "asking for an applet" "Select an applet (.app) to open" "$(itest_panel last message)"
check "canceled" "true" "$(itest_panel last canceled)"
check "so no window opened" "" "$(itest_windows)"

section "Opening an applet opens its project window on the General tab"
# A test launch keeps the project out of the developer's Open Recent and Recent Items. An engine
# from before that (an AppletBuilder.app not yet updated with the current framework) adds the
# project there for real, and does not report the count: on one, nothing is opened at all.
case "$(itest_call omc.test.status)" in
    *'"skippedRecentDocuments": '*) ;;
    *)
        check "an engine that keeps the project out of Open Recent (build AppletBuilder with the current framework)" \
            "skippedRecentDocuments reported" "not reported"
        return 0 ;;
esac
before="$(itest_windows)"
itest_run AppletBuilder --file "$FIXTURE" > /dev/null
itest_wait_idle 60
window="$(itest_new_window "$before")"
check "the main command chained to the project window" "yes" "$([ -n "$window" ] && printf yes || printf no)"
wait_until 30 value_is_set "$window" "$GEN_NAME_ID"
check "the General tab loaded" "0" "$?"
# The name is the first value general.loaded sets; wait for the handler to end before the rest.
itest_wait_idle 60
check "its name" "Fixture" "$(itest_value "$window" "$GEN_NAME_ID")"
check "the header shows it too" "Fixture" "$(itest_value "$window" "$GEN_HEADER_NAME_ID")"
check "its bundle identifier" "com.omc.applet.Fixture" "$(itest_value "$window" "$GEN_BUNDLE_ID_ID")"
check "its version" "1.0" "$(itest_value "$window" "$GEN_VERSION_ID")"
# One file can count more than once (as the run's file and again as its window's), so at least one.
skipped="$(itest_call omc.test.status | /usr/bin/sed -n 's/.*"skippedRecentDocuments": \([0-9][0-9]*\).*/\1/p')"
case "$skipped" in
    ''|0|*[!0-9]*) skipped_some=no ;;
    *) skipped_some=yes ;;
esac
check "the project was not added to Open Recent" "yes" "$skipped_some"

section "The Commands tab lists the applet's commands, and a selection shows one"
show_tab "$window" "$COMMANDS_TAB"
wait_until 30 has_rows "$window" "$CMD_TABLE_ID"
check "the commands table was filled" "0" "$?"
check_contains "with the main command, by its handler name" '"Fixture.main"' "$(rows "$window" "$CMD_TABLE_ID")"
check "nothing selected: Remove is off" "true" "$(property "$window" "$CMD_REMOVE_BTN_ID" disabled)"
select_row "$window" "$CMD_TABLE_ID" 0
check "the table runs the selection handler" "AppletBuilder.commands.selected" "$(itest_click "$window" "$CMD_TABLE_ID")"
itest_wait_idle 60
detail="$(itest_value "$window" "$CMD_DETAIL_ID")"
check_contains "the editor shows the command's JSON" '"NAME": "Fixture"' "$detail"
check_contains "with its window" '"ACTIONUI_WINDOW"' "$detail"
check "and Remove is on" "false" "$(property "$window" "$CMD_REMOVE_BTN_ID" disabled)"

section "The Scripts tab: a script selected, edited in the editor and saved"
SCRIPT="$FIXTURE/Contents/Resources/Scripts/Fixture.main.sh"
show_tab "$window" "$SCRIPTS_TAB"
wait_until 30 has_rows "$window" "$SCRIPTS_TABLE_ID"
check "the scripts table was filled" "0" "$?"
check_contains "with the main handler" "Fixture.main.sh" "$(rows "$window" "$SCRIPTS_TABLE_ID")"
select_row "$window" "$SCRIPTS_TABLE_ID" 0
check "the table runs the selection handler" "AppletBuilder.scripts.selected" "$(itest_click "$window" "$SCRIPTS_TABLE_ID")"
itest_wait_idle 60
check "the editor shows the file" "$(/bin/cat "$SCRIPT")" "$(itest_value "$window" "$SCRIPTS_DETAIL_ID")"
check "Save starts off" "true" "$(property "$window" "$SCRIPTS_SAVE_BTN_ID" disabled)"
EDITED='#!/bin/sh
# Fixture.main.sh - edited by appletbuilder.itest.sh
exit 0'
# As typing does: the text changes, then the editor's valueChangeActionID fires
# (itest_set_value alone fires nothing).
itest_set_value "$window" "$SCRIPTS_DETAIL_ID" "$EDITED" > /dev/null
itest_call actionui.performAction "{\"window\": \"$window\", \"viewID\": $SCRIPTS_DETAIL_ID, \"property\": \"valueChangeActionID\"}" > /dev/null
itest_wait_idle 60
check "the edit turns Save on" "false" "$(property "$window" "$SCRIPTS_SAVE_BTN_ID" disabled)"
check_contains "and marks the script modified" "Modified" "$(itest_value "$window" "$SCRIPTS_EDITED_LABEL_ID")"
check "Save runs the save handler" "AppletBuilder.scripts.save.detail" "$(itest_click "$window" "$SCRIPTS_SAVE_BTN_ID")"
itest_wait_idle 60
check "the file now holds the editor's text" "$EDITED" "$(/bin/cat "$SCRIPT")"
check_contains "and the label says so" "Saved" "$(itest_value "$window" "$SCRIPTS_EDITED_LABEL_ID")"

section "Build & Run: the engine line, and the test buttons on a project without tests"
show_tab "$window" "$BUILD_RUN_TAB"
wait_until 30 value_is_set "$window" "$BUILD_ENGINE_VERSION_ID"
check "the pane loaded" "0" "$?"
# The template carries no engine of its own; Build would put AppletBuilder's in.
check_contains "the project has no engine yet" "Not installed - Build installs" "$(itest_value "$window" "$BUILD_ENGINE_VERSION_ID")"
check "Test runs the test handler" "AppletBuilder.test" "$(itest_click "$window" "$BUILD_TEST_BTN_ID")"
itest_wait_idle 120
check "and finds no Tests folder" "No Tests directory beside Fixture.app" "$(itest_value "$window" "$BUILD_STATUS_ID")"
check "Integration Test runs its handler" "AppletBuilder.itest" "$(itest_click "$window" "$BUILD_ITEST_BTN_ID")"
itest_wait_idle 120
check "and finds no integration tests" "No integration tests beside Fixture.app" "$(itest_value "$window" "$BUILD_STATUS_ID")"
check "the buttons are released afterwards" "false" "$(property "$window" "$BUILD_ITEST_BTN_ID" disabled)"

section "Closing the project window"
# Listed first, or the absence check below passes when the bridge call fails (an empty list).
check "the window is open before" "$window" "$(itest_windows | /usr/bin/grep -x -- "$window")"
itest_close "$window" > /dev/null
itest_wait_idle 60
check "the window is gone" "" "$(itest_windows | /usr/bin/grep -x -- "$window")"
check "the project itself is still there" "yes" "$([ -f "$FIXTURE/Contents/Info.plist" ] && printf yes || printf no)"
