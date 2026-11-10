//
//  OMCProcessEnvironment.h
//  Abracode
//
//  The process's own environment, as the libc environ variable holds it, for code that builds a
//  child's environment from it (omc_popen.c's CreateEnviron).
//

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// The current environment: "KEY=value" strings ending with NULL, owned by libc; setenv and
// unsetenv may replace it, so read it again after them. macOS: a framework cannot refer to
// environ directly, so it is *_NSGetEnviron(); Linux: environ.
char **OMCGetProcessEnviron(void);

#ifdef __cplusplus
}
#endif
