# Porting a Nib Applet to ActionUI - for AI Agents

Companion docs: `Nib-Guide.md` (the format you are leaving),
`omc_agent_tips_and_troubleshooting.md` (its section 1, on `/bin/sh`, applies to
every script you write here), `omctest_guide.md` (section 10 below).

*Already mid-port and something is broken?* Skip to the symptom index at the end.

---

## The task

Replace a compiled Interface Builder dialog with an ActionUI JSON window, so the
UI becomes a plain text file that can be validated, previewed, diffed and edited
without Xcode. The handler scripts survive largely intact; what changes is how
they are addressed and how control values are spelled.

Work the sections in order. Each is one porting task, and each ends in a state
you can verify before moving on.

| # | Section | Verify before moving on |
|---|---|---|
| 1 | Assess the source: XIB present, tags enumerated | inventory reconciles with every id the scripts touch |
| 2 | Reuse the nib's tags as ActionUI ids | `grep -c OMC_NIB` over `Scripts/` returns 0 |
| 3 | Value representation: sentinels, booleans, defaults | id lists derived from the JSON, not from memory |
| 4 | Layout: stacks, tabs, boxes, frames | `appletbuilder preview --screenshot`, compared per tab |
| 5 | Replace editable combo boxes | each field has a companion dropdown at `1000 + id` |
| 6 | Drag and drop onto a text field | a dropped folder and dropped text both handled |
| 7 | Manifest and wiring | `appletbuilder validate`: no unresolved `actionID`s |
| 8 | Shell-quote the command text | an apostrophe in a path no longer breaks the run |
| 9 | JSON built from shell | tabs escaped, duplicates collapsed |
| 10 | Tests | `appletbuilder test`, then mutate each new check and watch it go red |
| 11 | Hand to a human | they launch it and click through |

Sections 1 to 3 are where a port fails silently; sections 4 to 6 are where it
fails visibly. Do not start at 2: the inventory from section 1 is what tells you
whether the rename in section 2 covered everything.

---


## 1. First: can you transcribe, or must you reconstruct?

### 1.1 Check for the XIB source

A `.nib` in a bundle is a directory. Run this before planning anything:

```sh
file MyApp.app/Contents/Resources/Base.lproj/MyDialog.nib/*
```

```
keyedobjects.nib:  Apple binary property list      compiled, opaque
designable.nib:    XML 1.0 document                the original XIB
```

**If `designable.nib` exists, do not work from screenshots.** It carries every
fact you need:

| What you need | Where it is in the XIB |
|---|---|
| OMC control id | `tag=` attribute on the control |
| Value a menu item delivers | `userDefinedRuntimeAttribute keyPath="mappedValue"` |
| COMMAND_ID a control fires | `userDefinedRuntimeAttribute keyPath="commandID"` |
| Placeholder | `placeholderString` on the cell |
| Initial value / checked state | `title` on the cell / `state="on"` |
| Menu separator | a `menuItem` with **no** `title` attribute |

If it is absent, control ids and action wiring must be recovered from the
scripts instead, and the layout from screenshots. Say so before starting.

### 1.2 Enumerate tags in BOTH forms

```sh
# form 1: the XML attribute
grep -oE 'tag="[0-9]+"' designable.nib | sort -u
# form 2: a runtime attribute (containers often use this)
grep -A3 'keyPath="tag"' designable.nib
```

> **Real failure:** an extraction read only form 1 and reported tag 402 as dead
> code. 402 was the permissions `NSGridView`, carried as a runtime attribute,
> and `update_permissions_controls` enabled and disabled it to gate nine
> checkboxes. The port shipped with the checkboxes permanently live, and the
> test written for it passed because it collapsed "disabled" and "never
> touched" (see section 10.1).

**Rule:** reconcile the tag set against every id the scripts reference:

