# Integration test for the ITestFixture applet: the run's own pasteboards, never the user's.

section "The run's pasteboards"
status="$(itest_call omc.test.status)"
check_contains "the engine uses the harness's prefix" "\"pasteboardPrefix\": \"$ITEST_PASTEBOARD_PREFIX\"" "$status"
check_contains "nothing skipped yet" '"skippedPastes": 0' "$status"

section "A handler copies to the general pasteboard"
run="$(itest_run fixture.copy --text "hi there")"
itest_wait_idle
check "the handler ran" "copy done" "$(itest_output "$run")"
check "the text is on the run's general pasteboard" "copied:hi there" "$(itest_pasteboard)"

section "A pasteboard a handler names itself"
run="$(itest_run fixture.handoff)"
itest_wait_idle
check "the handler reads back what it wrote" "handoff:handoff" "$(itest_output "$run")"
check "under the run's prefix" "handoff" "$(itest_pasteboard fixture_handoff)"

section "A command that takes the clipboard as its text"
itest_set_pasteboard "from the test"
run="$(itest_run fixture.clip)"
itest_wait_idle
check "the engine read the run's general pasteboard" "clip:from the test" "$(itest_output "$run")"

section "PASTE_AFTER_EXECUTION sends no keystrokes"
run="$(itest_run fixture.paste)"
itest_wait_idle
check "the handler ran" "paste handler ran" "$(itest_output "$run")"
check_contains "the paste was skipped and counted" '"skippedPastes": 1' "$(itest_call omc.test.status)"
