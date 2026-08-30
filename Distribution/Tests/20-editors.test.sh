#!/bin/sh
# Tests/20-editors.test.sh - the three in-app editors.
#
# The UI Files, Scripts and Commands tabs are the same machine three times over:
# a table listing what can be edited, a detail pane, a dirty flag, a fingerprint
# of the file as it was loaded, and a three-way alert when the file changed
# underneath. That last branch is where a wrong answer silently destroys a user's
# work, and it is the reason this file exists.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.appletbuilder.sh"

# check_file_modified raises one alert wired --ok "Save Anyway",
# --cancel "Reload from Disk", --other "Cancel". The alert tool's codes are
# 0 = OK, 1 = Cancel, 2 = Other, so:
SAVE_ANYWAY=0
RELOAD_FROM_DISK=1
CANCEL_THE_SAVE=2

project="$(ab_make_project Widget)"
RES="$project/Contents/Resources"

section "1. the UI Files table lists what is editable, and only that"

ab_reset_state
ab_open_project "$project"
omc_run AppletBuilder.uifiles.loaded
check_status "uifiles.loaded succeeded"        0
check "both window documents are listed" "2"   "$(ui_row_count $UI_TABLE_ID)"
check "MainMenu.json is one of them"     "1"   "$(ui_rows $UI_TABLE_ID | /usr/bin/grep -c '^MainMenu.json	')"
check "Window.json is the other"         "1"   "$(ui_rows $UI_TABLE_ID | /usr/bin/grep -c '^Window.json	')"
# Command.json lives in the same directory and is not a UI file. Listing it would
# invite editing the command manifest in a pane that validates ActionUI.
check "the command manifest is not offered" "0" "$(ui_rows $UI_TABLE_ID | /usr/bin/grep -c 'Command.json')"

section "2. selecting a JSON file loads it and opens up the toolbar"

ui_reset
window_json="$RES/Base.lproj/Window.json"
# Dirtied first, on purpose: the key is empty after ab_reset_state, so without
# this the assertion below passes whether the handler clears it or not.
ab_pb_set PB_UIFILES_DIRTY "1"
omc_table_cell $UI_TABLE_ID 2 "$window_json"
omc_run AppletBuilder.uifiles.selected
check_status "uifiles.selected succeeded"      0
check "the file is remembered" "$window_json"  "$(ab_pb_get PB_UIFILES_SELECTED)"
check "it was fingerprinted"           "yes"   "$([ -n "$(ab_pb_get PB_UIFILES_HASH)" ] && echo yes || echo no)"
check "the editor shows the file"      "$(/bin/cat "$window_json")" "$(ui_value $UI_DETAIL_ID)"
check "Validate is available"          "1"     "$(ui_enabled $UI_VALIDATE_BTN_ID)"
check "Prettify is available"          "1"     "$(ui_enabled $UI_PRETTIFY_BTN_ID)"
check "Preview is available"           "1"     "$(ui_enabled $UI_PREVIEW_BTN_ID)"
check "but Save is not, nothing is edited yet" "0" "$(ui_enabled $UI_SAVE_BTN_ID)"
check "and the file is not dirty"      ""      "$(ab_pb_get PB_UIFILES_DIRTY)"

section "3. selecting a nib offers only what applies to a nib"
# A compiled nib is a directory, not text: the JSON tools would produce nonsense
# and Save would write a directory's worth of nothing over it.

ui_reset
nibproject="$(ab_make_project Legacy Empty)"
nib="$nibproject/Contents/Resources/Base.lproj/MainMenu.nib"
check_exists "the fixture really has a nib" "$nib"
omc_table_cell $UI_TABLE_ID 2 "$nib"
omc_run AppletBuilder.uifiles.selected
check_status "uifiles.selected succeeded"      0
check "Validate is withdrawn"          "0"     "$(ui_enabled $UI_VALIDATE_BTN_ID)"
check "Prettify is withdrawn"          "0"     "$(ui_enabled $UI_PRETTIFY_BTN_ID)"
check "Preview is withdrawn"           "0"     "$(ui_enabled $UI_PREVIEW_BTN_ID)"
check "Save is withdrawn"              "0"     "$(ui_enabled $UI_SAVE_BTN_ID)"
check "Reveal still works on it"       "1"     "$(ui_enabled $UI_REVEAL_BTN_ID)"
check "and the pane explains itself"   "1"     "$(ui_value $UI_DETAIL_ID | /usr/bin/grep -c 'Interface Builder Nib')"

