# defaults

User settings for an applet's scripts: the part of macOS's `defaults` that applets use, the same on macOS and Linux. It ships in the engine's Support folder beside `plister` (Command Workshop 6.0), so every applet has it at `$OMC_OMC_SUPPORT_PATH/defaults`.

```
defaults read <domain> <key>
defaults write <domain> <key> [-string | -bool | -int | -float] <value>
defaults delete <domain> [<key>]
```

```bash
defaults="$OMC_OMC_SUPPORT_PATH/defaults"
"$defaults" write com.example.myapplet LastFolder "$folder"
folder="$("$defaults" read com.example.myapplet LastFolder 2>/dev/null)"
"$defaults" write com.example.myapplet ShowHidden -bool true
```

## Where the settings are kept

| Situation | Store |
|---|---|
| `OMC_DEFAULTS_PATH` is set (a folder) | one JSON file per domain there, `<folder>/<domain>.json`, on either system |
| macOS | `/usr/bin/defaults`, with the same arguments: the user's preferences, readable with `defaults read` in Terminal |
| Linux | one JSON file per domain in `${XDG_CONFIG_HOME:-~/.config}`, e.g. `~/.config/com.example.myapplet.json` |

The JSON files are written with `plister`. A domain with a `/` in it is a file path, as with macOS's `defaults`: `<path>.json`, or the path as given when it ends in `.json` or `.plist`.

**Tests.** The integration-test runner (`appletbuilder itest`) and the handler test runner (`appletbuilder test`, API 8) set `OMC_DEFAULTS_PATH` to the test's private home (`Library/Preferences`), so what a handler saves through this tool never reaches the user's settings. On macOS `/usr/bin/defaults` called directly cannot be redirected that way: the preferences daemon keys settings by user, not by `$HOME`. Use this tool for an applet's own settings.

## What it accepts

The same on both systems, so a script that works on one works on the other:

- `read` needs a key, and prints the value: a string as it is, an integer, a real (`1.5`), a bool as `1` or `0`. A domain or key that is not there prints nothing on stdout and exits 1.
- `write` with no type stores a string, as given (macOS's own `defaults` would parse `(1, 2)` or `{a = b;}`; this one does not). `-bool` takes `true`, `false`, `yes`, `no`, `1` or `0` (any case); `-int` a whole number; `-float` a number. Writing a key again replaces it, with its new type.
- `delete` with a key removes that key; without one, the whole domain.
- A key may not contain `/`. Dictionaries, arrays, dates and data are not supported, nor `-g`, `domains`, `export` or `import`.

Exit status: 0 done; 1 no such domain or key (`read`, `delete`), or the settings could not be written; 2 bad arguments.

Settings the system itself reads (on macOS, for example AppKit's `NSAutomaticQuoteSubstitutionEnabled` for the applet's text fields) belong in the system's preferences: write those with `/usr/bin/defaults` on macOS. They have no meaning on Linux.
