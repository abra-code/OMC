---
id: agent-tips
level: 1
flavors: [claude, capable, lite]
---

## Hard Rules for Agents — read before writing scripts

Each of these caused a real applet failure for an AI agent. The full
explanations, workaround tables, a script test harness, and a debug-logging
recipe are in `docs/omc_agent_tips_and_troubleshooting.md` — read it when any
of these bites or when behavior can't be explained from the code.

1. **`.sh` scripts run under `/bin/sh` = macOS bash 3.2 in POSIX mode.** There
   is no bash 4/5 on macOS. Process substitution (`done < <(cmd)`),
   `mapfile`, `declare -A`, and `${var,,}` are fatal parse errors that kill
   the script mid-file with no UI feedback. **Validate with `sh -n`, never
   `bash -n`** — `bash -n` passes scripts that die under OMC.
2. **Window init code goes in `INIT_SUBCOMMAND_ID`** (runs before the window
   appears). A non-blocking window's main command script runs at an
   unpredictable time — keep it `exit 0`.
3. **Views inside a not-yet-loaded `LoadableView` can't be targeted** by
   `omc_dialog_control`. Populate them in their `viewDidLoadActionID` handler
   from state files; have init write its readiness file last (atomic `mv`)
   and let handlers poll for it.
4. **Never set a Table's value** — it replaces the rows with one string, not
   the selection. There is no programmatic row-select; track the current item
   in a state file. Feed rows via `omc_table_set_rows_from_stdin`; extra
   tab-separated fields beyond the declared columns act as hidden columns
   (read via `$OMC_ACTIONUI_TABLE_<ID>_COLUMN_<N>_VALUE`).
5. **Pickers deliver (and are set by) the 1-based option INDEX**, not the
   option title; TabView delivers the 0-based tab index as trigger context.
   Persist each picker's ordered option list to a state file and resolve
   index → name in handlers. Validate every control-event value before using
   it — programmatic options/value updates can fire actions with bogus values.
6. **When runtime behavior can't be determined from code, instrument it**:
   add a `dbg()` logger to `/tmp` (gated on a flag file), log
   `$OMC_ACTIONUI_TRIGGER_VIEW_ID/_PART_ID/_CONTEXT` in every handler, ask
   the user to perform the UI operation once, read the log back. Don't guess.
