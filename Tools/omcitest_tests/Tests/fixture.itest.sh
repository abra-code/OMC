# Integration test for the ITestFixture applet: real engine, real window.

section "Lifetime and status"
check "app.did.launch ran before the test" "did.launch" "$(/bin/cat "$ITEST_WORK/lifetime.txt" 2>/dev/null)"
status="$(itest_call omc.test.status)"
check_contains "idle after launch" '"idle": true' "$status"

section "A command's output"
run="$(itest_run fixture.echo --text "hi there")"
itest_wait_idle
check "the echo run finished" "yes" "$(itest_run_finished "$run")"
check "its output" "echo:hi there" "$(itest_output "$run")"

section "The window, a click and a next command"
before="$(itest_windows)"
itest_run ITestFixture > /dev/null
itest_wait_idle
window="$(itest_new_window "$before")"
check "the main command opened a window" "yes" "$([ -n "$window" ] && printf yes || printf no)"
check "INIT_SUBCOMMAND_ID wrote the label" "ready" "$(itest_value "$window" 4)"
itest_set_value "$window" 2 "Tom"
check "the button's actionID" "fixture.greet" "$(itest_click "$window" 3)"
itest_wait_idle
check "the handler saw the field and wrote the greeting" "Hello, Tom" "$(itest_value "$window" 4)"
check "NEXT_COMMAND_ID ran after it" "after ran" "$(itest_value "$window" 5)"
