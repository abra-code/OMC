# OMC Skill

A multi-flavor AI agent skill that teaches a model how to build and debug OMC applets for macOS.

`Skill/SKILL.md` is the committed `claude` flavor, generated from `master/`. Other flavors live under `dist/` and are gitignored — build them with `Skill/build_skill.py` before installing.

## Layout

```
Skill/
├── master/                       canonical source of truth
│   ├── skill.meta.json           flavor definitions + content manifest
│   └── content/                  modular Markdown content pieces (level 1 = core, level 2 = reference)
│       ├── 01-core.md            what OMC is + applet bundle structure + Command.plist format
│       ├── 02-env-tools.md       key environment variables + six runtime tools
│       ├── 03-execution-modes.md all execution/activation modes, dialog keys, app lifetime events
│       ├── 04-ui-dialog.md       NIB + ActionUI dialog integration overview
│       ├── 05-appletbuilder.md   AppletBuilder workflow: create, edit, build
│       ├── 06-script-patterns.md shared lib pattern, state management, command chaining
│       ├── 07-examples.md        few-shot examples (lite only)
│       └── 08-reference.md       pointer to docs/ for full reference material
│
├── SKILL.md                      generated; claude flavor; committed
├── build_skill.py                assembles SKILL.md files and packages dist/
├── install_skill.py              deploys a built flavor to a target location
└── dist/                         generated build output; gitignored
    ├── claude/                   Anthropic Claude Code skill package
    ├── capable/                  Gemini / Grok / GPT-4o / Llama-3-70B+
    └── lite/                     Phi-3 / Mistral-7B / local-model class
```

The human reference material in `Documentation/` is the same across all flavors; only the SKILL.md prose layer differs.

## Flavors

| Flavor    | Target                                     | Levels | Script execution | Tables |
|-----------|--------------------------------------------|--------|------------------|--------|
| `claude`  | Anthropic Claude Code (`.claude/skills/`)  | 1 + 2  | yes              | yes    |
| `capable` | Gemini, Grok, GPT-4o, Llama-3-70B+         | 1 + 2  | no               | yes    |
| `lite`    | Phi-3, Mistral-7B, Llama-3-8B class        | 1 only | no               | no     |

## Build

```bash
python3 Skill/build_skill.py                 # all flavors
python3 Skill/build_skill.py --flavor claude # one flavor
python3 Skill/build_skill.py --master-only   # regenerate Skill/SKILL.md only
```

The build also refreshes the committed `Skill/SKILL.md` (claude flavor) so Claude Code picks it up without a build step in consuming repos.

## Install

```bash
# Anthropic Claude Code, current project: drops into ./.claude/skills/omc/
python3 Skill/install_skill.py claude

# Or into a specific project / user level
python3 Skill/install_skill.py claude --dest /path/to/project
python3 Skill/install_skill.py claude --user

# Capable model: write the SKILL.md to a file to paste/attach
python3 Skill/install_skill.py capable --out ~/Desktop/omc-capable.md

# Lite (small/local): same; or pipe to stdout
python3 Skill/install_skill.py lite --print | pbcopy
```

The installer auto-runs the build if the requested flavor isn't in `dist/` yet.

### Deployment notes per flavor

- **claude** — installs as a Claude Code skill: `.claude/skills/omc/{SKILL.md,docs/}`. The frontmatter `description` and `name` in SKILL.md govern when the skill activates. The bundled docs are reachable from the agent via the relative paths referenced in SKILL.md.
- **capable** — paste `SKILL.md` into the model's system prompt, or attach as a document for tools that support per-request context.
- **lite** — same as capable, but prefer the trigger keywords in the frontmatter so the model only engages when the user explicitly mentions OMC. Tables are stripped from this flavor's SKILL.md to keep the token count low.

## Editing rules

- Edit only files under `master/`. Generated `SKILL.md` and `dist/` will be overwritten on the next build.
- Each content piece has YAML frontmatter declaring its `id`, `level`, and `flavors`. The manifest entry in `skill.meta.json` is authoritative for build-time filtering.
- `Documentation/` is the source of truth for OMC behavior. When updating reference tables in content files, cross-check against the docs there.