```sh
grep -ohE 'OMC_NIB_DIALOG_CONTROL_[0-9]+_VALUE' Scripts/*.sh | sort -u
grep -ohE 'DLG_GUID" [0-9]+' Scripts/*.sh | sort -u
```

Any id a script touches that is not in your inventory is a control you missed.

### 1.3 Extract an inventory before writing JSON

Parse the XIB into one row per control: container, tag, kind, title,
placeholder, frame, `commandID`, and the ordered menu items with their
`mappedValue`. About 40 lines with `xml.etree`. This is the checklist the
finished JSON is diffed against, and it surfaces oddities (a stale initial
value, a duplicated tag) before they become bugs.

---

## 2. Reuse the nib's tags as ActionUI ids

Do not renumber. Handlers keep addressing the same numbers, and config files
written by the old build keep working. Only the variable names change:

```sh
sed -i '' \
  -e 's/OMC_NIB_DIALOG_CONTROL_\([0-9]*\)_VALUE/OMC_ACTIONUI_VIEW_\1_VALUE/g' \
  -e 's/"\$OMC_NIB_DLG_GUID"/"$window_uuid"/g' \
  Scripts/*.sh
```

Then set `window_uuid="$OMC_ACTIONUI_WINDOW_UUID"` in the shared lib, and give
the ids names there (`PATTERN_ID=102`) so the test suite can import rather than
restate them.

---

## 3. Value representation - where silent breakage lives

### 3.1 A Picker option cannot have an empty tag or title

`Picker.swift`: `guard let tag = dict["tag"] as? String, !tag.isEmpty`. A
failing option is dropped from the menu with only a log line.

Nib menus routinely use an empty `mappedValue` for "Any" / "Ignore" / "Skip".

**Rule:** give those a sentinel tag (`none`), and normalize it back to `""` in
the shell. A blank spacer item needs at least a space as its title.

### 3.2 A Toggle carries a Bool

`Toggle.swift`: `valueType = Bool.self`. It emits `"true"` / `"false"`, and
`setElementValueFromString` accepts **only** those two literals - anything else
is discarded with a warning you will not see.

**Rule:** every `[ "$flag" = "1" ]` in the ported scripts is dead until this is
handled, and every `0`/`1` in a stored config silently fails to restore.

### 3.3 A Picker has no initial-selection property

It opens on its **first option**. There is no JSON key for "start here".

**Rule:** do not reorder the menu to put the default first - that damages the
UI. Seed every control from a defaults table in the window's
`INIT_SUBCOMMAND_ID` handler.

### 3.4 Migrate old config files on load

A config written by the nib build holds `1`/`0`/`""`. ActionUI accepts none of
them for those controls. Convert inside the override loop:

```sh
case " $TOGGLE_IDS " in
	*" $CONTROL_ID "*)
		case "$CONTROL_VALUE" in 1) CONTROL_VALUE=true ;; 0) CONTROL_VALUE=false ;; esac
		;;
esac
case " $SENTINEL_PICKER_IDS " in
	*" $CONTROL_ID "*)
		[ -n "$CONTROL_VALUE" ] || CONTROL_VALUE="$NO_CHOICE_TAG"
		;;
esac
```

Without this a previously ticked box comes back unticked and nothing reports
anything.

---

## 4. Layout

The nib is absolute `fixedFrame="YES"` positioning. Frames give you grouping and
order; they do not translate. Re-derive as stacks.

### 4.1 TabView hoists its tabs into the title bar

On macOS 26 the default and `tabBarOnly` styles move the tab strip into the
window title bar, destroying an embedded tabbed pane.

**Rule:** `"style": "grouped"`. It renders as a centered segmented strip over a
rounded pane - close to the `NSTabView` being replaced.

### 4.2 GroupBox insets nothing

It draws the frame and title only. Content sits flush against the edges and a
trailing control reads as clipped.

**Rule:** put explicit `padding` on the box's content stack.

### 4.3 A frame cannot mix fixed and flexible keys

