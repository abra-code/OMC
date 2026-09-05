#include <sys/cdefs.h>
#include <sys/param.h>
#include <limits.h>       // PIPE_BUF, for the token write
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
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


void
OMCSecureClear(void *inBuffer, size_t inSize)
{
    if(inBuffer == NULL)
        return;

    volatile unsigned char *cursor = (volatile unsigned char *)inBuffer;
    while(inSize-- > 0)
        *cursor++ = 0;
}

// Mark a pipe fd close-on-exec so it cannot leak into an unrelated child that happens to
// be spawned concurrently. The explicit close loop below only covers children already
// registered in sChildProcessInfoList; a pipe still being set up here is not yet in that
// list. The child's own stdin/stdout are re-established by the adddup2 file actions, and
// dup2 target fds are never close-on-exec, so this does not affect the command's std
// streams. (macOS has no pipe2(), so this is done with fcntl right after pipe(); in the
// current single-threaded usage there is no concurrent spawn, so the tiny pipe()->fcntl
// window is not a real race - this is future-proofing should omc_popen ever be threaded.)
static inline void SetCloseOnExec(int fd)
{
    if(fd >= 0)
    {
        int flags = fcntl(fd, F_GETFD);
        if(flags >= 0)
            (void)fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
    }
}

// The two names of the ActionUI remote token contract. The token itself must never be in a
// child's environment - see omc_popen.h - so this file only ever removes that name, and only
// ever adds the one that carries the descriptor number, which is no secret.
static const char kActionUITokenVariable[] = "ACTIONUI_REMOTE_TOKEN";
static const char kActionUITokenFDVariable[] = "ACTIONUI_REMOTE_TOKEN_FD";

// True when "key=..." names exactly inKey. The '=' test is what keeps ACTIONUI_REMOTE_TOKEN_FD
// from matching the prefix ACTIONUI_REMOTE_TOKEN.
static bool EnvironEntryHasKey(const char *inEntry, const char *inKey, size_t inKeyLength)
{
    return (strncmp(inEntry, inKey, inKeyLength) == 0) && (inEntry[inKeyLength] == '=');
}

// The child's environment for a token handoff: every entry the caller built, minus any spelling
// of the two token variables, plus ACTIONUI_REMOTE_TOKEN_FD naming the descriptor this call
// created. Building it here rather than in the caller is what makes the number and the
// descriptor impossible to disagree about, and it is the only place that can strip a token the
// caller left in the list. Free with ReleaseEnviron. NULL on allocation failure.
static char **
CreateEnvironForTokenDescriptor(char * const *inEnvironList, int inTokenFD)
{
    size_t oldCount = 0;
    if(inEnvironList != NULL)
    {
        while(inEnvironList[oldCount] != NULL)
            oldCount++;
    }

    char **newEnviron = (char **)calloc( oldCount + 2, sizeof(char *) ); // +1 new entry, +1 terminator
    if(newEnviron == NULL)
        return NULL;

    size_t newIndex = 0;
    for(size_t i = 0; i < oldCount; i++)
    {
        const char *oneEntry = inEnvironList[i];
        if( EnvironEntryHasKey(oneEntry, kActionUITokenVariable, sizeof(kActionUITokenVariable) - 1) ||
            EnvironEntryHasKey(oneEntry, kActionUITokenFDVariable, sizeof(kActionUITokenFDVariable) - 1) )
        {
            continue;
        }

        newEnviron[newIndex] = strdup(oneEntry);
        if(newEnviron[newIndex] == NULL)
        {
            ReleaseEnviron(newEnviron);
            return NULL;
        }
        newIndex++;
    }

    char descriptorEntry[64];
    int written = snprintf(descriptorEntry, sizeof(descriptorEntry), "%s=%d", kActionUITokenFDVariable, inTokenFD);
    if( (written <= 0) || ((size_t)written >= sizeof(descriptorEntry)) )
    {
        ReleaseEnviron(newEnviron);
        return NULL;
    }

    newEnviron[newIndex] = strdup(descriptorEntry);
    if(newEnviron[newIndex] == NULL)
    {
        ReleaseEnviron(newEnviron);
        return NULL;
    }
    newIndex++;
    newEnviron[newIndex] = NULL;
    return newEnviron;
}

