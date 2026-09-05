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

char ** CreateEnviron(char* const* inKeys, char* const* inValues, size_t inCount);
void ReleaseEnviron(char **inEnviron);

//Zero a buffer that held a secret, in a way the optimizer may not delete.
//
//A plain memset over a buffer nothing reads again is a dead store, and the compiler is entitled
//to remove it - which would leave the token sitting in a stack frame. memset_s is the standard
//answer but is C-only: C++ does not get the Annex K functions from <string.h>, and the engine
//clears its token buffer from C++. So this is one implementation for both, written through a
//volatile pointer, where every store is observable behavior and none may be elided.
void OMCSecureClear(void *inBuffer, size_t inSize);

//returns 0 if succeeded
//inEnvironList is terminated with entry where key=NULL
//inShell is a string list terminated with NULL
int omc_popen(const char *command, char * const *inShell, char * const *inEnvironList, unsigned int inMode, ChildProcessInfo *outChildProcessInfo);

//As omc_popen, plus a secret handed to the child on an inherited pipe instead of in its
//environment. The child sees ACTIONUI_REMOTE_TOKEN_FD=<inTokenFD> and reads the token, followed
//by a newline, from that descriptor; ACTIONUI_REMOTE_TOKEN is removed from its environment if
//the caller left one there. Nothing of the pipe remains in this process when the call returns.
//
//Why a pipe: a child's environment at exec time is what `ps` reports, and it reports it to any
//process of the same user unless the child carries CS_RESTRICT - which python3 and node do not.
//A token in envp is therefore readable by anything on the machine for as long as the handler
//runs; a token on a pipe is readable only by the handler, which drains it. See PROTOCOL.md
//section 10 in the ActionUI repository for the two-owner lifecycle this implements.
//
//inToken == NULL behaves exactly like omc_popen and inTokenFD is then ignored. Otherwise
//inTokenFD must be above STDERR_FILENO (3 is the number every client documents) and the token
//must be shorter than PIPE_BUF, so that one write cannot block or tear.
int omc_popen_with_token(const char *command, char * const *inShell, char * const *inEnvironList, unsigned int inMode, const char *inToken, int inTokenFD, ChildProcessInfo *outChildProcessInfo);
int omc_pclose(pid_t inChildPid);
void omc_pclose_write(pid_t inChildPid);

#ifdef __cplusplus
}
#endif
