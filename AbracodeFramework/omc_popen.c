/*
 * Copyright (c) 1988, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * This code is derived from software written by Ken Arnold and
 * published in UNIX Review, Vol. 6, No. 8.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the University of
 *	California, Berkeley and its contributors.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <sys/cdefs.h>

#include <sys/param.h>
#include <sys/wait.h>

#include <signal.h>
#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <paths.h>
#include <pthread.h>

#include <crt_externs.h>

#include "omc_popen.h"

//extern char **environ;

typedef struct ChildProcessInfoLink
{
	struct ChildProcessInfoLink *next;
	ChildProcessInfo info;
} ChildProcessInfoLink;

static ChildProcessInfoLink *sChildProcessInfoList = NULL;

static pthread_mutex_t pidlist_mutex = PTHREAD_MUTEX_INITIALIZER;

#define	THREAD_LOCK()		if( pthread_is_threaded_np() ) pthread_mutex_lock(&pidlist_mutex)
#define	THREAD_UNLOCK()		if( pthread_is_threaded_np() ) pthread_mutex_unlock(&pidlist_mutex)

enum
{
	kPipeReadEnd = 0,		
	kPipeWriteEnd = 1
};

#define CLOSE_FILE_DESCRIPTOR( _fd ) \
if( (_fd) >= 0 ) { \
	(void)close( (_fd) ); \
	(_fd) = -1;\
}


void PrintEnv(void)
{
	char*** envPtr = _NSGetEnviron();	// pointer to the real 'environ'
	char** environ = *envPtr;
	while (*environ != NULL)
	{
		printf("%s\n", *environ);
		environ++;
	}
}

/*
void
SetEnvironOneByOne(const EnvironmentPair *inEnvironList )
{
	if(inEnvironList != NULL)
	{
		while(inEnvironList->key != NULL)
		{
			setenv(inEnvironList->key, inEnvironList->value, 1);
			inEnvironList += 1;//next entry
		}
	}
}
*/

//caller responsible for freeing the result environ list with ReleaseEnviron()
char **
CreateEnviron(char* const* inKeys, char * const* inValues, size_t inCount)
{
	char*** envPtr = _NSGetEnviron();	// pointer to the real 'environ'
	char** oldEnviron = *envPtr;
	char** newEnviron = NULL;
	size_t oldCount = 0;
	size_t newCount = 0;
	size_t newIndex = 0;
	size_t i, j;
	char * newKeyValue;

	if(oldEnviron != NULL)
	{
		while(oldEnviron[oldCount] != NULL)
		{
			oldCount++;
		}
	}

	newCount = oldCount + inCount;
	newEnviron = (char**)calloc( newCount + 1, sizeof(char *) );
	
//now make sure we are not duplicating any values:

	for(j = 0; j < oldCount; j++)
	{
		char duplicateFound = 0;
		char *oneOldKeyEqValue = oldEnviron[j];
		size_t lenOld = 0;//length of key before first "="
		while( (oneOldKeyEqValue[lenOld] != 0) && (oneOldKeyEqValue[lenOld] != '=') )
		{
			lenOld++;
		}
	
		for(i = 0; i < inCount; i++)
		{
			size_t lenNew = 0;
			const char *oneNewKey = inKeys[i];
			while( oneNewKey[lenNew] != 0 )
			{
				lenNew++;
			}
			
			if(lenOld == lenNew)
			{//keys of the same length, check if they match
				size_t k = 0;
				for(k = 0; k < lenNew; k++)
				{
					if( oneNewKey[k] != oneOldKeyEqValue[k] )
						break;
				}
				duplicateFound = (k == lenNew);
			}
			if(duplicateFound)
				break;
		}
		
		if( !duplicateFound )
		{//copy old value - it is unique
			while( oneOldKeyEqValue[lenOld] != 0 )//continue counting characters past the '=' char
			{
				lenOld++;
			}
			
			newKeyValue = malloc(lenOld + 1);
			memcpy(newKeyValue, oneOldKeyEqValue, lenOld);
			newKeyValue[lenOld] = 0;
			newEnviron[newIndex] = newKeyValue;
			newIndex++;
		}
	}

//at this point all old "key=value" strings have been copied over
//now copy all new ones

	for(i = 0; i < inCount; i++)
	{
		size_t keyLen = 0, valueLen = 0;
		const char *oneNewKey = inKeys[i];
		const char *oneNewValue = inValues[i];

		while( (oneNewKey != NULL) && (oneNewKey[keyLen] != 0) )
		{
			keyLen++;
		}
		
		while( (oneNewValue != NULL) && (oneNewValue[valueLen] != 0) )
		{
			valueLen++;
		}

		newKeyValue = malloc(keyLen + 1 + valueLen + 1); // "key=value\0"
		if(keyLen > 0)
			memcpy(newKeyValue, oneNewKey, keyLen);
		newKeyValue[keyLen] = '=';
		if(valueLen > 0)
			memcpy(newKeyValue + keyLen + 1, oneNewValue, valueLen);
		newKeyValue[keyLen + 1 + valueLen] = 0;

		newEnviron[newIndex] = newKeyValue;
		newIndex++;
	}

	newEnviron[newIndex] = NULL;

	return newEnviron;
}

