---
id: reference
level: 1
flavors: [claude, capable]
---

## Reference Documentation

Full OMC reference is in the `docs/` folder (also bundled in `AppletBuilder.app/Contents/Resources/Documentation/`):

| File | Contents |
|------|----------|
| `docs/omc_agent_tips_and_troubleshooting.md` | **For AI agents**: sh-vs-bash fatal syntax, script test harness, init/LoadableView lifecycle, table & picker runtime semantics, debug-logging workflow, pre-flight checklist — with real failure case studies |
| `docs/building_omc_applet.md` | Step-by-step applet creation guide with all details |
| `docs/omc_applet_catalog.md` | **Before building a new applet**: a classified inventory of every working applet in the collection - which one to clone for a batch converter, document editor, inspector, query builder, pipeline, or local-AI app, which are NIB-based (not agent-editable), and where to find each UI technique |
| `docs/appletbuilder_user_guide.md` | UI navigation reference for the AppletBuilder GUI app (for human users) |
| `docs/omc_command_reference.md` | Complete `Command.plist` key reference — all execution modes, dialog keys, output window settings, progress dialogs, input dialogs, services |
| `docs/omc_runtime_context_reference.md` | Every `$OMC_*` environment variable and `__SPECIAL_WORD__` substitution |
| `docs/omctest_guide.md` | **Writing tests**: the `Tests/` layout, the full helper API (driving the window, dispatching handlers, asserting on the virtual window), which `omc_dialog_control` verbs replay, the seam contract for binaries the harness cannot intercept, and how to write checks that can actually fail |
| `docs/omc_scripting_guide.md` | Shell script patterns: reading controls, updating UI, tables, state, debugging |
| `docs/omc_python_scripting_guide.md` | Python handlers: env (`PATH`/`PYTHONPATH`/`Packages`), equivalents of all shell patterns, installing deps into `Contents/Library/Packages`, and thinning the embedded Python (the `thin_applet_python.sh` plan/apply workflow) |
| `docs/omc_dialog_control--help.md` | Full `omc_dialog_control` command reference with all operations |
| `docs/omc_next_command--help.md` | `omc_next_command` reference |
| `docs/alert--help.md` | `alert` tool reference with all flags |
| `docs/pasteboard--help.md` | `pasteboard` tool reference |
| `docs/notify--help.md` | `notify` tool reference |
| `docs/plister--help.md` | `plister` plist tool reference |
| `docs/omc_services_reference.md` | macOS Services integration via `NSServices` in `Info.plist` |
| `docs/Nib-Guide.md` | Nib dialog creation: editing in Xcode, control classes, connecting to OMC |
| `docs/nib_to_actionui_migration.md` | **Porting a NIB applet off Interface Builder**: eleven ordered steps, each with a check to verify before moving on - assessing whether the nib can be transcribed or must be reconstructed, reusing nib tags as ActionUI ids, the value-representation traps (empty `Picker` tags, Bool toggles, no initial selection, migrating old config files), layout, replacing an editable combo box, drop targets, manifest rewiring, the `eval`-quoting bug the port exposes, tests, and what only a human can confirm. Ends in a symptom index |
| `docs/omc_controls_user_defined_runtime_attributes.md` | All OMC control classes in Nibs and their settable properties |
| `docs/MenuBar-Guide.md` | Menu bar JSON (`MainMenu.json`) in 5.1 applets: `actionID` command wiring, the `autoPopulate` Commands menu, deletion via `replacing`, Open Recent — the base array-root format is in the ActionUI skill (`ActionUI-MenuBar-JSON-Guide.md`) |

When you need the exact keys for `NIB_DIALOG`, the complete list of `omc_dialog_control` operations, or the full env-var table, read the relevant `docs/` file directly.

For ActionUI JSON UI (element types, properties, validation, patterns): read the **ActionUI skill** (`../ActionUI/Skill/SKILL.md`). The OMC skill only covers how ActionUI connects to OMC — the JSON format itself is entirely in the ActionUI skill.