section "4. selecting nothing shuts the whole toolbar down"

# No ui_reset here, deliberately. The pane must hold a real document first, or
# "the editor was emptied" is equally true of a handler that writes nothing at
# all - it would pass with the clearing deleted.
ui_reset
omc_table_cell $UI_TABLE_ID 2 "$window_json"
omc_run AppletBuilder.uifiles.selected
check "a document is loaded before we deselect" "1" \
    "$([ -n "$(ui_value $UI_DETAIL_ID)" ] && echo 1 || echo 0)"

omc_table_cell $UI_TABLE_ID 2 ""
omc_run AppletBuilder.uifiles.selected
check_status "uifiles.selected succeeded"      0
check "Remove is off"                  "0"     "$(ui_enabled $UI_REMOVE_BTN_ID)"
check "Validate is off"                "0"     "$(ui_enabled $UI_VALIDATE_BTN_ID)"
check "Save is off"                    "0"     "$(ui_enabled $UI_SAVE_BTN_ID)"
check "the editor was emptied"         ""      "$(ui_value $UI_DETAIL_ID)"

section "5. typing in the editor arms Save and marks the file dirty"

ui_reset
omc_run AppletBuilder.uifiles.text.changed
check_status "text.changed succeeded"          0
check "Save is armed"                  "1"     "$(ui_enabled $UI_SAVE_BTN_ID)"
check "the pane says so"    "🔴 Modified"       "$(ui_value $UI_EDITED_LABEL_ID)"
check "and the file is dirty"          "1"     "$(ab_pb_get PB_UIFILES_DIRTY)"

section "6. saving an unchanged-on-disk file just writes it"

ui_reset
alerts_reset
alert_answers_reset
edit_target="$OMCTEST_WORK/edit-me.json"
printf '{"a":1}' > "$edit_target"
ab_pb_set PB_UIFILES_SELECTED "$edit_target"
ab_pb_set PB_UIFILES_HASH "$(ab_call lib.common.sh file_hash "$edit_target")"
ab_pb_set PB_UIFILES_DIRTY "1"
omc_fire AppletBuilder.uifiles.save.detail "$UI_DETAIL_ID" '{"a":2}'
check_status "save.detail succeeded"           0
check "the file was written"    '{"a":2}'      "$(/bin/cat "$edit_target")"
check "the user was not interrupted"   "0"     "$(alerts_count)"
check "the pane confirms"      "✅ Saved"       "$(ui_value $UI_EDITED_LABEL_ID)"
check "Save disarmed again"            "0"     "$(ui_enabled $UI_SAVE_BTN_ID)"
check "the dirty flag cleared"         ""      "$(ab_pb_get PB_UIFILES_DIRTY)"
check "and the fingerprint was renewed" "$(ab_call lib.common.sh file_hash "$edit_target")" \
    "$(ab_pb_get PB_UIFILES_HASH)"

section "7. a file changed underneath: Save Anyway overwrites it"

ui_reset
alerts_reset
alert_answers_reset
printf '{"a":2}' > "$edit_target"
ab_pb_set PB_UIFILES_HASH "$(ab_call lib.common.sh file_hash "$edit_target")"
printf '{"someone":"else"}' > "$edit_target"      # changed behind the editor's back
alert_answer $SAVE_ANYWAY
omc_fire AppletBuilder.uifiles.save.detail "$UI_DETAIL_ID" '{"mine":true}'
check_status "save.detail succeeded"           0
check "the user was asked"             "1"     "$(alerts_count)"
check "and asked about an external change" "1" "$(alerts_mention 'modified by another application')"
check "the edit won"        '{"mine":true}'    "$(/bin/cat "$edit_target")"
check "the pane confirms"      "✅ Saved"       "$(ui_value $UI_EDITED_LABEL_ID)"

section "8. a file changed underneath: Reload from Disk keeps the disk copy"
# This is the branch that decides whose work survives. If the codes were ever
# mismatched, this section is what says so.