void
ReleaseEnviron(char **inEnviron)
{
	if(inEnviron == NULL)
		return;

	size_t i = 0;
	while(inEnviron[i] != NULL)
	{
		free( inEnviron[i] );
		i++;
	}
	free(inEnviron);
}


int
omc_popen(const char *command, char * const *inShell, char * const *inEnvironList, unsigned int inMode, ChildProcessInfo *outChildProcessInfo)
{
	char *argv[4];
	ChildProcessInfoLink *thisLink;
	ChildProcessInfoLink *oneLink;
	int pid = 0;
	int inputFDs[2] = {-1, -1};//file descriptors are valid in range <0, OPEN_MAX)
	int outputFDs[2] = {-1, -1};
	char **newArgs = NULL;
	char **shellArguments = argv;
	char *shellPath = _PATH_BSHELL;

//	PrintEnv();

	if( (command == NULL) || (outChildProcessInfo == NULL) )
		return -1;

	outChildProcessInfo->inputFD = -1;
	outChildProcessInfo->outputFD = -1;
	outChildProcessInfo->pid = 0;

	if( (inMode & kOMCPopenRead) != 0 )
	{
		if( pipe(outputFDs) < 0 )
			return -1;
	}

	if( (inMode & kOMCPopenWrite) != 0 )
	{
		if( pipe(inputFDs) < 0 )
		{
			CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
			CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);
			return -1;
		}
	}

	thisLink = malloc( sizeof(ChildProcessInfoLink) );
	thisLink->next = NULL;
	thisLink->info.inputFD = -1;
	thisLink->info.outputFD = -1;
	thisLink->info.pid = 0;

	if( thisLink == NULL )
	{
		CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeReadEnd] );
		CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeWriteEnd]);
		CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
		CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);
		return -1;
	}

	if(inShell != NULL)
	{
		//a list of strings, starting with shell path and arguments, for example:
		//	bin/sh
		//	-l
		//	-c
		int i;
		int itemCount = 0;
		while( inShell[itemCount] != NULL )
			itemCount++;
		
		if( itemCount > 0)
		{
			newArgs = (char **)malloc( sizeof(char *) * (itemCount+2) );//+2 for command and null terminator
			//arg 0 is the path to executed tool so we need to copy all of them
			for(i = 0; i < itemCount; i++)
			{
				newArgs[i] = inShell[i];
				
			}

			newArgs[itemCount] = (char *)command;
			newArgs[itemCount+1] = NULL;
			shellPath = inShell[0];
			shellArguments = newArgs;
		}
		else
		{
			inShell = NULL;
		}
	}


	if(inShell == NULL)
	{
		argv[0] = "sh";
		argv[1] = "-c";
		argv[2] = (char *)command;
		argv[3] = NULL;
		shellPath = _PATH_BSHELL;
		shellArguments = argv;
	}

	THREAD_LOCK();

	pid = vfork();
	if(pid == -1) /* Error. */
	{
		THREAD_UNLOCK();

		CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeReadEnd] );
		CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeWriteEnd]);
		CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
		CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);

		free(thisLink);
		if(newArgs != NULL)
			free(newArgs);
		return -1;
	}
	else if(pid == 0) /* Child. */
	{
		setpgid(0, 0);//will it create a new group?

		if( (inMode & kOMCPopenRead) != 0 )
		{
			close( outputFDs[kPipeReadEnd] );//do not uninit to -1 because this variable is shared by parent process too
			if( outputFDs[kPipeWriteEnd] != STDOUT_FILENO )
			{
				(void)dup2(outputFDs[kPipeWriteEnd], STDOUT_FILENO);
				close( outputFDs[kPipeWriteEnd]);
			}
		}
		
		if( (inMode & kOMCPopenWrite) != 0 )
		{
			close( inputFDs[kPipeWriteEnd] );//do not uninit to -1 because this varaible is shared by parent process too
			if( inputFDs[kPipeReadEnd] != STDIN_FILENO )
			{
				(void)dup2(inputFDs[kPipeReadEnd], STDIN_FILENO);
				close( inputFDs[kPipeReadEnd] );
			}
		}

		//close duplicate file descriptors in child process
		for( oneLink = sChildProcessInfoList; oneLink != NULL; oneLink = oneLink->next )
		{
			CLOSE_FILE_DESCRIPTOR( oneLink->info.inputFD );
			CLOSE_FILE_DESCRIPTOR( oneLink->info.outputFD );
		}

		if(inEnvironList == NULL)
			execv(shellPath, shellArguments);
		else
			execve(shellPath, shellArguments, inEnvironList);

		_exit(127);
		/* NOTREACHED */
	}
	THREAD_UNLOCK();

	thisLink->info.pid = pid;

	/* Parent */
	if( (inMode & kOMCPopenRead) != 0 )
	{
		thisLink->info.outputFD = outputFDs[kPipeReadEnd];
		close( outputFDs[kPipeWriteEnd] );
	}
	
	if( (inMode & kOMCPopenWrite) != 0 )
	{
		thisLink->info.inputFD = inputFDs[kPipeWriteEnd];
		close(  inputFDs[kPipeReadEnd] );
	}
	
	THREAD_LOCK();
	thisLink->next = sChildProcessInfoList;
	sChildProcessInfoList = thisLink;
	THREAD_UNLOCK();

	*outChildProcessInfo = thisLink->info;

	if(newArgs != NULL)
		free(newArgs);

	return 0;
}

