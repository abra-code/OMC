#!/bin/sh
# Tests/10-project.test.sh - opening a project, and the General tab.
#
# Covers the path a user takes before anything else: drop an applet on
# AppletBuilder, get the project window, see the applet's identity in it, edit
# that identity. The commands/scripts/UI-files editors are 20-editors.test.sh.
. "${OMCTEST_LIB:?set OMCTEST_LIB, or run via: appletbuilder test}"
. "$OMCTEST_TESTS/lib.test.appletbuilder.sh"

section "1. the main command routes on what was dropped"

chains_reset
ab_reset_state
project="$(ab_make_project Widget)"
check_exists "the fixture applet was built" "$project"
check_exists "and it has the Info.plist main.sh looks for" "$project/Contents/Info.plist"

omc_object "$project"
omc_run AppletBuilder.main
check_status "main succeeded"                    0
check "it opened the project window"        "1"  "$(chain_asked AppletBuilder.project)"
check "and not the New Applet dialog"       "0"  "$(chain_asked AppletBuilder.new.applet)"
check "the dropped applet was stashed"  "$project" "$(ab_pending_get)"

section "2. anything that is not an applet opens New Applet instead"

chains_reset
ab_reset_state
notapp="$OMCTEST_WORK/notes.txt"
printf 'hello\n' > "$notapp"
omc_object "$notapp"
omc_run AppletBuilder.main
check_status "main succeeded"                    0
check "it opened the New Applet dialog"     "1"  "$(chain_asked AppletBuilder.new.applet)"
check "and not the project window"          "0"  "$(chain_asked AppletBuilder.project)"
check "nothing was stashed"                 ""   "$(ab_pending_get)"

section "3. a directory named .app without an Info.plist is not an applet"
# The check main.sh makes is the one that matters: a stale or half-copied bundle
# must not open a project window that cannot be populated.

chains_reset
ab_reset_state
hollow="$OMCTEST_WORK/Hollow.app"
/bin/mkdir -p "$hollow/Contents"
omc_object "$hollow"
omc_run AppletBuilder.main
check "it fell through to New Applet"       "1"  "$(chain_asked AppletBuilder.new.applet)"
check "and did not open a project window"   "0"  "$(chain_asked AppletBuilder.project)"

section "4. project.init takes the stashed applet and makes it the window's own"

ab_reset_state
ab_pending_set "$project"
omc_run AppletBuilder.project.init
check_status "project.init succeeded"            0
check "the window now owns the project" "$project" "$(ab_pb_get PB_PROJECT_PATH)"
check "and the hand-off slot was consumed"  ""   "$(ab_pending_get)"

section "5. project.init refuses an applet that is not there any more"
# The window would otherwise open onto a path every later handler fails on.

ab_reset_state
ab_pending_set "$OMCTEST_WORK/Vanished.app"
omc_run AppletBuilder.project.init
check_status "project.init reported failure"     1
check "and recorded no project"             ""   "$(ab_pb_get PB_PROJECT_PATH)"

section "6. the General tab shows the applet's identity"

ab_reset_state
ab_open_project "$project"
omc_run AppletBuilder.general.loaded
check_status "general.loaded succeeded"          0
check "the name field"        "Widget"                    "$(ui_value $GEN_NAME_ID)"
check "the header echoes it"  "Widget"                    "$(ui_value $GEN_HEADER_NAME_ID)"
check "the bundle identifier" "com.omc.applet.Widget"     "$(ui_value $GEN_BUNDLE_ID_ID)"
check "the version"           "1.0"                       "$(ui_value $GEN_VERSION_ID)"
check "the plist was fingerprinted for conflict detection" "yes" \
    "$([ -n "$(ab_pb_get PB_PLIST_HASH)" ] && echo yes || echo no)"

section "7. the Services command picker is fed from the project's own commands"

check "the picker was given options" "1" "$(ui_calls "$SVC_COMMAND_PICKER_ID.*omc_set_property")"
check "and they name this applet's command" "1" \
    "$(ui_prop $SVC_COMMAND_PICKER_ID options | /usr/bin/grep -c '"Widget"')"

section "8. general.loaded picks the project up from the hand-off slot too"
# general.loaded can win the race with project.init, so it has to be able to
# claim the applet itself - and to leave it claimed for the tabs behind it.

ab_reset_state
ab_pending_set "$project"
omc_run AppletBuilder.general.loaded
check_status "general.loaded succeeded"          0
check "it claimed the project"      "$project"   "$(ab_pb_get PB_PROJECT_PATH)"
check "and consumed the slot"       ""           "$(ab_pending_get)"
check "the name still loaded"       "Widget"     "$(ui_value $GEN_NAME_ID)"

section "9. with no project at all, the General tab writes nothing"

ab_reset_state
ui_reset
omc_run AppletBuilder.general.loaded
check_status "general.loaded still succeeded"    0
check "the name field was left alone"       ""   "$(ui_value $GEN_NAME_ID)"