`{"width", "height"}` and `{"minWidth", "maxHeight", ...}` are two forms. Mixing
them makes ActionUI ignore the whole dictionary. `appletbuilder validate` does
catch this one - it is the only layout error that is caught statically.

### 4.4 Give a tab's content stack a frame

Without `{"maxWidth": "infinity", "maxHeight": "infinity", "alignment":
"topLeading"}` the stack hugs its content and the pane centers it, so
`alignment: leading` appears to do nothing.

### 4.5 Pin everything that must not grow

A `TextEditor` with only a `minHeight` takes every spare point and squeezes
everything above it. Pin the rest; let exactly one element grow on purpose.

---

## 5. Replacing an editable combo box

There is no editable combo box in ActionUI. Use a `TextField` plus a companion
dropdown, with the companion at `1000 + the field's id` so the pairing is
derivable in a handler.

Two candidates, and the choice is a real trade:

| | menu-style `Picker` | `Menu` |
|---|---|---|
| Populate | one `omc_set_property "options"` | one `omc_insert_element` per item |
| Item identity | the tag **is** the value | encode in the Button id, resolve in handler |
| Appearance | chevron ~2.5pt right of center | glyph centers exactly |
| Testable end to end | yes | insertion is recorded, not executed |

The Picker's flaw is unfixable from JSON: it reserves a fixed leading inset for
its (hidden) title, so narrowing the frame shrinks the bezel without moving the
glyph. Widths 20/24/28 are equally off-center. Pick the Picker unless the
appearance has been called out.

For the `Menu` route:

- **`buttonStyle: "bordered"` draws a second chevron** of its own next to your
  label. Use `plain`.
- Use `chevron.up.chevron.down` (the symbol macOS uses on a popup button) with a
  `cornerRadius` + `background` to keep the combo bezel.
- **Declare the Menu in the JSON with `"children": []`; insert only the items.**
  Inserting the whole Menu is one call instead of N, but the button then does
  not exist until the init handler runs: invisible in `appletbuilder preview`,
  absent entirely if init fails.
- **Resolve the item through a per-window snapshot**, not by re-reading the
  source list at click time. Write the list the dropdown was built from to a
  file keyed by `$OMC_ACTIONUI_WINDOW_UUID`; the click handler reads position N
  from it. The Button id encodes combo and position:
  `id = 100000 + field_id * 100 + index`.

Cost check: `omc_dialog_control` spawns at roughly **0.47s per 140 calls**.
Budget window-open accordingly.

**Preserve differing actions.** If the nib's combo boxes did not all carry the
same `commandID`, a single shared handler must branch. In Find five combos
refreshed a command preview and the sixth loaded a config.

---

## 6. Drag and drop onto a text field

`OMCComboBox` accepted drops natively; an ActionUI `TextField` needs
`onDropTypes` + `onDropActionID`.

- **Items are not always paths.** `DropHelper` tries `public.utf8-plain-text`
  and `public.plain-text` **before** the file-URL branch, and only that branch
  runs `URL.path`. Guard for an absolute path before use.
- **Parse defensively.** The payload is `{"items":[...],"location":{...}}`,
  compact. A naive "first quoted string after items" runs past an **empty**
  array into `"location"` and returns a fragment of it, which then becomes the
  search path. Check the first non-space character after `[` is a quote.
- BSD `sed` has no `\|` alternation, so the escaping-aware regex does not exist.
  Document the limitation rather than pretending to handle it.

---

## 7. Manifest and wiring

### 7.1 Swap the dialog dictionary

`INIT_SUBCOMMAND_ID`, `IS_BLOCKING`, `END_OK_SUBCOMMAND_ID` and
`END_CANCEL_SUBCOMMAND_ID` all carry over unchanged.

```
NIB_DIALOG { NIB_NAME = "Find", ... }  ->  ACTIONUI_WINDOW { JSON_NAME = "Find", ... }
```

Add a command entry for every new handler, then:

