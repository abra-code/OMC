# AppletBuilder test suite

AppletBuilder is an OMC applet, so all of its logic lives in handler scripts under
`AppletBuilder.app/Contents/Resources/Scripts/`. This suite runs those handlers
headlessly through `omctest`, the harness AppletBuilder itself ships.

    appletbuilder test Distribution/AppletBuilder.app

or the **Test** button in AppletBuilder's own Build & Run pane, with AppletBuilder
open as a project in itself. `Documentation/omctest_guide.md` is the reference for
writing the files; this README is the map of what AppletBuilder does and how much
of it is covered.

Current state: **285 checks across 4 files, all passing** (281 where `defaults`
cannot reach cfprefsd - see section 4 - which skips one section and says so).

---

## 1. What AppletBuilder is, structurally

| Piece | Where | What it is |
|---|---|---|
| 91 commands | `Resources/Command.json` | one per UI action, dispatched by `COMMAND_ID` |
| 110 handler scripts | `Resources/Scripts/` | the actual logic, one file per command plus 9 shared libs |
| 14 window documents | `Resources/Base.lproj/*.json` | ActionUI windows, sheets and the menu bar |
| 5 applet templates | `Resources/Templates/*.applet` | what "New Applet" copies from |
| 2 verifiers | `Contents/Library/{command,actionui}_verifier/` | Python schema validators |
| agent CLI | `Resources/Agents/appletbuilder` | `create`/`validate`/`build`/`test`/`prettify`/`preview` |
| the harness | `Resources/Agents/omctest.sh` | shipped here, used by every OMC applet |

The shared libraries are where the reusable logic is, and where most of the value
of testing is concentrated:

| Lib | Responsibility |
|---|---|
| `lib.common.sh` | view ids, per-window state keys, UI setters, the `ab_log`/`ab_report`/`ab_confirm` reporting indirection |
| `lib.build.sh` | the whole build pipeline: validate, framework/Python refresh, thin, junk sweep, codesign, run tests |
| `lib.create.sh` | New Applet: copy a template, rename everything in it, install binaries and icon |
| `lib.validate.sh` | script/command/ActionUI validation |
| `lib.plist.sh` | Info.plist and Command.json read/write/edit |
| `lib.tables.sh` | the three list views |
| `lib.prefs.sh` | two user settings in a `defaults` domain |
| `lib.errors.sh`, `lib.help.sh` | error/reference output windows, Markdown-to-HTML help cache |

**The reporting indirection is the key design fact for testing.** Pipeline code
never touches the UI directly: it calls `ab_log`, `ab_report` and `ab_confirm`,
which the GUI handlers override and the CLI leaves pointing at stderr. That is why
a build phase can be tested by reading its transcript instead of a window
(`ab_call_log` in `lib.test.appletbuilder.sh`).

---

## 2. Functional areas, and coverage

| # | Area | Handlers | Covered by | State |
|---|---|---|---|---|
| A | Dispatch and project lifecycle | `main`, `project*`, `save`, `reveal` | `10-project` | good |
| B | General tab / Info.plist identity | `general.*` (7) | `10-project` | good |
| C | The three editors: UI Files, Scripts, Commands | `uifiles.*` (15), `scripts.*` (12), `commands.*` (14) | `20-editors` | good |
| D | Validation | `lib.validate.sh`, `*.validate` | `30-validation` | good |
| E | Build hygiene and the junk sweep | `clean_build_junk`, `validate_project` | `40-build-hygiene` | good |
| F | Agent CLI | `Agents/appletbuilder` | `30-validation` s13 | smoke only |
| G | New Applet creation | `new.*` (10), `lib.create.sh` | - | **not covered** |
| H | Services (NSServices) editing | `services.*` (5) | partial (picker feed only) | **thin** |
| I | Build pipeline proper | `build`, `run`, `buildrun.loaded` | - | **not covered** |
| J | Help viewer | `help.*` (10), `lib.help.sh` | - | **not covered** |
| K | Settings | `settings.*` (3) | - | **not covered** |
| L | Error/reference windows | `show.errors`, `show.reference` | indirectly, via `chain_asked` | thin |

