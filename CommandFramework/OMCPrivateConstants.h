
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// Absolute path of the directory Python bytecode caches are redirected to. Exported as
// PYTHONPYCACHEPREFIX before executing Python code, so that .pyc files never land next to their
// source - which, for an interpreter embedded in the app, means inside the signed bundle.
//
// Was the fixed literal "/tmp/Pyc". It is now per-user, because what accumulates in this
// directory is executable bytecode that CPython loads back after validating nothing but the
// source file's mtime and size. Both are trivial to reproduce for anyone who can read the
// applet, and /tmp is world-writable, so a fixed path there can be created first by another
// local user who then decides what our interpreter executes.
//
// Returns NULL only if no directory could be determined, in which case the caller must NOT set
// the variable at all rather than substitute a guess. That is not the same as caching into the
// bundle: the two callers back each other up, since a handler spawned by OmcExecutor still
// inherits whatever the app process already had. The returned string is owned by the callee and
// valid for the life of the process.
const char *OMCGetPythonPycachePrefix(void);

#ifdef __cplusplus
}
#endif
