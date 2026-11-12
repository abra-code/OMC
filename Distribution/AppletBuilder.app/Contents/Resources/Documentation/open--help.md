# open

Opens files, folders, URLs and applications from an applet's scripts: the part of macOS's `open` that applets use, the same on macOS and Linux. It ships in the engine's Support folder beside `plister` (Command Workshop 6.0), so every applet has it at `$OMC_OMC_SUPPORT_PATH/open`.

```
open <file, folder or URL>...
open -R <file or folder>...
open -a <application> [<file>...]
```

```bash
open_tool="$OMC_OMC_SUPPORT_PATH/open"
"$open_tool" "$OMC_OBJ_PATH"                      # in its default application
"$open_tool" -R "$OMC_OBJ_PATH"                   # shown in the file manager, selected
"$open_tool" -a "$editor" "$OMC_OBJ_PATH"         # with a chosen application
"$open_tool" "https://example.com"                # a URL in the browser
```

## What it does

| | macOS | Linux |
|---|---|---|
| `open <item>` | `/usr/bin/open` | `gio open`; an applet bundle (`<name>.app`) runs its `Contents/Linux` executable |
| `open -R <item>` | `/usr/bin/open -R` (Finder) | the file manager, through its `org.freedesktop.FileManager1` D-Bus service; with none, the containing folder opens |
| `open -a <app> [<file>...]` | `/usr/bin/open -a` | runs the application with the files' absolute paths as arguments, detached: an applet bundle (its `Contents/Linux` executable), an executable's path, or a command on `PATH` |

On Linux the application `-a` starts runs in a session of its own, so the handler that started it does not wait for it, and its output goes nowhere. An applet bundle's executable is the one `CFBundleExecutable` names in its `Info.plist`.

## What it accepts

The same on both systems, so a script that works on one works on the other:

- A file or folder must exist (`The file <path> does not exist.`, status 1); a URL (a scheme of two or more characters and a colon, such as `https:` or `mailto:`) is passed on as it is, unless a file of that name exists (`ab:c`), which opens as a file, as with macOS's `open`.
- Only `-R` and `-a` are accepted as options; macOS's other options (`-e`, `-t`, `-g`, `-W` and so on) are refused (status 2). An applet that needs them calls `/usr/bin/open` on macOS itself.
- An application name with no path (`-a TextEdit`) means an application on macOS and a command on `PATH` on Linux; a path to an applet bundle or an executable works on both.

Exit status: 0 done; 1 a file or application not found, or it could not be opened; 2 bad arguments.
