./pasteboard --help

```
NAME
	pasteboard - set or get Mac OS X pasteboard string

SYNOPSIS
	pasteboard "Pasteboard Name" put[set]|get "String To Set"

DESCRIPTION
	pasteboard allows you set or get a string in Mac OS X pasteboard
	It supports private (named) pasteboards as well as global "general" and "find" pasteboards
	It can be used for interprocess communication through private pasteboards
	You can use either "put" or "set" command for putting the string in the pasteboard
```

## On Linux

The same command line, from a script (`pasteboard/linux/pasteboard` in the repository) in the framework's Support folder:

- A named pasteboard is a file in a private folder of the user's: `$XDG_RUNTIME_DIR/omc-pasteboards` (which lives as long as the login session, as macOS's pasteboard server does), or `${TMPDIR:-/tmp}/omc-pasteboards-<user id>` when `XDG_RUNTIME_DIR` is not set; `OMC_PASTEBOARD_PATH`, a folder, takes their place. Any name works, `/` and spaces included.
- `put`/`set` with a string stores it as given; with no string, stdin as it comes. `get` prints the value with nothing added; a pasteboard never written prints nothing.
- `general` and `find`, the system clipboard on macOS, are not available on Linux yet (exit status 1): a command-line tool cannot keep the clipboard on Wayland after it exits.
- A name that merely starts with `general` or `find` (`findSelection`) is a named pasteboard on Linux; on macOS it is the general or find pasteboard. Use other names for your own pasteboards.

**Tests.** In an OMC test launch (`appletbuilder itest`), every pasteboard, `general` included, is the run's own, on both systems, and the engine reads the run's `general` as the clipboard. On Linux the run's pasteboards are files in the run's own folder (`OMC_PASTEBOARD_PATH`), so they go with it.