section "10. renaming in the name field derives a bundle id and saves both"

ab_reset_state
renamed="$(ab_make_project Gadget)"
ab_open_project "$renamed"
omc_fire AppletBuilder.general.name.changed "$GEN_NAME_ID" "My New Tool"
check_status "name.changed succeeded"            0
check "a bundle id was derived"   "com.omc.applet.my-new-tool" "$(ui_value $GEN_BUNDLE_ID_ID)"
check "the header followed"       "My New Tool"  "$(ui_value $GEN_HEADER_NAME_ID)"
check "it said so"                "Name updated" "$(ui_value $GEN_STATUS_ID)"
check "and the plist really changed" "My New Tool" "$(ab_plist_read "$renamed" CFBundleName)"
check "identifier written through too" "com.omc.applet.my-new-tool" \
    "$(ab_plist_read "$renamed" CFBundleIdentifier)"

section "11. re-entering the name that is already saved changes nothing"
# The handler fires on every keystroke-committing edit, so "unchanged" has to be
# a no-op: otherwise it would overwrite a bundle id the user had hand-edited.

ui_reset
omc_fire AppletBuilder.general.name.changed "$GEN_NAME_ID" "My New Tool"
check_status "name.changed succeeded"            0
check "no status was reported"              ""   "$(ui_value $GEN_STATUS_ID)"
check "and no bundle id was pushed"         ""   "$(ui_value $GEN_BUNDLE_ID_ID)"

section "12. an empty name is ignored rather than saved"

ui_reset
omc_fire AppletBuilder.general.name.changed "$GEN_NAME_ID" ""
check_status "name.changed succeeded"            0
check "nothing was pushed to the form"      ""   "$(ui_value $GEN_BUNDLE_ID_ID)"
check "and the applet kept its name" "My New Tool" "$(ab_plist_read "$renamed" CFBundleName)"

section "13. closing the project forgets every key, not just the path"

# Driven off AB_STATE_KEYS rather than a hand-picked three. A key cleanup_state
# forgets is not cosmetic: a stale PB_CMD_HASH surviving close-and-reopen makes
# the next save compare against the fingerprint of a document that is no longer
# loaded - so the external-change alert is either skipped, and the user silently
# overwrites someone else's edit, or raised for a conflict that does not exist.
ab_reset_state
ab_open_project "$project"

for _k in $AB_STATE_KEYS; do
    ab_pb_set "$_k" "leftover"
done
# Positive control: without it a broken ab_pb_set would make every assertion
# below pass against keys that were never populated in the first place.
_set=0
for _k in $AB_STATE_KEYS; do
    [ "$(ab_pb_get "$_k")" = "leftover" ] && _set=$((_set + 1))
done
check "every key holds something before the sweep" "14" "$_set"

ab_call lib.common.sh cleanup_state

_left=""
for _k in $AB_STATE_KEYS; do
    [ -n "$(ab_pb_get "$_k")" ] && _left="$_left $_k"
done
check "cleanup_state cleared all of them"   ""   "$_left"

section "14. the remembered bundle-id prefix, through the isolation seam"
# This is the only place the AB_PREFS_DOMAIN seam is exercised. Without a section
# that actually WRITES a preference, every prefs assertion elsewhere describes
# the built-in fallback and the seam could be reverted with nothing going red.
#
# WARNING for anyone mutation-testing this: reverting lib.prefs.sh to the
# hardcoded domain makes this section write BundleIDPrefix and ExternalEditor
# into the developer's REAL com.abracode.applet-builder. That is the hazard the
# seam exists to prevent, so it is the seam working - but delete both keys
# afterwards:  defaults delete com.abracode.applet-builder BundleIDPrefix

if ab_prefs_usable; then
    /bin/rm -f "$AB_PREFS_DOMAIN"
    check "with nothing stored, the built-in default is used" "com.omc.applet." \
        "$(ab_call lib.prefs.sh get_bundle_id_prefix)"

    ab_call lib.prefs.sh save_bundle_id_prefix "com.acme.tools.Widget" >/dev/null 2>&1
    # The assertion that pins the seam down: the write landed in the isolated
    # file, not in the developer's real preferences.
    check_exists "the setting went to the isolated domain" "$AB_PREFS_DOMAIN"
    check "and it kept the prefix, not the whole id" "com.acme.tools." \
        "$(ab_call lib.prefs.sh get_bundle_id_prefix)"

    # And it is what a new applet's bundle id is then built from.
    ui_reset
    prefixed="$(ab_make_project Doohickey)"
    ab_open_project "$prefixed"
    omc_fire AppletBuilder.general.name.changed "$GEN_NAME_ID" "Second Tool"
    check "a later applet inherits the remembered prefix" "com.acme.tools.second-tool" \
        "$(ui_value $GEN_BUNDLE_ID_ID)"

    ab_call lib.prefs.sh save_external_editor "/Applications/Nothing.app" >/dev/null 2>&1
    check "the editor setting round-trips too" "/Applications/Nothing.app" \
        "$(ab_call lib.prefs.sh get_external_editor)"