```sh
appletbuilder validate MyApp.app
```

It cross-checks every `actionID` in the JSON against the manifest. **This is the
only static check on that hop** - omctest cannot see it, because handlers are
dispatched directly. Treat its warnings as errors.

### 7.2 keyboardShortcut always adds Command

`View.swift` coerces an absent, empty or invalid `modifiers` array to
`["command"]` in both the validation and the render path. There is no JSON
spelling for a plain Return or Escape, so a nib `keyEquivalent` of `\r` with an
empty `modifierMask` cannot be reproduced.

**Rule:** write `"modifiers": ["command"]` explicitly so the JSON states what
actually happens, and tell the user the binding changed.

### 7.3 A TextField's actionID also fires on focus loss

Deliberate, and matches AppKit end-editing behavior. Clicking a button beside
the field runs the field's action **first**.

**Rule:** if that action is destructive or state-replacing (loading a saved
config, say), remove the `actionID` and drive it from something explicit.

---

## 8. Fix the eval-quoting bug this port will expose

If the applet builds a command string and `eval`s it - a common OMC shape -
check how values are interpolated. `'$value'` is not escaping:

| Control value | Result |
|---|---|
| `/tmp/Bob's Stuff` | `unexpected EOF while looking for matching '` - the button does nothing |
| `evil'$(echo PWNED)'x` | `PWNED` runs |

Usually pre-existing. **The port is what makes it reachable**, because the drop
handler from section 6 now writes an externally supplied path into a control
with no typing.

```sh
shell_quote()
{
	printf "'%s'" "$(printf '%s' "$1" | /usr/bin/sed "s/'/'\\\\''/g")"
}
```

Apply at every site where a control value enters the command text.

---

## 9. Building JSON from shell

### 9.1 Escape tabs and control characters

A raw tab inside a JSON string is invalid. `NSJSONSerialization` rejects the
fragment, ActionUI keeps the property as a plain string, and the control loses
its **entire** item list - not just the offending entry. Tabs are legal in
filenames, so any list built from paths can hit this.

```sh
json_escape()
{
	printf '%s' "$1" | /usr/bin/sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/$(printf '\t')/\\\\t/g" \
		-e 's/[[:cntrl:]]//g'
}
```

### 9.2 De-duplicate on whole lines

Accumulating items as `<item>` means an item ending in `>` makes `<a>>` contain
`<a>`, and the next item is silently dropped. Use
`printf '%s\n' "$seen" | grep -Fxq -- "$item"`.

---

## 10. Testing

`appletbuilder test MyApp.app` runs real handlers against a mock environment.
See `omctest_guide.md`. It does **not** cover rendering, and it does not cover
the `actionID`-to-command hop.

### 10.1 Do not collapse "disabled" and "never touched"

`ui_enabled` returns `1`, `0`, or **empty for never written**. A helper mapping
"not 1" to "off" makes a handler that skipped the control entirely pass as
though it had disabled it - exactly how a missing control id survives a port.

```sh
enabled_state() { # <view-id> -> enabled | disabled | untouched
    case "$(ui_enabled "$1")" in
        1) echo enabled ;;
        0) echo disabled ;;
        *) echo untouched ;;
    esac
}
```

### 10.2 Assert on something only the correct code produces

Two checks written during Find's port could not fail:

