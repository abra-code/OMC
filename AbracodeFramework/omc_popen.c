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
#include <spawn.h>

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

#if 0
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
#endif // 0

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
    //	PrintEnv();
    
    if( (command == NULL) || (outChildProcessInfo == NULL) )
        return -1;
    
    outChildProcessInfo->inputFD = -1;
    outChildProcessInfo->outputFD = -1;
    outChildProcessInfo->pid = 0;
    
    int inputFDs[2] = {-1, -1}; // file descriptors are valid in range <0, OPEN_MAX)
    int outputFDs[2] = {-1, -1};

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
    
    ChildProcessInfoLink *thisLink = malloc(sizeof(ChildProcessInfoLink));
    thisLink->next = NULL;
    thisLink->info.inputFD = -1;
    thisLink->info.outputFD = -1;
    thisLink->info.pid = 0;
    
    if(thisLink == NULL)
    {
        CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeReadEnd] );
        CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeWriteEnd]);
        CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
        CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);
        return -1;
    }
    
    char *shellPath = _PATH_BSHELL;
    char *default_argv[] = { "sh", "-c", (char *)command, NULL };
    char **shellArguments = NULL;
    char **newArgs = NULL;
    
    if(inShell != NULL)
    {
        //a list of strings, starting with shell path and arguments, for example:
        //	bin/sh
        //	-l
        //	-c
        int i;
        int itemCount = 0;
        while( inShell[itemCount] != NULL )
        {
            itemCount++;
        }
        
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
        shellArguments = default_argv;
    }
    
    posix_spawnattr_t attr = NULL;
    posix_spawn_file_actions_t file_actions = NULL;
    bool attributes_initialized = false;
    bool file_actions_initialized = false;
    
    THREAD_LOCK();
    
    // Set up posix_spawn attributes
    if (posix_spawnattr_init(&attr) != 0) {
        goto spawn_error;
    }
    attributes_initialized = true;
    
    if (posix_spawn_file_actions_init(&file_actions) != 0) {
        goto spawn_error;
    }
    file_actions_initialized = true;
    
    // Set process group - equivalent to setpgid(0, 0)
    if (posix_spawnattr_setpgroup(&attr, 0) != 0) {
        goto spawn_error;
    }
    
    if (posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP) != 0) {
        goto spawn_error;
    }
    
    // Configure file descriptors for child
    if ((inMode & kOMCPopenRead) != 0) {
        if (posix_spawn_file_actions_addclose(&file_actions, outputFDs[kPipeReadEnd]) != 0)
            goto spawn_error;
        if (outputFDs[kPipeWriteEnd] != STDOUT_FILENO) {
            if (posix_spawn_file_actions_adddup2(&file_actions, outputFDs[kPipeWriteEnd], STDOUT_FILENO) != 0)
                goto spawn_error;
            if (posix_spawn_file_actions_addclose(&file_actions, outputFDs[kPipeWriteEnd]) != 0)
                goto spawn_error;
        }
    }
    
    if ((inMode & kOMCPopenWrite) != 0) {
        if (posix_spawn_file_actions_addclose(&file_actions, inputFDs[kPipeWriteEnd]) != 0)
            goto spawn_error;
        if (inputFDs[kPipeReadEnd] != STDIN_FILENO) {
            if (posix_spawn_file_actions_adddup2(&file_actions, inputFDs[kPipeReadEnd], STDIN_FILENO) != 0)
                goto spawn_error;
            if (posix_spawn_file_actions_addclose(&file_actions, inputFDs[kPipeReadEnd]) != 0)
                goto spawn_error;
        }
    }
    
    // Close inherited file descriptors from parent's child list
    for (ChildProcessInfoLink *link = sChildProcessInfoList; link != NULL; link = link->next) {
        if (link->info.inputFD >= 0)
            posix_spawn_file_actions_addclose(&file_actions, link->info.inputFD);
        if (link->info.outputFD >= 0)
            posix_spawn_file_actions_addclose(&file_actions, link->info.outputFD);
    }
    
    // Spawn the process
    // NOTE: environ parameter must NOT be NULL - use empty array for no environment
    char *empty_env[] = { NULL };
    char *const *use_environ = (inEnvironList != NULL) ? inEnvironList : empty_env;
    
    int pid = 0;
    int spawn_result = posix_spawn(&pid, shellPath, &file_actions, &attr,
                                   shellArguments, use_environ);
    
    // Clean up attributes
    if (file_actions_initialized) {
        posix_spawn_file_actions_destroy(&file_actions);
    }
    if (attributes_initialized) {
        posix_spawnattr_destroy(&attr);
    }
    
    if (spawn_result != 0) {
        goto spawn_error;
    }
    
    THREAD_UNLOCK();

    // Continue with existing parent code...
    thisLink->info.pid = pid;
    
    /* Parent - rest stays the same */
    if ((inMode & kOMCPopenRead) != 0) {
        thisLink->info.outputFD = outputFDs[kPipeReadEnd];
        close(outputFDs[kPipeWriteEnd]);
    }
    
    if ((inMode & kOMCPopenWrite) != 0) {
        thisLink->info.inputFD = inputFDs[kPipeWriteEnd];
        close(inputFDs[kPipeReadEnd]);
    }
    
    THREAD_LOCK();
    thisLink->next = sChildProcessInfoList;
    sChildProcessInfoList = thisLink;
    THREAD_UNLOCK();

    *outChildProcessInfo = thisLink->info;
    free(newArgs);
    return 0;

spawn_error:
    if (file_actions_initialized) {
        posix_spawn_file_actions_destroy(&file_actions);
    }
    if (attributes_initialized) {
        posix_spawnattr_destroy(&attr);
    }
    
    THREAD_UNLOCK();
    
    CLOSE_FILE_DESCRIPTOR(inputFDs[kPipeReadEnd]);
    CLOSE_FILE_DESCRIPTOR(inputFDs[kPipeWriteEnd]);
    CLOSE_FILE_DESCRIPTOR(outputFDs[kPipeReadEnd]);
    CLOSE_FILE_DESCRIPTOR(outputFDs[kPipeWriteEnd]);
    
    free(thisLink);
    free(newArgs);
    
    return -1;
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
    int status = 0;
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
        pid = waitpid(inChildPid, &status, 0);
    }
    while (pid == -1 && errno == EINTR);

	free(thisLink);

    return (pid == inChildPid) ? status : -1;
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
