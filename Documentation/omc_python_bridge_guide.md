# The Python Bridge to ActionUI Windows

**OMC 5.3.** A Python command handler can read the ActionUI window it was dispatched from, not only write to it.

That is the whole of what is new. `omc_dialog_control` has always been able to set a value, fill a table, enable a control; it has never been able to ask what is on screen. A handler's only view of the window was the snapshot the engine took when the command was dispatched - `$OMC_ACTIONUI_VIEW_101_VALUE` and its siblings - so anything the user changed after that was invisible, and any workflow that needed to *look* before deciding had to be restructured around it.

```python
import omc

win = omc.window()
name = win.get_string(101)          # what is in the field right now
rows = win.get_rows(5)              # every row of the table, right now
```

---

## Contents

1. [Nothing to install](#1-nothing-to-install)
2. [The two entry points](#2-the-two-entry-points)
3. [Reading](#3-reading)
4. [Writing](#4-writing)
5. [Tables](#5-tables)
6. [Adding and removing elements](#6-adding-and-removing-elements)
7. [Modals, dialogs and toasts](#7-modals-dialogs-and-toasts)
8. [OMC's own window verbs](#8-omcs-own-window-verbs)
9. [Batching](#9-batching)
10. [Errors](#10-errors)
11. [When to use omc_dialog_control instead](#11-when-to-use-omc_dialog_control-instead)
12. [Testing a bridge handler](#12-testing-a-bridge-handler)
13. [How it works](#13-how-it-works)

---

## 1. Nothing to install

AppletBuilder installs two modules into every applet that embeds Python and has Python command handlers: `omc` and `actionui_remote`. They land in `Contents/Library/Packages/`, which is already on `PYTHONPATH`, and they survive a Python runtime upgrade - unlike anything installed into the runtime's own `site-packages`.

So a handler just imports them. If `import omc` raises `ModuleNotFoundError`, the applet was built by an AppletBuilder older than 5.3; rebuild it.

**An applet using a system Python does not get them.** The engine only puts `Contents/Library/Packages` on `PYTHONPATH` for an embedded runtime, so shipping the modules to an applet without one would give it files it cannot import.

## 2. The two entry points

### `omc.window()`

The ActionUI window that dispatched this handler, as an `omc.OMCWindow`. It is a subclass of `actionui_remote.Window`, so every method below is the same one any ActionUI application's Python client has.

```python
win = omc.window()
```

Raises `omc.OMCError` with a specific message when the applet is not serving a bridge - which is the case for any command file with no `ACTIONUI_WINDOW` - or when this command was not dispatched from a window.

### `omc.context()`

Everything the engine put in the environment, parsed once and named, so a handler does not open with a block of `os.environ.get` calls.

| Field | From |
| --- | --- |
| `ctx.window_uuid` | `$ACTIONUI_WINDOW_UUID` |
| `ctx.endpoint` | `$ACTIONUI_REMOTE_ENDPOINT` |
| `ctx.command_guid`, `ctx.parent_command_guid` | the command GUIDs |
| `ctx.app_bundle_path`, `ctx.support_path`, `ctx.resources_path` | the `OMC_*_PATH` trio |
| `ctx.obj_path`, `ctx.obj_text` | the selection |
| `ctx.trigger` | `None`, or a `Trigger` - see below |
| `ctx.view_value(101)` | the dispatch-time snapshot of one view |
| `ctx.table_value(5, 1)`, `ctx.table_all_rows(5, 1)` | dispatch-time table snapshots |

`ctx.trigger` is set only when the handler was dispatched from a control's action. It carries `view_id`, `view_part_id`, `context` (JSON-decoded when it parses) and `raw` (the payload exactly as the engine wrote it).

```python
trigger = omc.context().trigger
if trigger and trigger.view_id == 5:
    print("row %d was clicked" % trigger.view_part_id)
```

The decode is lossy on purpose - a context of `"42"` arrives as the integer `42`, `"true"` as `True`, and `"null"` as `None`, which is indistinguishable from no payload. Read `trigger.raw` when the literal text matters.

**Snapshots are not live.** `ctx.view_value(101)` is what the engine captured at dispatch; `win.get_value(101)` is what is on screen now. That distinction is the reason this module exists.

## 3. Reading

```python
win.get_value(view_id, view_part_id=0)      # native type: str, int, float, bool
win.get_string(view_id, view_part_id=0, content_type=None)
win.get_int(view_id, view_part_id=0)
win.get_double(view_id, view_part_id=0)
win.get_bool(view_id, view_part_id=0)

win.get_property(view_id, name)             # a runtime property
win.get_state(view_id, key)                 # a state value
win.get_state_string(view_id, key)

win.get_element_info()                      # {view_id: "Type"} for every positive id
win.content_size_limits()
```

`get_element_info()` is the one to reach for when a handler must work against a window it did not author, or to assert in a test that the window is the shape it expects.

## 4. Writing

```python
win.set_value(view_id, view_part_id, value)
win.set_string(view_id, value, view_part_id=0, content_type=None)
win.set_int(view_id, value, view_part_id=0)
win.set_double(view_id, value, view_part_id=0)
win.set_bool(view_id, value, view_part_id=0)

win.set_property(view_id, name, value)
win.set_enabled(view_id, enabled)
win.set_hidden(view_id, hidden)
win.set_state(view_id, key, value)
win.set_state_from_string(view_id, key, value)
```

`content_type` accepts the same values the engine does - `"markdown"`, `"html"` and so on - for elements that render text.

## 5. Tables

```python
win.get_rows(view_id)                       # [[str, ...], ...]
win.get_column_count(view_id)
win.set_rows(view_id, rows)
win.append_rows(view_id, rows)
win.clear_rows(view_id)

win.select_row(view_id, index)              # returns the selected row, or None
win.select_row_with_content(view_id, text, column=None)
win.clear_selection(view_id)
```

Reading a table back is the single biggest thing the bridge adds. A handler that previously had to be handed `$OMC_ACTIONUI_TABLE_5_COLUMN_1_ALL_ROWS` as a tab-separated string, and parse it, now asks for a list of lists.

## 6. Adding and removing elements

```python
from actionui_remote import InsertPosition

win.insert_element(parent_id, element, container=None, position=None)
win.insert_row(parent_id, cells, container=None, position=None)
win.remove_element(view_id)
```

`element` is a dict - the same ActionUI JSON an element is written as in a document. `position` takes an `InsertPosition`: `append()`, `prepend()`, `at(2)`, `before(sibling_id)`, `after(sibling_id)`.

```python
win.insert_element(10, {"type": "Text", "id": 200, "properties": {"text": "added"}},
                   position=InsertPosition.at(0))
```

## 7. Modals, dialogs and toasts

```python
win.present_modal(source=None, format=None, style=None, on_dismiss_action_id=None)
win.dismiss_modal()
win.present_alert(title, message=None, buttons=None)
win.present_confirmation_dialog(title, message=None, buttons=None)
win.dismiss_dialog()
win.present_toast(message, duration=None, action_title=None, action_id=None)
win.dismiss_toast()
```

`present_modal` also accepts `element=` (a dict), `json_text=` and `path=` (a resource name the host resolves the same way `omc_present_modal` does).

## 8. OMC's own window verbs

These are not ActionUI's - they are OMC's, and they run the same helper tools a shell handler would. The split is invisible from here.

```python
win.terminate_ok()                  # close, run END_OK
win.terminate_cancel()              # close, run END_CANCEL
win.bring_to_front()
win.activate_app()
win.set_title(title)
win.resize(width, height)
win.move(x, y)
win.set_command_id(view_id, command_id)
win.select_control(view_id)

omc.next_command("MyApp.step2")     # chain, using OMC_CURRENT_COMMAND_GUID
omc.alert("Something went wrong.", title="MyApp", level="caution")
```

Do not depend on ordering between one of these and a bridge call in the same script: they reach the window through different channels.

## 9. Batching

One round trip instead of many. Inside the block every method returns `None`; afterwards `results` holds one entry per call.

```python
with win.batch() as b:
    b.set_string(101, "working...")
    b.set_enabled(102, False)
    b.set_rows(5, rows)

with win.batch(raise_on_error=False) as b:
    b.get_value(101)
    b.get_value(102)
for outcome in b.results:
    if isinstance(outcome, omc.RemoteError):
        ...
```

`results` is always populated, with a `RemoteError` in any failed slot. With the default `raise_on_error=True` the first failure is raised when the block exits, carrying the whole list as `err.results`.

## 10. Errors

```python
try:
    win = omc.window()
    value = win.get_string(101)
except omc.EndpointError:
    ...     # the host is gone
except omc.RemoteError as err:
    ...     # err.code: 1001 unknown window, 1002 unknown view, 1003 engine failure
except omc.OMCError:
    ...     # not running under OMC, or a helper tool failed
```

`EndpointError` is easy to miss. `omc.window()` only checks that the variables are set; the socket is opened lazily on the first verb. A host that stopped serving after this handler was launched therefore fails at the first `get_value()`, not at `omc.window()`.

Error codes are normative in `ActionUIRemote/PROTOCOL.md`.

## 11. When to use `omc_dialog_control` instead

It is unchanged and fully supported.

- **Shell handlers.** The bridge has no shell client; a `.sh` handler keeps using the tool.
- **Applets without an embedded Python runtime.** They do not get the modules.
- **A one-line write.** `omc_dialog_control "$UUID" 101 "done"` from a shell handler is not worse for being old.

Use the bridge when a handler needs to **read**, when it needs to make several changes atomically enough to batch, or when the logic is already Python.

## 12. Testing a bridge handler

`omctest` stands up a real ActionUI host for an applet that ships the client, so a handler's `omc.window()` works under test with no special case, and two assertions read what it did:

```sh
omc_run MyApp.refresh
check "the table was filled"  "1"     "$(bridge_called actionui.setRows)"
check "the field says ready"  "ready" "$(bridge_value 101)"
```

See section 4.11 of the [omctest guide](omctest_guide.md), which also explains why writes through `win.set_title()` are read back with `ui_title` rather than `bridge_value`.

## 13. How it works

The applet serves newline-delimited JSON-RPC 2.0 on a Unix domain socket, private to the user, started by the first ActionUI window it opens. Two environment variables address it, exported to every handler:

| Variable | |
| --- | --- |
| `$ACTIONUI_REMOTE_ENDPOINT` | the socket path; `$OMC_ACTIONUI_REMOTE_ENDPOINT` is the same value |
| `$ACTIONUI_WINDOW_UUID` | the window; `$OMC_ACTIONUI_WINDOW_UUID` is the same value |

The unprefixed pair is what the protocol itself names, so a script written against it runs unchanged whether its host is an OMC applet or any other ActionUI application. `actionui_remote` can be used directly for that reason; `omc.window()` simply returns a subclass with OMC's own verbs added.

The wire format is normative in `ActionUIRemote/PROTOCOL.md` in the ActionUI repository. Nothing about it is OMC-specific.

## Related Documentation

- [Python Scripting Guide](omc_python_scripting_guide.md) - Python handlers generally, and where the modules live
- [OMC Runtime Context Reference](omc_runtime_context_reference.md) - every environment variable and special word
- [omctest Guide](omctest_guide.md) - the applet test harness, and the bridge assertions
- [omc_dialog_control](omc_dialog_control--help.md) - the write path, for shell handlers
