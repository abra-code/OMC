/*
 *  omc_popen.h
 *  
 *
 *  Created by Tomasz Kukielka on 5/30/07.
 *  Copyright 2007 Abracode. All rights reserved.
 *
 */

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ChildProcessInfo
{
	int inputFD;
	int outputFD;
	pid_t pid;
} ChildProcessInfo;

typedef enum OMCPopenExecutionMode
{
	kOMCPopenRead = 0x01,
	kOMCPopenWrite = 0x02,
} OMCPopenExecutionMode;

char ** CreateEnviron(char **inKeys, char **inValues, size_t inCount);
void ReleaseEnviron(char **inEnviron);

//returns 0 if succeeded
//inEnvironList is terminated with entry where key=NULL
//inShell is a string list terminated with NULL
int omc_popen(const char *command, char **inShell, char **inEnvironList, unsigned int inMode, ChildProcessInfo *outChildProcessInfo);
int omc_pclose(pid_t inChildPid);
void omc_pclose_write(pid_t inChildPid);

#ifdef __cplusplus
}
#endif
