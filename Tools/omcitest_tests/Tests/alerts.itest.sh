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