### What each test file establishes

**`10-project.test.sh`** (55 checks) - the path before anything else. `main` routes
a dropped `.app` to the project window and anything else to New Applet, and refuses
a directory named `.app` with no `Info.plist`. `project.init` and `general.loaded`
both claim the applet from the hand-off pasteboard (they race, and either can win).
The General tab shows the applet's identity and feeds the Services command picker.
Renaming derives a bundle id, writes it through to the plist, and is a no-op when
the name has not actually changed. `cleanup_state` clears every key, not just the
path.

**`20-editors.test.sh`** (127 checks) - the same machine three times over: a table,
a detail pane, a dirty flag, a fingerprint of the file as loaded, and a three-way
alert when the file changed underneath. All three branches of that alert are
exercised, because that is where a wrong answer silently destroys a user's work:
Save Anyway overwrites, Reload from Disk keeps the disk copy and does not write,
Cancel leaves both copies alone and keeps the document dirty. Also: the UI Files
table excludes the command manifest, a `.nib` gets only the buttons that apply to
it, Prettify and Validate report through the error window, the Commands tab edits
one manifest entry in place, and invalid JSON never reaches the manifest. Two sections guard things a handler
test cannot reach on its own: that a manifest save leaves the file's permissions
alone, and that every `mktemp` template in the shipped bundle - handlers, agent
CLI, helpers and the applet templates themselves - ends in its `X`s.

**`30-validation.test.sh`** (69 checks) - the gate every build passes through.
Scripts are checked with the shell OMC would actually run them with, so bash-only
syntax in a `.sh` file is an error with an explanation. The bash-4 heuristic scanner
is checked construct by construct, along with both of its escape hatches (comments,
`bash4-ok`) and a positive control that the same line unexempted still fires. Three
of its rules provably cannot fire and the file pins down why. Also: manifest and
ActionUI validation, `Command.json`-over-`Command.plist` resolution, framework
version comparison (including `5.10` above `5.9`), and unique command id generation.

**`40-build-hygiene.test.sh`** (36 checks) - what the build refuses to ship.
`clean_build_junk` is the last thing between a working tree and a signed artifact,
and the property under test is that it is **loud**: it names what it removed, names
config directories individually rather than folding them into a count, reports a
repository inside the bundle and never deletes it, sweeps a symlink wearing a junk
name without touching its target, and escalates junk that survived. Profiling
droppings are a validation warning that names the file rather than a silent delete,
because the file is evidence of its own cause.

---

## 3. Known gaps, and why

**New Applet creation (area G) is the largest.** `applet_create_from_template`
calls `xcrun actool`, `xcrun ibtool` and `lsregister` by absolute path, and OMC
convention means those cannot be intercepted through `$OMC_OMC_SUPPORT_PATH`. The
guide's answer is a convention in the applet, not a mechanism in the harness: route
them through overridable variables (`AB_ACTOOL_TOOL`, `AB_IBTOOL_TOOL`) the way
`$python3` already is. Until then, the parts of the pipeline that do not need them
(name and bundle-id derivation, the Python-vs-shell main script choice, clone
detection, icon cleanup) are testable and the parts that do are not.

**The build pipeline proper (area I)** ends in `codesign_applet.sh`. Signing is
safe to run for real but slow and identity-dependent; the phases before it are
already covered through `40-build-hygiene`.

**The help viewer (area J)** renders Markdown into a WebView. The conversion is
testable (`ensure_help_docs_converted` is a staleness check over mtimes); the
viewer is not.

**Known defect, fix pending: validation writes `__pycache__` into the bundle.**
Each bundled verifier imports a package that lives inside the app, with no
`PYTHONPYCACHEPREFIX` set, so `Contents/Library/{command,actionui}_verifier/verifier/__pycache__`
appear on every `appletbuilder validate` - and therefore on every `test` and every
Build, since validation runs first. `md2html.py` does the same to
`Contents/Library/mistune` when Help is opened. `clean_build_junk` sweeps them
before codesigning, so nothing ships broken, but the bundle is written into during
ordinary use. Once fixed, this file should gain a check that a validation run
leaves no `__pycache__` under `Contents/Library` - it would pass vacuously today.