/*
 * pclose --
 *	Pclose returns -1 if stream is not associated with a `popened' command,
 *	if already `pclosed', or waitpid returns an error.
 */
int
omc_pclose(pid_t inChildPid)
{
	ChildProcessInfoLink *thisLink = NULL, *lastLink = NULL;
	int pstat = 0;
	pid_t pid = 0;

	/*
	 * Find the appropriate file pointer and remove it from the list.
	 */
	THREAD_LOCK();
	for (lastLink = NULL, thisLink = sChildProcessInfoList; thisLink != NULL; lastLink = thisLink, thisLink = thisLink->next)
	{
		if (thisLink->info.pid == inChildPid)
			break;
	}

	if( thisLink == NULL )
	{
		THREAD_UNLOCK();
		return (-1);
	}

	if (lastLink == NULL)
		sChildProcessInfoList = thisLink->next;
	else
		lastLink->next = thisLink->next;

	THREAD_UNLOCK();

	CLOSE_FILE_DESCRIPTOR( thisLink->info.inputFD );
	CLOSE_FILE_DESCRIPTOR( thisLink->info.outputFD );

	do
	{
		pid = wait4( thisLink->info.pid, &pstat, 0, (struct rusage *)0 );
	}
	while (pid == -1 && errno == EINTR);

	free(thisLink);

	return (pid == -1 ? -1 : pstat);
}

//half-close. needs to be followed by full omc_pclose() when really done
void omc_pclose_write(pid_t inChildPid)
{
	ChildProcessInfoLink *thisLink = NULL;

	THREAD_LOCK();

	for (thisLink = sChildProcessInfoList; thisLink != NULL; thisLink = thisLink->next)
	{
		if (thisLink->info.pid == inChildPid)
		{
			CLOSE_FILE_DESCRIPTOR( thisLink->info.inputFD );//sets the fd to invalid
		}
	}

	THREAD_UNLOCK();
}
