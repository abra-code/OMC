//
//  OMCProcessEnvironment.h
//  Abracode
//
//  The process's own environment, as the libc environ variable holds it, for code that builds a
//  child's environment from it (omc_popen.c's CreateEnviron).
//

#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// The current environment: "KEY=value" strings ending with NULL, owned by libc; setenv and
// unsetenv may replace it, so read it again after them. macOS: a framework cannot refer to
// environ directly, so it is *_NSGetEnviron(); Linux: environ.
char **OMCGetProcessEnviron(void);

// A variable the platform gives every child unless the engine's own environment or the command
// already names it, so a user's or a command's own value wins (CreateEnviron).
typedef struct OMCChildEnvironmentDefault
{
	const char *name;
	const char *value;
} OMCChildEnvironmentDefault;

// The platform's defaults for a child's environment, *outCount of them (0 and NULL when none).
// The list is static; the caller does not free it.
const OMCChildEnvironmentDefault *OMCGetChildEnvironmentDefaults(size_t *outCount);

#ifdef __cplusplus
}
#endif