- one asserted an exit code that the guarded **and** unguarded handler both
  produce (a `while` loop's status is its last body command, not its condition);
- one asserted the recorded string of a JSON property **the harness never
  parses**, so a malformed payload passed. Parse it in the test.

### 10.3 Mutate what the port introduced

Break the thing each new check names and confirm it goes red. For this port
specifically: remove the normalization; remove the defaults seeding; send the
dropdown items to the field instead of the companion; delete each guard; revert
`shell_quote` to bare wrapping; remove the tab escaping. Four of Find's checks
were rewritten because they stayed green.

### 10.4 Declare runtime-minted ids

Ids created with `omc_insert_element` are not in the statically extracted set,
so they land in `unknown_ids.log`. Use `ui_declare_ids <id> <id> ...` - spell
them out, never a range.

---

## 11. What only a human can confirm

A green `validate` plus a green `test` means the handler logic is right *given
the documented engine contract*. It says nothing about:

- how the window looks, or whether anything is clipped or misaligned;
- whether each control's `actionID` reaches the intended handler;
- runtime element insertion, which the harness records but does not execute.

```sh
appletbuilder preview MyApp.app/Contents/Resources/Base.lproj/MyApp.json \
    --screenshot /tmp/shot.png
```

Read the PNG back and compare against screenshots of the old dialog, tab by tab.
Two traps: the render is **transparent/black if the display is asleep or the
screen is locked** - check for all-zero pixels before trusting it - and a static
preview cannot show anything the init handler inserts at runtime.

Then ask the user to launch the app once and click through it.

---

## Pre-flight checklist

```
[ ] designable.nib present? if not, say so before starting
[ ] tags enumerated in BOTH forms (attribute + userDefinedRuntimeAttribute)
[ ] inventory reconciled against every id the scripts reference
[ ] nib tags reused verbatim as ActionUI ids
[ ] menu mappedValues reused verbatim as Picker option tags
[ ] empty option tags replaced with a sentinel, normalized back in the shell
[ ] SENTINEL_PICKER_IDS and TOGGLE_IDS derived from the JSON, not from memory
[ ] toggles: true/false handled on read and on write
[ ] non-first picker defaults seeded in the init handler
[ ] handlers needing raw values do NOT source the normalizing lib
[ ] old config files migrated on load
[ ] TabView style "grouped"
[ ] GroupBox content padded
[ ] exactly one element allowed to absorb vertical slack
[ ] combo boxes replaced, and their differing commandIDs preserved
[ ] command-string interpolation shell-quoted
[ ] JSON built from shell escapes tabs and control characters
[ ] every new handler added to the command manifest
[ ] sh -n on every script (never bash -n)
[ ] appletbuilder validate: no unresolved actionIDs
[ ] omctest suite, mutation-tested
[ ] previewed against the old screenshots, then handed to the user to launch
```

---

## Appendix: symptom index

For a port that is already underway and misbehaving.  
Every item here caused a real failure during the [Find.app](https://github.com/abra-code/FindApp)'s conversion. Most
failures in this port are **silent**: the JSON validates, the scripts pass
`sh -n`, the suite is green, and a control simply does nothing.


| Symptom | Cause | Section |
|---|---|---|
| A picker item is missing from the menu | option tag or title is empty | 3.1 |
| A whole dropdown is empty | invalid JSON in `options` - often a raw tab | 9.1 |
| Every checkbox behaves as unchecked | `[ "$x" = "1" ]` vs ActionUI's `true` | 3.2 |
| A control opens on the wrong value | Pickers open on option 0; no init seeding | 3.3 |
| A saved config does not restore some controls | config holds normalized values, or legacy `1`/`0`/`""` | 3.5, 3.6 |
| A group of controls can never be disabled | a tag hid in a `userDefinedRuntimeAttribute` | 1.2 |
| Tabs appear in the window title bar | `TabView` default style on macOS 26 | 4.1 |
| Content is flush with a box's edges | `GroupBox` insets nothing | 4.2 |
| A `frame` is ignored entirely | fixed and flexible keys mixed | 4.3 |
| One control ate all the vertical space | nothing else is pinned | 4.5 |
| Return/Escape need Command held down | ActionUI forces `["command"]` | 7.2 |
| A field's action fires when you click elsewhere | `actionID` also fires on blur | 7.3 |
| The action button does nothing for one folder | apostrophe in a path, unquoted `eval` | 8 |
| A dropdown button's glyph looks off-center | menu-style `Picker` leading inset | 5 |