ui_reset
alerts_reset
alert_answers_reset
printf '{"a":2}' > "$edit_target"
ab_pb_set PB_UIFILES_HASH "$(ab_call lib.common.sh file_hash "$edit_target")"
printf '{"on":"disk"}' > "$edit_target"
# Dirtied first for the same reason as section 2: section 6's save already
# cleared this key, so without it the reload branch's clearing is unprovable.
ab_pb_set PB_UIFILES_DIRTY "1"
alert_answer $RELOAD_FROM_DISK
omc_fire AppletBuilder.uifiles.save.detail "$UI_DETAIL_ID" '{"mine":true}'
check_status "save.detail succeeded"           0
check "the user was asked"             "1"     "$(alerts_count)"
check "the disk copy was NOT overwritten" '{"on":"disk"}' "$(/bin/cat "$edit_target")"
check "the editor now shows the disk copy" '{"on":"disk"}' "$(ui_value $UI_DETAIL_ID)"
check "the pane says what happened" "Reloaded from disk" "$(ui_value $UI_EDITED_LABEL_ID)"
check "Save disarmed"                  "0"     "$(ui_enabled $UI_SAVE_BTN_ID)"
check "the dirty flag cleared"         ""      "$(ab_pb_get PB_UIFILES_DIRTY)"
check "and the fingerprint tracks the disk copy" "$(ab_call lib.common.sh file_hash "$edit_target")" \
    "$(ab_pb_get PB_UIFILES_HASH)"

section "9. a file changed underneath: Cancel leaves both copies alone"

ui_reset
alerts_reset
alert_answers_reset
printf '{"a":2}' > "$edit_target"
ab_pb_set PB_UIFILES_HASH "$(ab_call lib.common.sh file_hash "$edit_target")"
printf '{"untouched":true}' > "$edit_target"
ab_pb_set PB_UIFILES_DIRTY "1"
alert_answer $CANCEL_THE_SAVE
omc_fire AppletBuilder.uifiles.save.detail "$UI_DETAIL_ID" '{"mine":true}'
check_status "save.detail succeeded"           0
check "the user was asked"             "1"     "$(alerts_count)"
check "the disk copy is untouched" '{"untouched":true}' "$(/bin/cat "$edit_target")"
check "the editor was not reloaded over" ""    "$(ui_value $UI_DETAIL_ID)"
# The edit is still unsaved, so the document must still read as dirty - a cleared
# flag here would let the window close without offering to save it.
check "and the file is still dirty"    "1"     "$(ab_pb_get PB_UIFILES_DIRTY)"

section "10. saving with nothing selected is an error, not a write"

ui_reset
ab_pb_set PB_UIFILES_SELECTED ""
omc_fire AppletBuilder.uifiles.save.detail "$UI_DETAIL_ID" 'whatever'
check_status "save.detail reported failure"    1
check "and said why"  "Error: no file selected" "$(ui_value $UI_EDITED_LABEL_ID)"

section "11. Prettify reformats valid JSON and reports invalid JSON"

ui_reset
chains_reset
omc_fire AppletBuilder.uifiles.prettify "$UI_DETAIL_ID" '{"b":2,"a":[1,2]}'
check_status "prettify succeeded"              0
check "the JSON came back indented"    "1"     "$(ui_value $UI_DETAIL_ID | /usr/bin/grep -c '^    "b": 2')"
check "and the result counts as an edit" "1"   "$(ui_enabled $UI_SAVE_BTN_ID)"
check "nothing was reported"           "0"     "$(chain_asked AppletBuilder.show.errors)"

ui_reset
chains_reset
omc_fire AppletBuilder.uifiles.prettify "$UI_DETAIL_ID" '{"b":'
check_status "prettify succeeded"              0
check "the pane says it is invalid" "Invalid JSON" "$(ui_value $UI_EDITED_LABEL_ID)"
check "and the error window was opened" "1"    "$(chain_asked AppletBuilder.show.errors)"

section "12. Validate runs the real ActionUI verifier over the selected file"

ui_reset
chains_reset
ab_pb_set PB_UIFILES_SELECTED "$window_json"
omc_run AppletBuilder.uifiles.validate
check_status "uifiles.validate succeeded"      0
check "the shipped template validates clean" "✅ Valid" "$(ui_value $UI_EDITED_LABEL_ID)"
check "so nothing was reported"        "0"     "$(chain_asked AppletBuilder.show.errors)"

