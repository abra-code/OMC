# Integration test for the ITestFixture applet: save and open panels answered by the test.

/bin/mkdir -p "$ITEST_WORK/in/sub1" "$ITEST_WORK/in/sub2" "$ITEST_WORK/out"
printf 'data\n' > "$ITEST_WORK/in/input.txt"

section "A save panel takes the queued path"
itest_answer_save "$ITEST_WORK/out/report.txt"
run="$(itest_run fixture.save)"
itest_wait_idle
check "the handler got the answered name" "saved:report.txt" "$(itest_output "$run")"
check "and wrote to the answered path" "saved" "$(/bin/cat "$ITEST_WORK/out/report.txt" 2>/dev/null)"
check "one panel so far" "1" "$(itest_panel_count)"
check "it was a save panel" "save" "$(itest_panel last kind)"
check "with the command's message" "Save the report" "$(itest_panel last message)"
check "its button prompt" "Export" "$(itest_panel last prompt)"
check "its default name" "report.txt" "$(itest_panel last defaultName)"
check "its content types" "public.plain-text" "$(itest_panel last allowedContentTypes)"
check "answered, not canceled" "false" "$(itest_panel last canceled)"

section "An open panel for one file"
itest_answer_open "$ITEST_WORK/in/input.txt"
run="$(itest_run fixture.choose)"
itest_wait_idle
check "the handler got the chosen file" "chose:$ITEST_WORK/in/input.txt" "$(itest_output "$run")"
check "the panel took files only" "true false" "$(itest_panel last canChooseFiles) $(itest_panel last canChooseDirectories)"

section "Several folders where the panel allows several"
itest_answer_open "$ITEST_WORK/in/sub1" "$ITEST_WORK/in/sub2"
run="$(itest_run fixture.folder)"
itest_wait_idle
output="$(itest_output "$run")"
check_contains "the handler got the first folder" "$ITEST_WORK/in/sub1" "$output"
check_contains "and the second" "$ITEST_WORK/in/sub2" "$output"
check "the record lists both" "2" "$(itest_panel last paths | /usr/bin/wc -l | /usr/bin/tr -d ' ')"

section "Canceled panels do not run the command"
itest_answer_cancel
run="$(itest_run fixture.choose)"
itest_wait_idle
check "a cancel answer cancels" "true" "$(itest_panel last canceled)"
check "and the handler did not run" "" "$(itest_output "$run")"
run="$(itest_run fixture.choose)"
itest_wait_idle
check "no answer queued cancels too" "no answer was queued" "$(itest_panel last problem)"
check "and the handler did not run either" "" "$(itest_output "$run")"

section "Answers the panel could not have given are refused"
itest_answer_open "$ITEST_WORK/in/sub1"
itest_run fixture.choose > /dev/null
itest_wait_idle
check "a folder for a files-only panel" "a folder for a panel that takes only files" "$(itest_panel last problem)"
itest_answer_open "$ITEST_WORK/in/input.txt" "$ITEST_WORK/in/input.txt"
itest_run fixture.choose > /dev/null
itest_wait_idle
check "several paths for a single-item panel" "several paths for a panel that takes one" "$(itest_panel last problem)"
itest_answer_open "$ITEST_WORK/in/missing.txt"
itest_run fixture.choose > /dev/null
itest_wait_idle
check "a path that does not exist" "an answered path does not exist" "$(itest_panel last problem)"
itest_answer_save "$ITEST_WORK/nowhere/report.txt"
itest_run fixture.save > /dev/null
itest_wait_idle
check "a save path in a missing folder" "the folder of the answered save path does not exist" "$(itest_panel last problem)"
itest_answer_save "$ITEST_WORK/out"
itest_run fixture.save > /dev/null
itest_wait_idle
check "a save path that names a folder" "a folder for a save panel" "$(itest_panel last problem)"
itest_answer_open "$ITEST_WORK/in/input.txt"
itest_run fixture.save > /dev/null
itest_wait_idle
check "an open answer for a save panel" "the queued answer is for an open panel" "$(itest_panel last problem)"

section "The open panel for a command's own files"
itest_answer_open "$ITEST_WORK/in/input.txt"
run="$(itest_run fixture.files --open-panel)"
itest_wait_idle
check "the command ran on the answered file" "files:$ITEST_WORK/in/input.txt" "$(itest_output "$run")"
check "its message" "Pick the inputs" "$(itest_panel last message)"
panels_before="$(itest_panel_count)"
run="$(itest_run fixture.files)"
itest_wait_idle
check "without --open-panel no panel is shown" "$panels_before" "$(itest_panel_count)"
check "and the command does not run" "" "$(itest_output "$run")"

section "Clearing"
itest_answer_cancel
itest_panels_clear
check "no records after clearing" "0" "$(itest_panel_count)"
run="$(itest_run fixture.choose)"
itest_wait_idle
check "the dropped answer is not used" "no answer was queued" "$(itest_panel last problem)"
