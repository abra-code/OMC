//
//  StandardDirectories.cpp (Linux)
//  Abracode
//
//  The Linux implementation of Platform/StandardDirectories.h: the XDG base directories
//  (freedesktop.org's rules for per-user folders), as the macOS one gives ~/Library's. Not built
//  yet: the Linux port has no build.
//
//  - Preferences: $XDG_CONFIG_HOME, else ~/.config. Not made here, as on macOS, where only
//    ~/Library is: a reader of a missing preferences file needs no folder.
//  - Application support: $XDG_DATA_HOME, else ~/.local/share, made if missing (with mode 0700,
//    as XDG asks for a folder it makes), as macOS makes ~/Library/Application Support.
//  A relative XDG value is ignored, as XDG says: such paths are invalid.
//

#include "StandardDirectories.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <string>

// inPath without trailing slashes ("/" stays): a HOME of "/home/u/" would otherwise give
// "/home/u//.config", which scripts get in paths built from it (macOS's NSFileManager tidies it)
static std::string
WithoutTrailingSlashes(const char *inPath)
{
	std::string path(inPath);
	while( (path.size() > 1) && (path.back() == '/') )
		path.pop_back();
	return path;
}

// $inVariable when it is an absolute path, else $HOME/inHomeRelative; empty when neither is there
static std::string
XDGBaseDirectoryPath(const char *inVariable, const char *inHomeRelative)
{
	const char *value = getenv(inVariable);
	if( (value != nullptr) && (value[0] == '/') )
		return WithoutTrailingSlashes(value);

	const char *home = getenv("HOME");
	if( (home == nullptr) || (home[0] != '/') )
		return std::string();
	std::string homePath = WithoutTrailingSlashes(home);
	if(homePath == "/")
		return homePath + inHomeRelative;
	return homePath + "/" + inHomeRelative;
}

// Makes the folder and the missing folders above it, each with mode 0700. True when it is a folder afterwards.
static bool
MakeFolderWithParents(const std::string &inPath)
{
	for(std::string::size_type slash = inPath.find('/', 1); ; slash = inPath.find('/', slash + 1))
	{
		std::string partial = inPath.substr(0, slash);
		if( !partial.empty() && (mkdir(partial.c_str(), S_IRWXU) != 0) && (errno != EEXIST) )
			return false;
		if(slash == std::string::npos)
			break;
	}
	struct stat folderInfo;
	return (stat(inPath.c_str(), &folderInfo) == 0) && S_ISDIR(folderInfo.st_mode);
}

static CFURLRef
CreateFolderURL(const std::string &inPath)
{
	if(inPath.empty())
		return nullptr;
	return ::CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)inPath.c_str(), (CFIndex)inPath.size(), true /*isDirectory*/);
}

CFURLRef OMCCopyPreferencesDirURL(void)
{
	return CreateFolderURL( XDGBaseDirectoryPath("XDG_CONFIG_HOME", ".config") );
}

CFURLRef OMCCopyApplicationSupportDirURL(void)
{
	std::string path = XDGBaseDirectoryPath("XDG_DATA_HOME", ".local/share");
	if( path.empty() || !MakeFolderWithParents(path) )
		return nullptr;
	return CreateFolderURL(path);
}