ui_reset
chains_reset
broken="$OMCTEST_WORK/Broken.json"
printf '{"elements":[{"type":"NoSuchElement"}]}' > "$broken"
ab_pb_set PB_UIFILES_SELECTED "$broken"
omc_run AppletBuilder.uifiles.validate
check "a bad document is not called valid" "0" \
    "$(ui_value $UI_EDITED_LABEL_ID | /usr/bin/grep -c 'Valid$')"
check "and the report window was opened" "1"   "$(chain_asked AppletBuilder.show.errors)"

section "13. the Scripts tab runs the same machine on its own keys"
# Separate state: an edit in one tab must never disarm Save in another.

ui_reset
alerts_reset
alert_answers_reset
ab_reset_state
ab_open_project "$project"
script="$RES/Scripts/Widget.main.sh"
check_exists "the fixture has a handler script" "$script"
omc_table_cell $SCRIPTS_TABLE_ID 2 "$script"
omc_run AppletBuilder.scripts.selected
check_status "scripts.selected succeeded"      0
check "the script is remembered" "$script"     "$(ab_pb_get PB_SCRIPTS_SELECTED)"
check "the editor shows it" "$(/bin/cat "$script")" "$(ui_value $SCRIPTS_DETAIL_ID)"
check "and the UI Files tab was not touched" "" "$(ab_pb_get PB_UIFILES_SELECTED)"

omc_fire AppletBuilder.scripts.save.detail "$SCRIPTS_DETAIL_ID" '#!/bin/sh
echo edited'
check_status "scripts.save.detail succeeded"   0
check "the script was written" '#!/bin/sh
echo edited' "$(/bin/cat "$script")"
check "with no alert"                  "0"     "$(alerts_count)"
check "the pane confirms"      "✅ Saved"       "$(ui_value $SCRIPTS_EDITED_LABEL_ID)"

section "14. the Commands tab edits one entry of the manifest in place"

ui_reset
alerts_reset
alert_answers_reset
ab_reset_state
chains_reset
ab_open_project "$project"
cmd_file="$(ab_command_file "$project")"
check "the project's manifest is the JSON one" "$RES/Command.json" "$cmd_file"

omc_run AppletBuilder.commands.loaded
check_status "commands.loaded succeeded"       0
check "the one command is listed"      "1"     "$(ui_row_count $CMD_TABLE_ID)"
# No COMMAND_ID on a primary command, so the table falls back to "<NAME>.main".
check "labelled the way it is dispatched" "Widget.main" "$(ui_rows $CMD_TABLE_ID | /usr/bin/cut -f1)"

ui_reset
omc_table_cell $CMD_TABLE_ID 2 "0"
omc_run AppletBuilder.commands.selected
check_status "commands.selected succeeded"     0
check "the selection is remembered"    "0"     "$(ab_pb_get PB_CMD_SELECTED)"
check "and the manifest fingerprinted" "yes"   "$([ -n "$(ab_pb_get PB_CMD_HASH)" ] && echo yes || echo no)"
check "the detail pane shows this command as JSON" "1" \
    "$(ui_value $CMD_DETAIL_ID | /usr/bin/grep -c '"NAME": "Widget"')"
check "and only this command" "0" "$(ui_value $CMD_DETAIL_ID | /usr/bin/grep -c 'COMMAND_LIST')"

ui_reset
omc_fire AppletBuilder.commands.save.detail "$CMD_DETAIL_ID" '{"NAME": "Widget", "ACTIVATION_MODE": "act_always", "EXECUTION_MODE": "exe_display_in_output_window"}'
check_status "commands.save.detail succeeded"  0
check "the pane confirms"      "✅ Saved"       "$(ui_value $CMD_EDITED_LABEL_ID)"
check "the manifest really changed" "exe_display_in_output_window" \
    "$("$AB_PLISTER" get value "$cmd_file" /COMMAND_LIST/0/EXECUTION_MODE)"
check "the list still has exactly one command" "1" \
    "$("$AB_PLISTER" get count "$cmd_file" /COMMAND_LIST)"
check "and the table was told to redraw" "1"   "$(chain_asked AppletBuilder.commands.loaded)"

