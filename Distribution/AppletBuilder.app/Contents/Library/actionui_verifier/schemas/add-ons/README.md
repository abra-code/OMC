# Add-on element schemas

This directory holds verifier schemas for optional ActionUI **add-on** element types, kept
separate from the built-in element schemas in the parent `schemas/` directory.

`validate_actionui.py` auto-discovers every `add-ons/<AddOn>/*.json` here, so documents that use
an add-on element type (for example the `QuickLook` element from the ActionUIQuickLook add-on)
validate without passing `--schema-dir`. Built-in schemas win on a name collision, so an add-on
cannot shadow a core element.

## How it is populated

In a checkout of the ActionUI repo this directory is normally empty: the verifier also
auto-discovers add-on sources directly from `../../Add-ons/<AddOn>/Schemas/`, so no copy is needed
for in-place use.

When the verifier is **packaged** into a self-contained copy with no repo around it, the packaging
step copies each add-on's `Schemas/*.json` into `add-ons/<AddOn>/` here:

- `Skill/build_skill.py` populates `Skill/dist/<flavor>/scripts/schemas/add-ons/<AddOn>/`.
- OMC's `update_appletbuilder.sh` populates
  `AppletBuilder.app/Contents/Library/actionui_verifier/schemas/add-ons/<AddOn>/`.

The single source of truth for an add-on schema stays in the add-on itself
(`Add-ons/<AddOn>/Schemas/<Element>.json`); copies placed here are build artifacts.