**Nothing here tests the engine.** The harness simulates the documented contract in
`omc_runtime_context_reference.md`. It also never synthesizes UI events, so a
typo'd `actionID` is invisible to these tests - `appletbuilder validate` is what
catches that, and it runs first on every `test` invocation.

---

## 4. Three things specific to testing this applet

**Its documents are other applets.** Fixtures are whole `.app` bundles, built at run
time by `ab_make_project` from the templates the bundle already ships. Nothing
binary is committed, and the fixtures cannot drift from what New Applet produces.
`ab_make_project` sweeps junk out of the copy, so a `.DS_Store` or a `__pycache__`
sitting in the developer's template tree cannot make a test non-deterministic.

**It keeps two settings in a `defaults` DOMAIN.** cfprefsd keys the user domain by
uid rather than by `$HOME`, so no test run can isolate it - omctest reports the
construct at the start of every run. `lib.prefs.sh` therefore reads its domain from
`AB_PREFS_DOMAIN`, and `ab_prefs_isolate` points that at a plist inside the
per-file fake home. `defaults` accepts a path in place of a domain, so the same code
runs against a file that dies with the scratch.

`defaults` is fussy about the path in two ways that both fail SILENTLY - it exits
0 having written nothing:

- **It will not write through a symlink.** `$TMPDIR` lives under `/var`, which is
  a symlink to `/private/var`, so the isolated domain has to be the physical path.
  `ab_prefs_isolate` resolves it with `pwd -P`.
- **It cannot reach cfprefsd from a sandbox** that has no access to the Mach
  service.

Either one would leave every preferences assertion quietly describing the built-in
fallback instead of a stored value. Two things guard against that: `ab_prefs_usable`
probes for a working `defaults` and `ab_skip_section` says so out loud when there
is not one, and section 14 of `10-project.test.sh` asserts `check_exists` on the
isolated file itself. The `check_exists` is what actually caught the symlink case.

**Do not mutation-test the seam by reverting `lib.prefs.sh` without protection.**
With the seam gone the suite writes `BundleIDPrefix` and `ExternalEditor` into the
real `com.abracode.applet-builder` domain - which is the hazard the seam exists to
prevent, so it is working as designed, but the keys have to be deleted afterwards.

**Compare paths as paths.** macOS hands an app a `TMPDIR` with a trailing slash, so
the harness scratch carries an interior `//` that any code doing `cd`/`pwd` removes.
Two spellings of the same directory can coexist inside one run.

---

## 5. Adding to the suite

Files run in lexical order, each in its own environment; no registration step.
Name them `NN-topic.test.sh`. Put AppletBuilder-specific vocabulary in
`lib.test.appletbuilder.sh` rather than in a file - it already provides:

| Helper | Use |
|---|---|
| `ab_make_project <Name> [template]` | build a fixture applet in `$OMCTEST_WORK` |
| `ab_add_executable <app>` | give it a `Contents/MacOS/<exe>` |
| `ab_open_project <path>` | what `project.init` would have recorded |
| `ab_pb_get` / `ab_pb_set <PB_KEY>` | the applet's per-window state |
| `ab_reset_state` | clear every key it keeps, not just the path |
| `ab_call <lib> <fn> [args]` | call a library function directly |
| `ab_call_rc` / `ab_call_out` / `ab_call_log` | its exit code / a global it set / what it reported |
| `ab_py <module> <expr> [args]` | evaluate against a Python helper module |
| `ab_cli <args>` | the agent CLI |
| `ab_prefs_usable` | whether `defaults` can actually write here (see section 4) |
| `ab_skip_section <why>` | print a greppable SKIP line when a precondition is absent |

`AB_STATE_KEYS` holds every per-window key the applet keeps, imported from
`lib.common.sh` rather than listed here, so a key added to the applet is reset
and asserted on without anyone remembering to update the suite.
| `ab_command_file <app>` | the manifest the applet would resolve |

**Before believing a new check, break the thing it names and watch it go red.**
Every section in this suite was verified that way; the mutations used are recorded
in the commit notes. A check that cannot fail is worse than no check, because it
reads as coverage.