section "15. an edit that is not valid JSON never reaches the manifest"

ui_reset
before="$("$AB_PLISTER" get value "$cmd_file" /COMMAND_LIST/0/EXECUTION_MODE)"
omc_fire AppletBuilder.commands.save.detail "$CMD_DETAIL_ID" '{"NAME": "Widget",'
check_status "commands.save.detail reported failure" 1
check "and said why"     "Error: invalid JSON"  "$(ui_value $CMD_EDITED_LABEL_ID)"
check "the manifest is unchanged"  "$before"   "$("$AB_PLISTER" get value "$cmd_file" /COMMAND_LIST/0/EXECUTION_MODE)"
check "and it is still readable"       "1"     "$("$AB_PLISTER" get count "$cmd_file" /COMMAND_LIST)"

section "16. an alert that times out or fails to display is treated as Cancel"
# check_file_modified maps everything that is not OK or Cancel to "do nothing".
# 3 is the alert tool timing out and 255 is it failing to display at all; both
# must land on the branch that writes nothing, because an unanswered question
# about whose copy to keep has no safe affirmative answer. The obvious
# "simplification" of that case arm to `2) return 2` silently breaks both.

for rc in 3 255; do
    ui_reset
    alerts_reset
    alert_answers_reset
    printf '{"base":1}' > "$edit_target"
    ab_pb_set PB_UIFILES_SELECTED "$edit_target"
    ab_pb_set PB_UIFILES_HASH "$(ab_call lib.common.sh file_hash "$edit_target")"
    printf '{"on":"disk"}' > "$edit_target"
    ab_pb_set PB_UIFILES_DIRTY "1"
    alert_answer "$rc"
    omc_fire AppletBuilder.uifiles.save.detail "$UI_DETAIL_ID" '{"mine":true}'
    check "rc $rc: the handler survived"        "0"  "$OMCTEST_STATUS"
    check "rc $rc: the disk copy is untouched"  '{"on":"disk"}' "$(/bin/cat "$edit_target")"
    check "rc $rc: the editor was not reloaded over" "" "$(ui_value $UI_DETAIL_ID)"
    check "rc $rc: and the edit is still pending" "1" "$(ab_pb_get PB_UIFILES_DIRTY)"
done

section "17. the Commands tab has its own conflict path, and it behaves the same"
# Not the same code: commands.save.detail re-extracts one entry with
# plutil + json.tool and chains commands.loaded, where uifiles.save.detail just
# cats the file. Sections 7-9 prove nothing about it.

ui_reset
alerts_reset
alert_answers_reset
chains_reset
conflict_project="$(ab_make_project Conflicted)"
ab_reset_state
ab_open_project "$conflict_project"
conflict_cmd="$(ab_command_file "$conflict_project")"
ab_pb_set PB_CMD_SELECTED "0"
ab_pb_set PB_CMD_HASH "$(ab_call lib.common.sh file_hash "$conflict_cmd")"

# Someone else rewrites the manifest behind the editor.
/usr/bin/plutil -replace COMMAND_LIST.0.NAME -string "ChangedOnDisk" "$conflict_cmd"
alert_answer $RELOAD_FROM_DISK
omc_fire AppletBuilder.commands.save.detail "$CMD_DETAIL_ID" '{"NAME": "MyEdit", "EXECUTION_MODE": "exe_script_file"}'
check_status "commands.save.detail succeeded"  0
check "the user was asked"             "1"     "$(alerts_count)"
check "the manifest kept the disk copy" "ChangedOnDisk" \
    "$("$AB_PLISTER" get value "$conflict_cmd" /COMMAND_LIST/0/NAME)"
check "the editor shows the disk copy"  "1" \
    "$(ui_value $CMD_DETAIL_ID | /usr/bin/grep -c '"NAME": "ChangedOnDisk"')"
check "the pane says what happened" "Reloaded from disk" "$(ui_value $CMD_EDITED_LABEL_ID)"
check "and the table was told to redraw" "1"   "$(chain_asked AppletBuilder.commands.loaded)"

