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

section "A command run as the window's subcommand (--window)"
itest_set_value "$window" 2 "Window"
run="$(itest_run fixture.greet --window "$window")"
itest_wait_idle
check "the window ran it with its own field" "Hello, Window" "$(itest_value "$window" 4)"
check_contains "the run says the window took it" '"dispatchedToWindow": true' "$(itest_call omc.test.log "{\"run\": $run}")"
run="$(itest_run fixture.no.such.command --window "$window")"
itest_wait_idle
log="$(itest_call omc.test.log "{\"run\": $run}")"
check_contains "an unknown command does not count as taken" '"dispatchedToWindow": false' "$log"
check_contains "and fails, as from the menu" '"status": -128' "$log"
check_contains "an unknown window is refused" "-32602" "$(itest_run fixture.greet --window NOT-A-WINDOW 2>&1)"
check_contains "and so is --window with --key-window" "-32602" "$(itest_run fixture.greet --window "$window" --key-window 2>&1)"

section "Closing the window as its close button does"
check_contains "an unknown window is refused" "-32602" "$(itest_close NOT-A-WINDOW 2>&1)"
check_contains "the close is taken" '"closing": true' "$(itest_close "$window")"
itest_wait_idle
check "its end command ran, while the window still had its values" "closed:Window" "$(/bin/cat "$ITEST_WORK/closed.txt" 2>/dev/null)"
# The engine no longer has the window. (actionui.listWindows still names it: OMC does not remove a
# closed window's ActionUI model, reported to the owner.)
check_contains "the closed window is refused" "-32602" "$(itest_close "$window" 2>&1)"

section "A private home and the applet under test"
run="$(itest_run fixture.env)"
itest_wait_idle
output="$(itest_output "$run")"
check "handlers get the file's private home" "home:$ITEST_HOME" "$(printf '%s\n' "$output" | /usr/bin/sed -n 1p)"
check "and its private temporary folder" "tmp:$ITEST_TMPDIR" "$(printf '%s\n' "$output" | /usr/bin/sed -n 2p)"
check "inside the test's folder" "yes" "$(case "$ITEST_HOME" in ("$ITEST_WORK"/*) printf yes ;; (*) printf no ;; esac)"
check "ITEST_APP names the applet" "yes" "$([ -f "$ITEST_APP/Contents/Resources/Command.json" ] && printf yes || printf no)"
