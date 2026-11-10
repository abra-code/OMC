//
//  OMCProcessEnvironment.c
//  Abracode
//
//  Linux implementation of Platform/OMCProcessEnvironment.h. Not built yet: the Linux port has no
//  build. glibc and musl both export environ to shared libraries.
//

#include "OMCProcessEnvironment.h"

extern char **environ;

char **
OMCGetProcessEnviron(void)
{
	return environ;
}
