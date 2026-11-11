//
//  OMCUnixSocketAddress.h (Linux)
//  Abracode
//
//  The address of a Unix domain socket in the engine's private folder, for omc_dialog_control's port
//  (both ends: Common/Linux/OMCDialogControlSender.c and Platform/Linux/OMCMessagePortListener.cpp).
//
//  A socket's path may hold only 107 bytes (sun_path), and the private folder under a long home path
//  ($XDG_RUNTIME_DIR unset: ~/.cache/omc/tmp) can leave too little room for the leaf name. So the
//  folder is opened (O_PATH) and checked, and the socket is reached as /proc/self/fd/<fd>/<leaf>:
//  Linux resolves it through the descriptor, so the length of the folder's path does not matter, and
//  the folder used is the one checked (no swap between the check and the use). Probe and options:
//  ~/git/AppleCoreLibrariesForLinux/build/probe/dialog-control-socket/REPORT.md (option 1).
//

#pragma once

#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

// Splits inSocketPath into its folder and leaf, opens the folder and checks that it is a folder this
// user owns that no one else can enter or write (the engine's private folder), and fills outAddress
// with the descriptor-relative path of the leaf. Returns the folder's descriptor, which the caller
// keeps open while it binds or connects and then closes; -1 with errno set on failure.
static inline int OMCMakeUnixSocketAddress(const char *inSocketPath, struct sockaddr_un *outAddress, const char **outLeaf)
{
	if((inSocketPath == NULL) || (outAddress == NULL))
	{
		errno = EINVAL;
		return -1;
	}
	const char *slash = strrchr(inSocketPath, '/');
	if((slash == NULL) || (slash == inSocketPath) || (slash[1] == '\0'))
	{
		errno = EINVAL;
		return -1;
	}
	const char *leaf = slash + 1;
	size_t folderLength = (size_t)(slash - inSocketPath);
	char folder[4096];
	if(folderLength >= sizeof(folder))
	{
		errno = ENAMETOOLONG;
		return -1;
	}
	memcpy(folder, inSocketPath, folderLength);
	folder[folderLength] = '\0';

	int folderFD = open(folder, O_PATH | O_DIRECTORY | O_CLOEXEC);
	if(folderFD < 0)
		return -1;

	struct stat folderInfo;
	if(fstat(folderFD, &folderInfo) != 0)
	{
		int savedErrno = errno;
		close(folderFD);
		errno = savedErrno;
		return -1;
	}
	if(!S_ISDIR(folderInfo.st_mode) || (folderInfo.st_uid != getuid()) || ((folderInfo.st_mode & (S_IRWXG | S_IRWXO)) != 0))
	{
		close(folderFD);
		errno = EACCES;
		return -1;
	}

	memset(outAddress, 0, sizeof(*outAddress));
	outAddress->sun_family = AF_UNIX;
	int n = snprintf(outAddress->sun_path, sizeof(outAddress->sun_path), "/proc/self/fd/%d/%s", folderFD, leaf);
	if((n < 0) || ((size_t)n >= sizeof(outAddress->sun_path)))
	{
		close(folderFD);
		errno = ENAMETOOLONG;
		return -1;
	}
	if(outLeaf != NULL)
		*outLeaf = leaf;
	return folderFD;
}