section "18. every mktemp template in the applet ends in its X's"
# BSD mktemp only substitutes a TRAILING run of X's, so "foo_XXXXXX.json" is not
# a template - it creates that exact name, and the next call exits 1 printing
# nothing. A save interrupted between mktemp and the rename would leave the file
# behind and wedge every later save permanently. This is a static check because
# the failure needs a leftover file to show up, which no single run produces.

# "an X followed by a non-X", rather than "XXXXXX followed by a non-X": mktemp
# accepts as few as three X's and as many as you like, so anchoring on a run of
# exactly six both misses ..._XXX.json and falsely accuses a correct ..._XXXXXXXX.
# -I skips the compiled helper binaries under Helpers/.
mktemp_offenders() {
    /usr/bin/grep -rEIl "mktemp[^)]*X[^X\"')[:space:]]" "$1" 2>/dev/null
}

# Positive controls. A pattern that had stopped matching would otherwise report a
# clean applet forever - which is the whole failure mode this section guards.
bad6="$OMCTEST_WORK/bad-6x.sh"
printf '#!/bin/sh\ntmp=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/thing_XXXXXX.json")\n' > "$bad6"
check "a six-X template with a suffix is flagged"  "$bad6"  "$(mktemp_offenders "$bad6")"

bad3="$OMCTEST_WORK/bad-3x.sh"
printf '#!/bin/sh\ntmp=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/thing_XXX.json")\n' > "$bad3"
check "and so is a three-X one"                    "$bad3"  "$(mktemp_offenders "$bad3")"

good_probe="$OMCTEST_WORK/good-template.sh"
printf '#!/bin/sh\ntmp=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/thing_XXXXXX")\nd=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/dir_XXXXXXXX")\n' > "$good_probe"
check "while correct templates pass, however long" ""  "$(mktemp_offenders "$good_probe")"

# Scanned everywhere the applet ships shell, not just its own handlers. The
# templates matter most: a bad template there is copied into every applet New
# Applet creates, so the wedge propagates to the user's own work.
check "no script in the applet has one"   ""  "$(mktemp_offenders "$AB_SCRIPTS")"
check "nor the agent CLI"                 ""  "$(mktemp_offenders "$AB_AGENTS")"
check "nor any shipped applet template"   ""  "$(mktemp_offenders "$AB_TEMPLATES")"
check "nor the bundled helpers"           ""  "$(mktemp_offenders "$OMC_APP_BUNDLE_PATH/Contents/Helpers")"

section "19. saving the manifest does not change who can read it"
# plist_edit replaces Command.json by renaming a temp file over it, and mktemp
# creates 0600. Without the mode being carried across, every Commands-tab save
# silently turns a world-readable manifest owner-only - and nothing in the build
# or codesign path puts it back, so the applet stops working for anyone it is
# distributed to.

mode_project="$(ab_make_project Readable)"
mode_cmd="$(ab_command_file "$mode_project")"
/bin/chmod 644 "$mode_cmd"
check "the manifest starts world-readable" "644" "$(/usr/bin/stat -f '%Lp' "$mode_cmd")"

ab_reset_state
chains_reset
ab_open_project "$mode_project"
ab_pb_set PB_CMD_SELECTED "0"
ab_pb_set PB_CMD_HASH "$(ab_call lib.common.sh file_hash "$mode_cmd")"
omc_fire AppletBuilder.commands.save.detail "$CMD_DETAIL_ID" '{"NAME": "Readable", "EXECUTION_MODE": "exe_script_file"}'
check_status "the save succeeded"          0
check "and the manifest is still world-readable" "644" "$(/usr/bin/stat -f '%Lp' "$mode_cmd")"

# The Info.plist path replaces in place rather than by rename, so it has never
# had the problem - asserted so that a future refactor onto one shared code path
# cannot regress it unnoticed.
mode_plist="$mode_project/Contents/Info.plist"
/bin/chmod 644 "$mode_plist"
ab_call lib.plist.sh plist_edit "$mode_plist" set_keys CFBundleVersion "9.9" >/dev/null 2>&1
check "the Info.plist keeps its mode too" "644" "$(/usr/bin/stat -f '%Lp' "$mode_plist")"
check "and the edit really landed" "9.9" "$(ab_plist_read "$mode_project" CFBundleVersion)"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids"      "" "$(ui_unknown_writes)"
check "no table was clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse"      "" "$(ui_errors)"

omctest_end
