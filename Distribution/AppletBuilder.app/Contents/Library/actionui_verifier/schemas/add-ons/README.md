# Add-on element schemas

This directory holds verifier schemas for optional ActionUI **add-on** element types, kept
separate from the built-in element schemas in the parent directory (`ActionUIVerifier/Schemas/` in
the repo, `schemas/` in a packaged Python verifier).

Both verifiers (`Tools/verifier/validate_actionui.py` and the Swift `ActionUIVerifier` library,
which bundles this directory) auto-discover every `add-ons/<AddOn>/*.json` here, so documents that use
an add-on element type (for example the `QuickLook` element from the ActionUIQuickLook add-on)
validate without passing `--schema-dir`. Built-in schemas win on a name collision, so an add-on
cannot shadow a core element.

## How it is populated

In a checkout of the ActionUI repo this directory is normally empty: the verifiers also
auto-discover add-on sources directly from `<repo>/Add-ons/<AddOn>/Schemas/`, so no copy is needed
for in-place use.

When the Python verifier is **packaged** into a self-contained copy with no repo around it, the
packaging step copies the core schemas next to it as `schemas/`, and each add-on's
`Schemas/*.json` into `schemas/add-ons/<AddOn>/`:

- `Skill/build_skill.py` populates `Skill/dist/<flavor>/scripts/schemas/add-ons/<AddOn>/`.
- OMC's `update_appletbuilder.sh` populates
  `AppletBuilder.app/Contents/Library/actionui_verifier/schemas/add-ons/<AddOn>/`.

The single source of truth for an add-on schema stays in the add-on itself
(`Add-ons/<AddOn>/Schemas/<Element>.json`); copies placed here are build artifacts.
