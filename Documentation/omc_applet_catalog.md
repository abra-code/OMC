# OMC Applet Catalog

A classified inventory of the public OMC applets, written for AI agents that are about to
build a new applet. Every applet here has a public GitHub repository under `abra-code`.
The OMC skill teaches the *format*; this catalog tells you *which existing app to copy from*.

**The single most useful thing you can do before writing a new applet is to open the closest
existing one and read its `Command.json`, its `Base.lproj/*.json`, and its `Scripts/lib.*.sh`.**
Every applet listed here is a complete, shipping, code-signed app. Cloning one gets you a
correct bundle layout, a working main command, a real window, and idiomatic script structure
for free.

---

## 1. Where the applets live, and how to start from one

### 1.1 Repositories

Every applet below has, or lives inside, a public repository under
[github.com/abra-code](https://github.com/abra-code).

A clone gives you the applet *sources*: inside the bundle, `Info.plist`, `Command.json` or
`Command.plist`, `Base.lproj/*.json` or `*.nib`, `Scripts/*`, and the app resources; at the repo
root, `Tests/` (in most repos - see the Tests column in section 7), `README.md`,
`codesign_applet.sh`, `LICENSE`, `Icon/`, `OMCApplet.entitlements`, and any `update_*.sh`
vendoring script. That is the set of files this catalog tells you to read.

What is *not* in a repo: compiled frameworks, the embedded Python runtime and its site-packages,
model weights, and compiled helper binaries - all added at build time. Hand-written helper
*source* is tracked, though: see `ICEdit.app/Contents/Helpers/icedit/` (a Python package) and
`AppletBuilder.app/Contents/Library/` (the two Python verifiers).

| Applet | Repository | Bundle in repo |
|---|---|---|
| Sips | [abra-code/SipsApp](https://github.com/abra-code/SipsApp) | `Sips.app` |
| TextUtil | [abra-code/TextUtilApp](https://github.com/abra-code/TextUtilApp) | `TextUtil.app` |
| DocToDoc | [abra-code/DocToDocApp](https://github.com/abra-code/DocToDocApp) | `DocToDoc.app` |
| PDFUtil | [abra-code/PDFUtilApp](https://github.com/abra-code/PDFUtilApp) | `PDFUtil.app` |
| QuickPDF | [abra-code/QuickPDFApp](https://github.com/abra-code/QuickPDFApp) | `QuickPDF.app` |
| Zip | [abra-code/ZipApp](https://github.com/abra-code/ZipApp) | `Zip.app` |
| ICEdit | [abra-code/ICEditApp](https://github.com/abra-code/ICEditApp) | `ICEdit.app` |
| PackageBuilder | [abra-code/PackageBuilderApp](https://github.com/abra-code/PackageBuilderApp) | `PackageBuilder.app` |
| OTool | [abra-code/OToolApp](https://github.com/abra-code/OToolApp) | `OTool.app` |
| Notarize | [abra-code/NotarizeApp](https://github.com/abra-code/NotarizeApp) | `Notarize.app` |
| Interpreter | [abra-code/InterpreterApp](https://github.com/abra-code/InterpreterApp) | `Interpreter.app` |
| Cadabra | [abra-code/Cadabra](https://github.com/abra-code/Cadabra) | `Cadabra.app` |
| AIChat | [abra-code/Cadabra](https://github.com/abra-code/Cadabra) | `AIChat.app` (same repo as Cadabra) |
| AppletBuilder | [abra-code/omc](https://github.com/abra-code/omc) | `Distribution/AppletBuilder.app` |
| Enoch | [abra-code/EnochApp](https://github.com/abra-code/EnochApp) | `Enoch.app` |
| Xattr | [abra-code/XattrApp](https://github.com/abra-code/XattrApp) | `Xattr.app` |
| Watchdog | [abra-code/WatchdogApp](https://github.com/abra-code/WatchdogApp) | `Watchdog.app` |
| Delta | [abra-code/DeltaApp](https://github.com/abra-code/DeltaApp) | `Delta.app` |
| Find | [abra-code/FindApp](https://github.com/abra-code/FindApp) | `Find.app` |

Default branches are `main` except **`omc` and `FindApp`** in the table above, and **`replay`** in the supporting table below, which all use `master`. This matters only if you
are building `raw.githubusercontent.com` URLs rather than cloning.

To read one applet without a full checkout:

```
git clone --depth 1 https://github.com/abra-code/SipsApp.git
```

Supporting repositories referenced later in this document:

| Repository | What it is |
|---|---|
| [abra-code/omc](https://github.com/abra-code/omc) | the OMC engine, AppletBuilder, templates, and this documentation |
| [abra-code/ActionUI](https://github.com/abra-code/ActionUI) | the ActionUI framework, plus `Examples/` - the UI JSON pattern library |
| [abra-code/pdfutil](https://github.com/abra-code/pdfutil) | Swift PDFKit + Vision helper used by PDFUtil, QuickPDF, Interpreter |
| [abra-code/replay](https://github.com/abra-code/replay) | parallel execution tool bundled by Delta and Cadabra |
| [abra-code/icedit](https://github.com/abra-code/icedit) / [abra-code/glyphsvg](https://github.com/abra-code/glyphsvg) | ICEdit's two helpers: `icedit` is a Python package (tracked in ICEditApp), `glyphsvg` is a C binary |
| [abra-code/mlx-agent](https://github.com/abra-code/mlx-agent) | the MLX inference agent behind Cadabra and Interpreter |
| [abra-code/ChatView](https://github.com/abra-code/ChatView), [DiffView](https://github.com/abra-code/DiffView), [RichText](https://github.com/abra-code/RichText), [AsyncImageCache](https://github.com/abra-code/AsyncImageCache) | Swift packages consumed by ActionUI |
| [abra-code/PillowUI](https://github.com/abra-code/PillowUI) | Python + ActionUI JSON demo |
| [abra-code/Shortcuts](https://github.com/abra-code/Shortcuts) | Abracode Shortcuts, a conventional Cocoa app |

### 1.2 Cloning a finished applet with AppletBuilder

AppletBuilder can clone a finished applet directly:

```
<AppletBuilder.app>/Contents/Resources/Agents/appletbuilder create \
    --clone <checkout>/SipsApp/Sips.app \
    --name MyConverter --dest ~/Development/MyConverterApp \
    --bundle-id com.example.myconverter
```

`--name` becomes the applet name, the executable name, and the script prefix; `--clone`
auto-detects whether the source used embedded Python. Use `--template` instead when no existing
applet is close enough:

```
appletbuilder list-templates
appletbuilder create --template "ActionUI Window" --name MyTool --dest ~/Development/MyToolApp [--python]
```

Templates live in `OMC/Distribution/AppletBuilder.app/Contents/Resources/Templates/`:
`ActionUI Window.applet`, `ActionUI Web.applet`, `Nib Window.applet`, `Nib Web.applet`, `Empty.applet`.

**Decision rule:** clone a real applet when the new app shares an interaction model with one
of the families below (that is almost always true). Fall back to `ActionUI Window` only for a
genuinely novel shape.

---

## 2. Read this before you pick: the NIB constraint

Two UI generations exist in this collection.

| Generation | Marker in the manifest | Marker on disk | Agent-editable? |
|---|---|---|---|
| **ActionUI JSON** (current) | `ACTIONUI_WINDOW` | `Base.lproj/*.json` | **Yes** - plain text, schema-validated, previewable |
| **Cocoa NIB** (legacy) | `NIB_DIALOG` | `Base.lproj/*.nib` | **In principle yes, in practice no** - see below |

A `.nib` in these applets is not a single opaque file. It is a bundle directory holding both a
source and a build product:

```
Base.lproj/Find.nib/
    designable.nib          <- Interface Builder XIB, XML, human-readable
    keyedobjects.nib        <- compiled binary, this is what loads at runtime
```

Every app-owned nib across the six NIB applets has this shape, and every one carries a
`designable.nib`. No `.xib` file exists anywhere in these projects, so the in-bundle
`designable.nib` is the source of record. The compiled member is `NIBArchive` in most cases
(Xattr, Watchdog, Enoch, AIChat) and an Apple binary plist in the rest (Find, Delta) - do not
assume either. `Xattr.nib` is the only one shipping per-deployment-target variants
(`keyedobjects-101300.nib` and `keyedobjects-110000.nib`); every other nib ships a single
`keyedobjects.nib`.

So the XML *is* editable text and `ibtool` *can* regenerate the binary. The constraint is not
the file format - it is that **an agent cannot author or substantially restructure an XIB with
any confidence.** Three specific traps, none of them visible to a schema check:

1. **Controls must be OMC subclasses.** Find.nib is built almost entirely from `OMCButton`,
   `OMCPopUpButton`, `OMCComboBox`, `OMCTextField`, `OMCMenuItem`, `OMCBox`, and `OMCGridView`.
   Per `Nib-Guide.md`, a control has to be reclassed to its OMC subclass to talk to OMC at all.
   Add a stock `NSButton` and it compiles cleanly and is completely inert.
2. **Two independent couplings, both by hand-maintained identifier.** A `commandID` user-defined
   runtime attribute binds the control to a `COMMAND_ID` in the manifest (Find.nib has dozens;
   tables use `selectionCommandID` / `doubleClickCommandID`). Separately, the integer
   NSView `tag` binds it to the scripts: the script reads
   `$OMC_NIB_DIALOG_CONTROL_<tag>_VALUE` and writes back with `omc_dialog_control ... <tag>`.
   Note the manifest itself contains no control identifiers - grep `Command.plist` for
   `CONTROL_ID` and you get zero hits. Get either identifier wrong and the window still builds.
3. **Menu items carry `mappedValue`** runtime attributes mapping a selection to the string the
   script receives, one per item. These are pure convention; nothing checks them.

These are springs-and-struts layouts, not autolayout - there are no `<constraint>` elements in
the applet nibs at all - so the usual "you will break the constraint graph" worry does not apply
here. The real failure mode is quieter: a nib that compiles, loads,
and does nothing.

**Recompiling, if you must.** Plain `ibtool --compile` emits a *flat file* and would replace the
nib directory with one. The bundle shape only survives with:

```
ibtool --flatten NO --compile Out.nib designable.nib
```

Three caveats. The round trip rewrites `designable.nib` itself (the toolsVersion is bumped), so
the source no longer matches what shipped. The versioned `keyedobjects-NNNNNN.nib` names come
from an Xcode build and are not reproducible this way, so Xattr cannot be round-tripped
faithfully. And the recompiled binary is not byte-identical to the shipped one, so an in-place
recompile breaks the code signature seal and the applet must be re-signed. `ibtool` also needs
full Xcode, and under a sandbox it fails *silently* - exit 0, no output file.

The practical rule:

- A **cosmetic, single-attribute** change to an existing element (a label string, a title, a
  frame number) is feasible with the recipe above, followed by a re-sign and a user check that
  the window still loads.
- **Adding a control, changing a layout, or rewiring a command** is not. That needs Xcode and a
  human.

**Never choose a NIB applet as the starting point for a new applet.** Never choose the
`Nib Window` / `Nib Web` templates. If the user hands you a NIB applet to extend, say plainly
that anything beyond a trivial attribute tweak needs Xcode, and scope your work to the scripts -
those are shell or Python text and fully editable.

Two footnotes. The dialog nibs inside `Abracode.framework`
(`Versions/A/Resources/Base.lproj/progress.nib`, `input_combo.nib`, `OMCOutputWindow.nib`, and
the rest) really *are* flat, sourceless compiled files - the "opaque binary" description is
accurate for those, and they are framework internals you should not touch regardless. And the
`AIChat.nib` in AIChat and Enoch is a thin shell around a single `OMCWebKitView` with zero
tags and zero commandIDs; the UI lives in the JavaScript, not the nib, which makes those two far
less constrained than Find or Watchdog.

NIB applets in this collection (reference only, not clone sources): Xattr, Watchdog,
Delta, Find, Enoch, and AIChat (hybrid: NIB main window + ActionUI dialogs).

---

## 3. Classification axes

Match a new applet against these six axes, then read the quick-pick table in section 4.

| Axis | Values seen in this collection |
|---|---|
| **A. UI generation** | ActionUI JSON (current, most apps) / Cocoa NIB (legacy) / hybrid |
| **B. Script language** | pure shell / pure embedded Python / shell + Python helpers / shell + JS (WebKit bridge) |
| **C. Interaction model** | batch converter queue / document editor (open-save-dirty) / inspector-viewer / linear pipeline-wizard / chat / live monitor / meta dev tool |
| **D. Input routing** | `act_always` (launch into a window) / `act_file_or_folder`, `act_file`, `act_folder` (drop and open-with) / in-window drop targets / macOS Services / declared document types + UTI |
| **E. Bundled payload** | nothing (system tools only) / helper CLI in `Contents/Helpers` / embedded Python + `Contents/Library/Packages` / AI inference stack in `Contents/Support` / model weights in-bundle |
| **F. Test coverage** | omctest `Tests/` suite / none |

**Complexity and Size legend.** The family tables and the full matrix in section 7 rate every
applet on two coarse scales rather than quoting file counts, line counts, or byte sizes - those
drift with every commit and this document does not track them. Clone the repo and count if you
need a real number.

The two scales are independent: PackageBuilder is complex but compact, Enoch is trivial but
multi-gigabyte. Do not read one off the other.

**Complexity** - measured by command count, `len(COMMAND_LIST)` in the manifest:

| Bucket | Commands |
|---|---|
| **small** | up to roughly twenty |
| **medium** | roughly twenty to forty |
| **large** | forty-plus |
| **very large** | the outliers: Cadabra and AppletBuilder |

**Size** - the installed bundle, driven almost entirely by what it carries:

| Bucket | Installed bundle |
|---|---|
| **compact** | tens of MB or less - system tools only, no bundled runtime |
| **large** | bundles embedded Python, an AI inference stack, or a large third-party CLI |
| **multi-GB** | ships model weights in the bundle (Enoch only) |

Two payload notes that decide bundle size and signing work:

- **Embedded Python** lives at `Contents/Library/Python/`; third-party modules go in
  `Contents/Library/Packages/` (survives a runtime rebuild). It is the single biggest
  contributor to bundle size after model weights.
- **Local AI stacks** live at `Contents/Support/` (`Llama.cpp/`, `MLX/`). Model weights are
  downloaded at runtime in every app except Enoch, which ships its GGUF weights inside the bundle.

---

## 4. Quick pick: "I am building X, clone Y"

| If the new applet is... | Clone | Why |
|---|---|---|
| A batch converter over a CLI tool, one output per input | **[SipsApp/Sips.app](https://github.com/abra-code/SipsApp)** | Smallest complete example of the batch-queue family: drop list, options, destination folder, progress, cancel |
| A batch converter with a format/flavor matrix | **[DocToDocApp/DocToDoc.app](https://github.com/abra-code/DocToDocApp)** | Same shape plus a bundled helper binary (pandoc) and a format+flavor picker |
| A batch converter with many operation modes that swap panels | **[PDFUtilApp/PDFUtil.app](https://github.com/abra-code/PDFUtilApp)** | Operation picker swaps GroupBox panels; routes Save-As vs destination-folder by output shape |
| A converter that needs a preview pane | **[TextUtilApp/TextUtil.app](https://github.com/abra-code/TextUtilApp)**, PDFUtil, QuickPDF, DocToDoc | Built-in QuickLook window (`*QuickLook.json` + `.quicklook.sh` / `.quicklook.init.sh`) |
| A document editor with open/save/dirty state | **[PackageBuilderApp/PackageBuilder.app](https://github.com/abra-code/PackageBuilderApp)** | The only app with its own document type, UTI, and `.pkgbld` project format; full dirty tracking and external-change detection |
| A document editor over an archive or container | **[ZipApp/Zip.app](https://github.com/abra-code/ZipApp)** | Staged edits committed on save, breadcrumb navigation, password sheets, progress with cancel |
| A structured file inspector, one window per input | **[OToolApp/OTool.app](https://github.com/abra-code/OToolApp)** | Multi-window via `OPEN_OBJECT_DIALOG` + `ALLOW_MULTIPLE_ITEMS`, sidebar + 6 lazy-loaded tabs, filterable tables |
| A multi-step signing / upload / verify pipeline | **[NotarizeApp/Notarize.app](https://github.com/abra-code/NotarizeApp)** | Linear pipeline with per-step state, a credentials wizard sheet, keychain access |
| A visual editor with pickers and live preview | **[ICEditApp/ICEdit.app](https://github.com/abra-code/ICEditApp)** | Python applet with color pickers, forms, split views, child picker windows sharing state |
| A local-LLM chat app | **[AIChatApp/Cadabra.app](https://github.com/abra-code/Cadabra)** | Current generation: native ActionUI `Chat` streaming, dual MLX + llama.cpp engines, MCP tools |
| A single-model AI utility (not a chat) | **[InterpreterApp/Interpreter.app](https://github.com/abra-code/InterpreterApp)** | On-device inference behind a task UI, background poller, no chat metaphor |
| An app-development / meta tool | **[OMC/Distribution/AppletBuilder.app](https://github.com/abra-code/omc)** | The most complex applet: a tabbed editor over many commands and JSON files, embedded verifiers, companion CLI |
| A one-shot Services menu action, no window | Templates `Empty.applet` | Plus read the `NSServices` block in [FindApp](https://github.com/abra-code/FindApp) or [InterpreterApp](https://github.com/abra-code/InterpreterApp) |

---

## 5. Applet families

### 5.1 Batch converters (the largest family)

All share one architecture: `act_always` main command opens a single ActionUI window; a table
holds a queue of dropped files; a picker chooses the output format; a Start button runs a batch
loop with progress and cancel; output goes to a chosen destination folder. This is the highest-
value family to copy because several independent apps have converged on it.

| Applet | Wraps | Manifest / UI | Complexity | Size | Tests | Notes |
|---|---|---|---|---|---|---|
| **[SipsApp/Sips.app](https://github.com/abra-code/SipsApp)** | system `sips` | Command.json / ActionUI | small | compact | yes | Cleanest, smallest member. Live resize/rotate/flip preview. Format list queried from `sips` at launch. Best first read. |
| **[TextUtilApp/TextUtil.app](https://github.com/abra-code/TextUtilApp)** | system `textutil` | Command.json / ActionUI | small | compact | yes | Smallest scripts of any ActionUI applet. Adds a QuickLook preview window. |
| **[DocToDocApp/DocToDoc.app](https://github.com/abra-code/DocToDocApp)** | bundled `pandoc` | Command.json / ActionUI | small | large | yes | The reference for **bundling a large third-party CLI** in `Contents/Helpers`, with per-arch distributions. |
| **[PDFUtilApp/PDFUtil.app](https://github.com/abra-code/PDFUtilApp)** | bundled `pdfutil` (Swift, PDFKit + Vision) | Command.json / ActionUI | medium | compact | yes, plus a helper-binary suite | Heavy variant: operation-panel switching, OCR/watermark/crop/split/merge, pre-flight structure-loss alert, atomic writes via `mktemp` + `--force`. |
| **[QuickPDFApp/QuickPDF.app](https://github.com/abra-code/QuickPDFApp)** | bundled `qpdf` + `pdfutil` | Command.json / ActionUI | medium | compact | yes, plus a helper-binary suite | Two-stage pipeline dispatch across two helper binaries. Static universal `qpdf` vendoring zlib/libjpeg-turbo/OpenSSL. |

Files to read first in this family: `Scripts/lib.<name>.sh` (tool paths, control IDs, shared
helpers), `Scripts/<Name>.main.sh`, `<name>.files.drop.sh`, `<name>.start.batch.sh`.

PDFUtil and QuickPDF also carry a **two-tier test strategy** worth copying: an omctest suite
that drives the applet handlers, plus a separate `./test.sh` that exercises the helper binary
alone with no app code involved.

### 5.2 Document editors (open / edit / save / dirty state)

| Applet | Document | Manifest / UI | Complexity | Size | Tests | Notes |
|---|---|---|---|---|---|---|
| **[PackageBuilderApp/PackageBuilder.app](https://github.com/abra-code/PackageBuilderApp)** | `.pkgbld` project (own UTI, Editor role) | Command.json / ActionUI | large | compact | extensive | **The document-based reference.** `UTExportedTypeDeclarations`, `LSHandlerRank Owner`, close confirmation, external-change detection, 4-tab window, drag-drop payload table with per-item inspector, cancelable build. Ships a headless companion CLI at `Contents/Resources/Agents/pkgbuilder` plus a JSON schema. |
| **[ZipApp/Zip.app](https://github.com/abra-code/ZipApp)** | `.zip` archives (Editor role) | Command.json / ActionUI | medium | large | yes | **The pure-Python reference.** Every handler is `.py` against embedded Python. Staged changes written on save, breadcrumb navigation, filter/search, `PROGRESS` dialog with `END_CANCEL_SUBCOMMAND_ID`, two sheets (`PasswordSheet.json`, `UnlockSheet.json`). Helper `Contents/Helpers/archive` links libarchive and reads passphrases from stdin only. |
| **[ICEditApp/ICEdit.app](https://github.com/abra-code/ICEditApp)** | Apple `.icon` bundles (folder documents) | Command.json / ActionUI | medium | large | extensive | Visual editor: layer list, color pickers, `Form`, `HSplitView`, `ContentUnavailableView`, three child symbol-picker windows. Per-window state shared through the pasteboard keyed by window UUID. Two helpers: `icedit` (Python, tracked in the repo) and `glyphsvg` (a compiled C binary). `act_folder` so a `.icon` folder can be dropped. Note its declared `CFBundleTypeRole` is `Viewer`, not `Editor` - only Zip and PackageBuilder declare `Editor`. |

### 5.3 Inspectors and viewers (read-only, no save)

| Applet | Inspects | Manifest / UI | Complexity | Size | Tests | Notes |
|---|---|---|---|---|---|---|
| **[OToolApp/OTool.app](https://github.com/abra-code/OToolApp)** | Mach-O binaries via `otool`/`nm`/`lipo` | Command.json / ActionUI | medium | compact | none | **The multi-window + tabbed-inspector reference.** Opens one independent window per dropped or opened item, via `act_file_or_folder` plus `OPEN_OBJECT_DIALOG` with `ALLOW_MULTIPLE_ITEMS` - not via `MULTIPLE_OBJECT_SETTINGS`, which it does not use. `NavigationSplitView` sidebar + `TabView` of 6 tabs, each a `LoadableView` loaded lazily on first visit. Filterable tables, arch-slice picker for fat binaries, per-window scratch dir keyed by `$OMC_ACTIONUI_WINDOW_UUID`. No bundled helpers - drives system tools. |
| **[XattrApp/Xattr.app](https://github.com/abra-code/XattrApp)** | extended attributes | Command.plist / **NIB** | small | compact | none | NIB. Read only for its `NSServices` block (two service items, `runOMCService`) and its `Contents/MacOS/getxattr` helper. |

### 5.4 Pipeline / wizard applets

| Applet | Pipeline | Manifest / UI | Complexity | Size | Tests | Notes |
|---|---|---|---|---|---|---|
| **[NotarizeApp/Notarize.app](https://github.com/abra-code/NotarizeApp)** | codesign -> submit -> poll -> staple -> assess | Command.json / ActionUI | medium | compact | yes, plus keychain stubs | **The wizard-sheet and credentials reference.** A reusable credentials sheet with back/next steps, per-target settings persisted by bundle identifier, signature diffing before re-signing, long-running `xcrun notarytool` with UI feedback. Its `Tests/helpers/` fake `security` binary is the pattern for testing keychain-dependent code. |

### 5.5 Local AI inference applets

Three generations of one lineage plus one task-specific app. Inference binaries always live in
`Contents/Support/`; models are downloaded at runtime except in Enoch.

| Applet | Engine(s) | UI | Python | Size | Tests | Notes |
|---|---|---|---|---|---|---|
| **[AIChatApp/Cadabra.app](https://github.com/abra-code/Cadabra)** | MLX (`mlx-agent`) **and** llama.cpp, chosen by model file type | ActionUI, native `Chat` element streaming | yes, an extensive package set | large | extensive | **Current generation, the one to clone.** The largest applet after AppletBuilder. Multi-window: chat, model picker, HF/ModelScope browser, MCP server manager, MCP inspector, external ACP agent editor. Sandboxed MCP file I/O through the embedded `replay` binary. Model benchmarking and in-place model switching. |
| **[AIChatApp/AIChat.app](https://github.com/abra-code/Cadabra)** | llama.cpp `llama-server` | **hybrid**: NIB main window hosting llama.cpp's stock WebUI in WebKit, ActionUI dialogs around it | yes, incl. `mcp_proxy` | large | shared with Cadabra | Previous generation. Read it for the **WebKit + JS bridge** pattern (`webkit.client.js`) and the stdio-to-HTTP MCP proxy. Its main window is a NIB - do not clone for new UI. |
| **[EnochApp/Enoch.app](https://github.com/abra-code/EnochApp)** | llama.cpp `llama-server` | **NIB** window hosting a SvelteKit WebUI | none | **multi-GB** | none | The only applet that **ships model weights in-bundle** (`Contents/Resources/*.gguf`). Read it as the reference for a single-purpose AI app with a baked-in model and a custom web front end; do not clone the bundle. |
| **[InterpreterApp/Interpreter.app](https://github.com/abra-code/InterpreterApp)** | `mlx-agent` (MLX + a wrapped llama-server), `langid`, `pdfutil` for Vision OCR | ActionUI, three window types | none - shell, plus one Perl helper | large | yes | **AI without a chat metaphor.** Fully on-device translation. The reference for a **background poller process per window** that owns a model broker and drives button enable/disable from a `status.json`, plus first-run auto-chaining into a model chooser and two Services entries (selected text and file drop). |

Two AI-specific structures worth lifting verbatim: the Hugging Face browser
(`aichat.hf.browse.*`, search + sort + quantization filter + download with progress) and the
MCP server manager (`aichat.mcp.servers.*` and `aichat.mcp.inspect.*`).

### 5.6 Monitors and one-shot utilities (NIB - reference only)

| Applet | Purpose | Manifest / UI | Notes |
|---|---|---|---|
| **[WatchdogApp/Watchdog.app](https://github.com/abra-code/WatchdogApp)** | live FSEvents folder monitor | Command.plist / **NIB** | `act_folder`. Pushes rows into a NIB table in real time via `omc_dialog_control` as events arrive - **event-driven, not polled**. Embeds the `watchdog` Python package with a compiled `_watchdog_fsevents` extension in `Contents/Library/Packages`. Read the Python handlers; any structural UI change needs Xcode (section 2). |
| **[DeltaApp/Delta.app](https://github.com/abra-code/DeltaApp)** | TSV diff report between two directory trees | Command.plist / **NIB** | Bundles the `replay` parallel-execution tool in `Contents/MacOS`. Read for the `replay` fan-out pattern. |
| **[FindApp/Find.app](https://github.com/abra-code/FindApp)** | GUI over `find` | Command.plist / **NIB** | `act_always`, dropping a folder retargets the search. Ships a **Services** item ("Search Here with Find.app"). Read its `NSServices` block. |

### 5.7 The meta tool

**[OMC/Distribution/AppletBuilder.app](https://github.com/abra-code/omc)** - the applet that builds applets, and the most complex
one in the collection: on the order of ninety commands across a dozen-plus ActionUI JSON files
and a hundred-odd scripts, almost all shell with a little Python and JS. **No NIB files at
all** - a proof that a full IDE-class app is expressible in ActionUI JSON.

Structure worth studying:

- Main window is a 5-tab `TabView`: General (metadata, icon, System Services), Commands
  (table + manifest editor + validate), Scripts (table + text editor), UI Files (table + editor
  + validate + prettify + ActionUIViewer preview), Build & Run (identity picker, build log,
  Build / Test / Run).
- Tab bodies are `LoadableView`s, loaded lazily on first selection.
- Dialogs: NewApplet, NewCommand, NewScript, NewUIFile, Settings, HelpViewer.
- `Contents/Helpers/ActionUIViewer` - universal binary that live-renders an ActionUI JSON file
  (this is what the Preview button launches).
- `Contents/Library/actionui_verifier/` and `Contents/Library/command_verifier/` - the Python
  schema validators, plus `mistune` for the Markdown help viewer. Note this bundle has **no**
  `Contents/Library/Packages/`; the verifiers sit directly under `Contents/Library/`.
- `Contents/Resources/Agents/appletbuilder` - the companion CLI, documented in the adjacent
  `README.md`. This is the entry point you should be calling.
- Two-stage validation: `plutil -lint` first, then the Python verifier.

Copy from AppletBuilder when you need: lazy tab loading, a table-plus-detail-editor pane, an
embedded help viewer (WebKit + `md2html.py` + `mistune`), a build log pane, or a companion CLI
that shares the GUI's shell libraries so both paths behave identically.

---

## 6. Technique cookbook: where to find each pattern

| Pattern | Best example | Where to look |
|---|---|---|
| Batch queue with drag-drop table | Sips | `Scripts/sips.files.drop.sh`, `sips.start.batch.sh` |
| Progress dialog with working Cancel | Zip | `PROGRESS` + `END_CANCEL_SUBCOMMAND_ID` in `Command.json` |
| Modal sheet | Zip (password), Notarize (credentials wizard) | `PasswordSheet.json`, `CredentialSheet.json` |
| QuickLook preview pane | PDFUtil, TextUtil, QuickPDF, DocToDoc | `*QuickLook.json` + `.quicklook.init.sh` |
| Tabs with lazy loading | OTool, AppletBuilder | `LoadableView` inside `TabView` |
| Sidebar + content split | OTool, Cadabra, Sips | `NavigationSplitView` |
| One window per dropped input | OTool | `act_file_or_folder` + `OPEN_OBJECT_DIALOG` / `ALLOW_MULTIPLE_ITEMS`. Note: `MULTIPLE_OBJECT_SETTINGS` = `proc_separately` appears in **no** shipping applet. The batch converters all use `proc_together`. |
| Document dirty tracking, save / save-as | PackageBuilder, Zip, ICEdit | `SAVE_AS_DIALOG`, window-close subcommand |
| Own document type + UTI | PackageBuilder | `UTExportedTypeDeclarations` in `Info.plist` |
| macOS Services menu item | Find, Xattr, Interpreter | `NSServices` with `NSMessage = runOMCService` |
| Command chaining | almost all | `omc_next_command`, `NEXT_COMMAND_ID` |
| Per-window state | ICEdit (pasteboard), OTool (scratch dir) | keyed by `$OMC_ACTIONUI_WINDOW_UUID` |
| Background process + UI polling | Interpreter | `interp.poll.sh`, broker `status.json` |
| Live table updates from an event source | Watchdog | `omc_dialog_control` driven by FSEvents |
| Parallel fan-out of shell work | Delta, Cadabra | the `replay` binary |
| Embedded Python, all handlers in `.py` | Zip, ICEdit | `Contents/Library/Python` + `.py` handlers |
| Embedded Python packages | Cadabra, Watchdog | `Contents/Library/Packages/` (AppletBuilder is the exception: its libraries sit directly in `Contents/Library/`) |
| Bundling a third-party CLI | DocToDoc (pandoc), QuickPDF (qpdf) | `Contents/Helpers/` + the `update_*.sh` script |
| Writing your own helper CLI | PDFUtil (`pdfutil`, Swift), ICEdit (`icedit`, Python; `glyphsvg`, C) | `Contents/Helpers/` |
| WebKit view + JS bridge | AIChat, Enoch, AppletBuilder help viewer | `webkit.client.js`, `help.webkit.client.js` |
| Native streaming chat | Cadabra | ActionUI `Chat` element in `aichat.chat.json` |
| Local model download UI | Cadabra, Interpreter | `aichat.hf.browse.*`, `interp.model.download.sh` |
| MCP server management | Cadabra | `aichat.mcp.servers.*`, `aichat.mcp.inspect.*` |
| Headless companion CLI | AppletBuilder, PackageBuilder | `Contents/Resources/Agents/` |
| Mocking system tools in tests | Notarize | `Tests/helpers/` fake `security` |
| Largest omctest suites | Cadabra, then PackageBuilder and ICEdit | `Tests/` |

---

## 7. Full matrix

| Applet | Released | Manifest | UI | Complexity | Size | Activation | Bundled payload | Tests |
|---|---|---|---|---|---|---|---|---|
| Sips | yes | JSON | ActionUI | small | compact | `act_always` | - | yes |
| TextUtil | yes | JSON | ActionUI | small | compact | `act_always` | - | yes |
| DocToDoc | yes | JSON | ActionUI | small | large | `act_always` | pandoc | yes |
| PDFUtil | yes | JSON | ActionUI | medium | compact | `act_always` | pdfutil | yes |
| QuickPDF | yes | JSON | ActionUI | medium | compact | `act_always` | qpdf, pdfutil | yes |
| Zip | yes | JSON | ActionUI | medium | large | `act_always`, `act_file_or_folder` | Python, archive | yes |
| ICEdit | yes | JSON | ActionUI | medium | large | `act_always`, `act_folder` | Python, icedit, glyphsvg | extensive |
| PackageBuilder | not yet | JSON | ActionUI | large | compact | `act_always`, `act_file` | pkgbuilder CLI | extensive |
| OTool | yes | JSON | ActionUI | medium | compact | `act_file_or_folder` | - | none |
| Notarize | yes | JSON | ActionUI | medium | compact | `act_file_or_folder` | - | yes |
| Interpreter | yes | JSON | ActionUI | medium | large | `act_always`, Services | MLX, llama.cpp, langid, pdfutil | yes |
| Cadabra | yes | JSON | ActionUI | very large | large | launch | Python, MLX, llama.cpp, replay, pdfutil | extensive |
| AIChat | yes | plist | hybrid | large | large | launch | Python, llama.cpp, replay | shared |
| AppletBuilder | yes | JSON | ActionUI | very large | large | `act_folder` | Python, ActionUIViewer, verifiers | via target |
| Enoch | yes | plist | **NIB** | small | **multi-GB** | launch | llama.cpp, in-bundle GGUF | none |
| Xattr | yes | plist | **NIB** | small | compact | `act_file_or_folder`, Services | getxattr | none |
| Watchdog | yes | plist | **NIB** | small | large | `act_folder` | Python, watchdog | none |
| Delta | yes | plist | **NIB** | small | compact | launch | replay | none |
| Find | yes | plist | **NIB** | small | compact | `act_always`, Services | - | none |

`Complexity` and `Size` are deliberately coarse buckets, not measurements - see the legend in
section 3. When you need a real number, count it in the repo: commands are `len(COMMAND_LIST)`
in the manifest, not the count of `*_COMMAND_ID` / `*_SUBCOMMAND_ID` string occurrences, which
is always higher.

---

## 8. Cautions and gaps

**Do not clone:**

- Any NIB applet (section 2).
- `AIChat.app` for new UI work - superseded by `Cadabra.app`.
- `Enoch.app` as a bundle - it carries its model weights. Read its structure, start elsewhere.

**Not OMC applets, despite living in the same tree:**

- [`ActionUI/Examples/`](https://github.com/abra-code/ActionUI/tree/main/Examples) - native Swift / Compose / Web hosts for ActionUI JSON. Useful as a
  library of **UI JSON patterns only**; the applet structure does not apply. Note the local
  `ActionUI-Examples/` working directory is a larger unpublished superset - only the four
  examples in the repo (BodyMetrics, TemperatureConverter, TipBillSplitter, UnitConverter)
  are public.
- [`ChatView`](https://github.com/abra-code/ChatView), [`DiffView`](https://github.com/abra-code/DiffView), [`RichText`](https://github.com/abra-code/RichText), [`AsyncImageCache`](https://github.com/abra-code/AsyncImageCache) - Swift packages consumed by ActionUI.
- [`PillowUI`](https://github.com/abra-code/PillowUI) - a Python + ActionUI JSON demo, not a bundle.
- [`Shortcuts`](https://github.com/abra-code/Shortcuts) (Abracode Shortcuts) - a conventional Cocoa app, no OMC manifest.
- [`OMC/OMCTestApp/`](https://github.com/abra-code/omc/tree/master/OMCTestApp) - has a `Command.plist`, but it is the engine's own NIB-based test harness
  for OMC features rather than a shippable applet. Not a clone source.

**Gaps - no applet demonstrates these yet.** If the user asks for one, there is no template to
copy and you are writing it from the guides:

- A **menu bar extra** (`MenuBarExtra` / status item). Note that `Documentation/MenuBar-Guide.md`
  is about `MainMenu.json`, the application menu bar - a different thing, and one every ActionUI
  applet here already uses. Nothing in this collection puts an item in the system status bar.
- A **background / `LSUIElement` agent** with no main window.
- A **preferences window** as a distinct pattern - each app rolls its own settings storage.
- A **multi-document** app with more than one open document at a time (OTool is multi-window
  but read-only; PackageBuilder and Zip are single-document).

---

## 9. Suggested reading order for a new applet

1. `Command.json` of the closest match - the command graph is the app's architecture.
2. `Scripts/lib.<name>.sh` - tool paths, control IDs, shared helpers. Every mature applet has one.
3. `Scripts/<Name>.main.sh` (or `.py`) - how the window opens.
4. `Base.lproj/<Name>.json` - the window layout and every `id` the scripts address.
5. `Base.lproj/MainMenu.json` - menu wiring, `CommandGroup` / `CommandMenu`.
6. The applet's `README.md` - the design rationale, often the fastest orientation.
7. `Tests/lib.test.<name>.sh` if present - shows exactly how handlers are invoked.