int
omc_popen(const char *command, char * const *inShell, char * const *inEnvironList, unsigned int inMode, ChildProcessInfo *outChildProcessInfo)
{
    return omc_popen_with_token( command, inShell, inEnvironList, inMode, NULL, -1, outChildProcessInfo );
}

int
omc_popen_with_token(const char *command, char * const *inShell, char * const *inEnvironList, unsigned int inMode,
                     const char *inToken, int inTokenFD, ChildProcessInfo *outChildProcessInfo)
{
    //	PrintEnv();
    
    if( (command == NULL) || (outChildProcessInfo == NULL) )
        return -1;
    
    outChildProcessInfo->inputFD = -1;
    outChildProcessInfo->outputFD = -1;
    outChildProcessInfo->pid = 0;

    size_t tokenLength = 0;
    if(inToken != NULL)
    {
        // Above stderr, because the three standard descriptors are dup2 targets below and the
        // child needs all of them. Shorter than PIPE_BUF so the single write below cannot tear
        // or block: a token is 64 hex characters, and one that does not fit is a bug worth
        // failing on rather than a case worth looping over.
        if(inTokenFD <= STDERR_FILENO)
            return -1;
        tokenLength = strlen(inToken);
        if( (tokenLength == 0) || ((tokenLength + 1) >= PIPE_BUF) )
            return -1;
    }
    
    int inputFDs[2] = {-1, -1}; // file descriptors are valid in range <0, OPEN_MAX)
    int outputFDs[2] = {-1, -1};
    int tokenFDs[2] = {-1, -1};

    if( (inMode & kOMCPopenRead) != 0 )
    {
        if( pipe(outputFDs) < 0 )
            return -1;
        SetCloseOnExec( outputFDs[kPipeReadEnd] );
        SetCloseOnExec( outputFDs[kPipeWriteEnd] );
    }

    if( (inMode & kOMCPopenWrite) != 0 )
    {
        if( pipe(inputFDs) < 0 )
        {
            CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
            CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);
            return -1;
        }
        SetCloseOnExec( inputFDs[kPipeReadEnd] );
        SetCloseOnExec( inputFDs[kPipeWriteEnd] );
    }

    if(inToken != NULL)
    {
        if( pipe(tokenFDs) < 0 )
        {
            CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeReadEnd] );
            CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeWriteEnd]);
            CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
            CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);
            return -1;
        }
        // pipe() hands back the two lowest free descriptors, so the read end can land exactly on
        // the number the caller asked for. Move it off, because a same-descriptor dup2 would not
        // deliver it: POSIX.1-2008 TC2 says posix_spawn_file_actions_adddup2(fa, fd, fd) clears
        // FD_CLOEXEC, and **Darwin does not** - measured, and the child then finds the descriptor
        // closed while this function reports success. dup() cannot hand back inTokenFD here,
        // because inTokenFD is still occupied by the descriptor being duplicated.
        if(tokenFDs[kPipeReadEnd] == inTokenFD)
        {
            int movedReadEnd = dup(tokenFDs[kPipeReadEnd]);
            if(movedReadEnd < 0)
            {
                CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeReadEnd] );
                CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeWriteEnd]);
                CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
                CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);
                CLOSE_FILE_DESCRIPTOR( tokenFDs[kPipeReadEnd] );
                CLOSE_FILE_DESCRIPTOR( tokenFDs[kPipeWriteEnd]);
                return -1;
            }
            (void)close( tokenFDs[kPipeReadEnd] );
            tokenFDs[kPipeReadEnd] = movedReadEnd;
        }

        // Both ends, for the same reason the pipes above are marked: a spawn running
        // concurrently must not inherit either. The read end still survives into the child,
        // because it now always arrives there as a dup2 onto a DIFFERENT descriptor, and that
        // is the case where dup2 does clear FD_CLOEXEC.
        SetCloseOnExec( tokenFDs[kPipeReadEnd] );
        SetCloseOnExec( tokenFDs[kPipeWriteEnd] );
    }
    
    ChildProcessInfoLink *thisLink = malloc(sizeof(ChildProcessInfoLink));
    if(thisLink == NULL)
    {
        CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeReadEnd] );
        CLOSE_FILE_DESCRIPTOR( inputFDs[kPipeWriteEnd]);
        CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeReadEnd] );
        CLOSE_FILE_DESCRIPTOR( outputFDs[kPipeWriteEnd]);
        CLOSE_FILE_DESCRIPTOR( tokenFDs[kPipeReadEnd] );
        CLOSE_FILE_DESCRIPTOR( tokenFDs[kPipeWriteEnd]);
        return -1;
    }

    thisLink->next = NULL;
    thisLink->info.inputFD = -1;
    thisLink->info.outputFD = -1;
    thisLink->info.pid = 0;
    
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
    char **tokenEnviron = NULL;
    
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

    // The token pipe, LAST of all the file actions and deliberately so: they are applied in
    // order, and the loop above closes descriptors by number. An earlier child's pipe may well
    // be sitting on the number the token is going to (3 is a very ordinary fd), so a dup2 placed
    // before that loop would be undone by it.
    if(inToken != NULL) {
        // The read end was moved off inTokenFD above, so this dup2 always crosses descriptors -
        // which is what makes it clear FD_CLOEXEC and actually deliver - and the close below is
        // always of a different descriptor.
        if (posix_spawn_file_actions_adddup2(&file_actions, tokenFDs[kPipeReadEnd], inTokenFD) != 0)
            goto spawn_error;
        if (posix_spawn_file_actions_addclose(&file_actions, tokenFDs[kPipeReadEnd]) != 0)
            goto spawn_error;
        // The child must not hold its own pipe's write end: it would then never see EOF on a
        // token it did not read to the end. FD_CLOEXEC above covers this too; both are cheap.
        //
        // Guarded, and it matters: pipe() hands back the two lowest free descriptors, so the
        // write end can perfectly well BE inTokenFD - ask for 7 and get a pipe on {6, 7}. The
        // dup2 just above has already closed it in the child, and an unconditional close here
        // would then close the token descriptor straight back off again.
        if (tokenFDs[kPipeWriteEnd] != inTokenFD) {
            if (posix_spawn_file_actions_addclose(&file_actions, tokenFDs[kPipeWriteEnd]) != 0)
                goto spawn_error;
        }
    }
    
    // Spawn the process
    // NOTE: environ parameter must NOT be NULL - use empty array for no environment
    char *empty_env[] = { NULL };
    char *const *use_environ = (inEnvironList != NULL) ? inEnvironList : empty_env;

    if(inToken != NULL) {
        tokenEnviron = CreateEnvironForTokenDescriptor(inEnvironList, inTokenFD);
        if(tokenEnviron == NULL)
            goto spawn_error;
        use_environ = tokenEnviron;

        // Written before the spawn, not after: the parent holds both ends, so 65 bytes into an
        // empty pipe cannot block, and a write that fails here fails with no child running
        // rather than leaving one blocked forever on a token that will never arrive.
        char tokenLine[PIPE_BUF];
        memcpy(tokenLine, inToken, tokenLength);
        tokenLine[tokenLength] = '\n';
        ssize_t written = write(tokenFDs[kPipeWriteEnd], tokenLine, tokenLength + 1);
        OMCSecureClear(tokenLine, tokenLength + 1);
        if(written != (ssize_t)(tokenLength + 1))
            goto spawn_error;
    }
    
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

    ReleaseEnviron(tokenEnviron);
    tokenEnviron = NULL;

    // The token is in the child's hands, or will be as soon as it reads. Both ends go now:
    // nothing of the pipe remains in this process, and the write end in particular must go or
    // the child never sees EOF. Deliberately NOT registered in sChildProcessInfoList - that list
    // exists for the stdio pipes, which outlive the call; these two do not.
    CLOSE_FILE_DESCRIPTOR( tokenFDs[kPipeWriteEnd] );
    CLOSE_FILE_DESCRIPTOR( tokenFDs[kPipeReadEnd] );

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
    CLOSE_FILE_DESCRIPTOR(tokenFDs[kPipeReadEnd]);
    CLOSE_FILE_DESCRIPTOR(tokenFDs[kPipeWriteEnd]);
    
    ReleaseEnviron(tokenEnviron);
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
