#include "ACFURL.h"
#include <limits.h>
#include <unistd.h>

// Was NSFileManager removeItemAtURL:, which also removes folder trees. The only caller deletes a
// temporary file, so unlink(), which never removes a folder, is all that is needed and is safer.
bool DeleteFile(CFURLRef fileURL)
{
	if(fileURL == nullptr)
		return false;

	char path[PATH_MAX];
	if(!::CFURLGetFileSystemRepresentation(fileURL, true, (UInt8 *)path, sizeof(path)))
		return false;

	return (::unlink(path) == 0);
}
