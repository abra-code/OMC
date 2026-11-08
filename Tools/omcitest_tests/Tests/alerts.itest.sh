# Integration test for the ITestFixture applet: alert and notify record and answer, nothing is shown.

section "The run's support folder"
run="$(itest_run fixture.confirm)"
itest_wait_idle
output="$(itest_output "$run")"
check_contains "handlers get the run's support folder" "support:$ITEST_WORK/support" "$output"
check "an alert with no answer queued answers OK" "answer:0" "$(printf '%s\n' "$output" | /usr/bin/head -n 1)"
check "it was recorded" "1" "$(alerts_count)"
check "with its text" "1" "$(alerts_mention "Delete the report?")"

section "Queued alert answers"
alerts_reset
alert_answer 1 2
run="$(itest_run fixture.confirm)"
itest_wait_idle
check "the first answer" "answer:1" "$(itest_output "$run" | /usr/bin/head -n 1)"
run="$(itest_run fixture.confirm)"
itest_wait_idle
check "the second answer" "answer:2" "$(itest_output "$run" | /usr/bin/head -n 1)"
check "two alerts since the reset" "2" "$(alerts_count)"

section "Notifications"
run="$(itest_run fixture.notify)"
itest_wait_idle
check "the handler ran" "notified:0" "$(itest_output "$run")"
check "one notification" "1" "$(notify_count)"
check "with its text" "1" "$(notify_mention "Export finished")"

section "The other tools are the real ones"
run="$(itest_run fixture.copy --text "through the support folder")"
itest_wait_idle
check "the pasteboard tool works through the link" "copied:through the support folder" "$(itest_pasteboard)"

section "The engine's own alerts: a WARNING confirmation"
# Not the alert tool above: the engine asks before it runs a command with WARNING, and a test
# launch answers from the queue it shares with the panels (itest_answer_alert).
warned() { # how many times fixture.warn ran
    if [ -f "$ITEST_WORK/warn.txt" ]; then /usr/bin/awk 'END { print NR }' "$ITEST_WORK/warn.txt"; else printf 0; fi
}
itest_panels_clear
itest_answer_alert default
itest_run fixture.warn > /dev/null
itest_wait_idle
check "Execute runs the command" "1" "$(warned)"
check "the confirmation was recorded" "alert" "$(itest_panel last kind)"
check "a caution" "caution" "$(itest_panel last level)"
check "with the command's text" "Greet everyone?" "$(itest_panel last message)"
check "and its buttons, default first" "$(printf 'Greet\nKeep Quiet')" "$(itest_panel last buttons)"
check "answered with the default" "default" "$(itest_panel last button)"
itest_answer_alert alternate
itest_run fixture.warn > /dev/null
itest_wait_idle
check "the alternate button does not run it" "1" "$(warned)"
check "and is recorded" "alternate" "$(itest_panel last button)"
itest_run fixture.warn > /dev/null
itest_wait_idle
check "with no answer queued it does not run either" "1" "$(warned)"
check "the alert took its alternate button" "alternate" "$(itest_panel last button)"
check "and says why" "no answer was queued" "$(itest_panel last problem)"
check "nothing was shown or left waiting" "true" "$(itest_call omc.test.status | /usr/bin/sed -n 's/.*"idle": \([a-z]*\).*/\1/p')"

section "Alerts and panels share one queue, in order"
itest_answer_save "$ITEST_WORK/never.txt"
itest_run fixture.warn > /dev/null
itest_wait_idle
check "an answer for a panel does not answer an alert" "the queued answer is for a panel" "$(itest_panel last problem)"
check "so the command does not run" "1" "$(warned)"
itest_answer_alert default
itest_run fixture.save > /dev/null
itest_wait_idle
check "and an alert answer cancels a panel" "true" "$(itest_panel last canceled)"
check "saying so" "the queued answer is for an alert" "$(itest_panel last problem)"
itest_answer_alert other
itest_run fixture.warn > /dev/null
itest_wait_idle
check "an alert without a third button" "the alert has no other button" "$(itest_panel last problem)"
check "takes Cancel, so the command does not run" "1" "$(warned)"
check_contains "an alert answer needs a button" "-32602" "$(itest_call omc.test.answer '{"kind": "alert"}' 2>&1)"

section "A version warning"
itest_answer_alert default
itest_run fixture.version > /dev/null
itest_wait_idle
check "Try Anyway runs a command that needs a newer OMC" "tried" "$(/bin/cat "$ITEST_WORK/version.txt" 2>/dev/null)"
check "its buttons" "$(printf 'Try Anyway\nCancel')" "$(itest_panel last buttons)"
itest_run fixture.version > /dev/null
itest_wait_idle
check "with no answer it does not run" "tried" "$(/bin/cat "$ITEST_WORK/version.txt" 2>/dev/null)"

section "An END_NOTIFICATION notice is recorded, not shown"
itest_answer_alert default
run="$(itest_run fixture.notice)"
itest_wait_idle
check "the command ran" "noticed" "$(itest_output "$run")"
check "its notice was recorded" "notice" "$(itest_panel last kind)"
check "with its title" "Fixture Done" "$(itest_panel last title)"
check "and message" "The fixture finished." "$(itest_panel last message)"
check_contains "it took no answer" '"pending": 1' "$(itest_call omc.test.panels)"
itest_panels_clear
