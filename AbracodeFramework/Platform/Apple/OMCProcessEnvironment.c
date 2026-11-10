//
//  OMCProcessEnvironment.c
//  Abracode
//
//  The macOS implementation of Platform/OMCProcessEnvironment.h: a framework cannot link against
//  environ (only the main executable's crt has it), so it is read through _NSGetEnviron.
//

#include "OMCProcessEnvironment.h"
#include <crt_externs.h>
#include <stddef.h>

char **
OMCGetProcessEnviron(void)
{
	char ***envPtr = _NSGetEnviron(); // pointer to the real 'environ'
	return (envPtr != NULL) ? *envPtr : NULL;
}