else
    # `defaults` reaches cfprefsd over a Mach service. A sandboxed run cannot,
    # and it fails SILENTLY - exit 0, nothing written - so every check above
    # would quietly describe the fallback value instead of a stored one.
    ab_skip_section "preferences: defaults cannot reach cfprefsd in this environment"
    check "the fallback prefix is still correct" "com.omc.applet." \
        "$(ab_call lib.prefs.sh get_bundle_id_prefix)"
fi

section "15. a renamed applet's URL scheme replaces the template's, not joins it"
# plutil -replace on an array index inserts rather than overwrites, so a new
# applet once kept the template's scheme beside its own. New Applet and the
# General tab rename both go through applet_update_url_scheme.

schemed="$(ab_make_project Schemed)"
ab_call lib.build.sh applet_update_url_scheme "$schemed/Contents/Info.plist" "My Schemed App"
check "exactly one scheme, the new one" '["my-schemed-app"]' \
    "$(/usr/bin/plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes json -o - "$schemed/Contents/Info.plist" 2>/dev/null)"
check "the URL name followed" "My Schemed App" "$(ab_plist_read "$schemed" CFBundleURLTypes.0.CFBundleURLName)"

section "16. the scheme derived from a name is always a valid URL scheme"
# A scheme must start with a letter (RFC 3986).

check "a plain name"                 "my-tool"        "$(ab_call lib.build.sh applet_url_scheme_for_name "My Tool")"
check "punctuation is dropped"       "tools-v2"       "$(ab_call lib.build.sh applet_url_scheme_for_name "Tool's v2!")"
check "leading hyphens are dropped"  "tool"           "$(ab_call lib.build.sh applet_url_scheme_for_name " - Tool")"
check "a leading digit gets a prefix" "applet-123-app" "$(ab_call lib.build.sh applet_url_scheme_for_name "123 App")"
non_ascii_sum="$(printf '%s' "日本語" | /usr/bin/cksum | /usr/bin/awk '{print $1}')"
check "a name with nothing usable gets a checksum" "applet-$non_ascii_sum" \
    "$(ab_call lib.build.sh applet_url_scheme_for_name "日本語")"

section "17. URL scheme errors are reported, a missing URL type is not one"

no_url="$(ab_make_project NoURL)"
/usr/bin/plutil -remove CFBundleURLTypes "$no_url/Contents/Info.plist"
ab_call lib.build.sh applet_update_url_scheme "$no_url/Contents/Info.plist" "Other Name" 2>/dev/null
check "an applet with no URL type succeeds"   "0" "$?"
check "and still has none" "" "$(ab_plist_read "$no_url" CFBundleURLTypes)"

broken_plist="$OMCTEST_WORK/broken-Info.plist"
printf 'not a plist' > "$broken_plist"
broken_report="$(ab_call lib.build.sh applet_update_url_scheme "$broken_plist" "Other Name" 2>&1 >/dev/null)"
check "an unreadable Info.plist fails"        "1" "$?"
case "$broken_report" in
    "Cannot update the URL scheme, Info.plist is not readable:"*) broken_said="yes" ;;
    *) broken_said="$broken_report" ;;
esac
check "and says why"                          "yes" "$broken_said"

section "18. New Applet removes the copy when the URL scheme cannot be set"

broken_tmpl="$OMCTEST_WORK/Broken.applet"
/bin/rm -rf "$broken_tmpl"
/bin/cp -Rp "$AB_TEMPLATES/Empty.applet" "$broken_tmpl"
/bin/chmod -R u+w "$broken_tmpl"
printf 'not a plist' > "$broken_tmpl/Contents/Info.plist"
create_dest="$OMCTEST_WORK/create-dest"
/bin/rm -rf "$create_dest"
/bin/mkdir -p "$create_dest"
create_report="$(AB_NO_CODESIGN=1 ab_call lib.create.sh applet_create_from_template \
    "$broken_tmpl" "Never Made" "$create_dest" "" "" "" "" 2>&1 >/dev/null)"
check "create failed"                         "1" "$?"
case "$create_report" in
    *"Cannot update the URL scheme, Info.plist is not readable:"*) create_said="yes" ;;
    *) create_said="$create_report" ;;
esac
check "at the URL scheme step"                "yes" "$create_said"
check "and left nothing behind"               "" "$(/bin/ls -A "$create_dest")"

section "cumulative: no handler wrote to a view id the window does not declare"
check "no undeclared ids"    "" "$(ui_unknown_writes)"
check "no table was clobbered" "" "$(ui_suspect_writes)"
check "no harness misuse"    "" "$(ui_errors)"

omctest_end
