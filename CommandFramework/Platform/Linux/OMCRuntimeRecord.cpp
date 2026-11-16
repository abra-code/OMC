//
//  OMCRuntimeRecord.cpp (Linux)
//  Command
//
//  See OMCRuntimeRecord.h. The records folder is writable by every user, so the file is opened
//  without following a symbolic link and used only when it is a plain file this user owns with no
//  other name (another user may have planted a link or a file under this user's name: then nothing
//  is written, and the cleanup keeps every runtime while that file is there). Appending one short line
//  with O_APPEND is a single write, so two launches at once can at worst add the same line twice,
//  which the cleanup does not mind. No lock: another user can open the file for reading and hold a
//  lock on it.
//

#include "Linux/OMCRuntimeRecord.h"
#include "OMCTestHost.h"
#include "OMCLog.h"
#include "CFObj.h"
#include <CoreFoundation/CoreFoundation.h>
#include <link.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <string>

namespace
{

const char *kRecordsFolder = "/var/lib/command-engine/applets";
const char *kRuntimesFolder = "/usr/lib/command-engine/";
const char *kSwiftCoreName = "libswiftCore.so";

// A records file this large is not read (it would only grow by a launch from a new place)
const off_t kMaxRecordsSize = 1024 * 1024;

int
FindSwiftCore(struct dl_phdr_info *inInfo, size_t inSize, void *outPath)
{
	(void)inSize;
	const char *name = inInfo->dlpi_name;
	if((name == nullptr) || (name[0] != '/'))
		return 0;
	const char *slash = strrchr(name, '/');
	if(strcmp(slash + 1, kSwiftCoreName) != 0)
		return 0;
	*(std::string *)outPath = name;
	return 1;
}

// "swift-6.4" when libswiftCore.so was loaded from /usr/lib/command-engine/swift-6.4/, else empty
std::string
RuntimeLine()
{
	std::string swiftCore;
	dl_iterate_phdr(FindSwiftCore, &swiftCore);
	size_t prefixLength = strlen(kRuntimesFolder);
	if((swiftCore.size() <= prefixLength) || (swiftCore.compare(0, prefixLength, kRuntimesFolder) != 0))
		return std::string();
	std::string line = swiftCore.substr(prefixLength);
	size_t slash = line.find('/');
	if((slash == std::string::npos) || (line.compare(slash + 1, std::string::npos, kSwiftCoreName) != 0))
		return std::string();
	line.resize(slash);
	// As the packages name it: swift-<minor> or swift-<minor>.<patch>
	if((line.size() <= 6) || (line.compare(0, 6, "swift-") != 0) || (line.find_first_not_of("0123456789.", 6) != std::string::npos))
		return std::string();
	return line;
}

// The applet bundle's path, or empty
std::string
BundlePath()
{
	CFBundleRef bundle = CFBundleGetMainBundle();
	if(bundle == nullptr)
		return std::string();
	CFObj<CFURLRef> bundleURL(CFBundleCopyBundleURL(bundle));
	if(bundleURL == nullptr)
		return std::string();
	char path[4096];
	if(!CFURLGetFileSystemRepresentation(bundleURL, true, (UInt8 *)path, sizeof(path)))
		return std::string();
	return std::string(path);
}

// Whether the open file holds inRecord as a whole line
bool
HasRecord(int inFile, off_t inSize, const std::string &inRecord)
{
	std::string contents((size_t)inSize, '\0');
	off_t done = 0;
	while(done < inSize)
	{
		ssize_t count = pread(inFile, &contents[(size_t)done], (size_t)(inSize - done), done);
		if(count < 0)
		{
			if(errno == EINTR)
				continue;
			return false;
		}
		if(count == 0)
			break;
		done += count;
	}
	contents.resize((size_t)done);
	// inRecord ends with its newline: a match at the start or after a newline is a whole line
	for(size_t at = contents.find(inRecord); at != std::string::npos; at = contents.find(inRecord, at + 1))
	{
		if((at == 0) || (contents[at - 1] == '\n'))
			return true;
	}
	return false;
}

} // namespace

void
OMCRecordRuntimeUse()
{
	if(OMCTestHostIsActive())
		return;
	std::string line = RuntimeLine();
	if(line.empty())
		return; // the toolchain's runtime (a development build), not a command-engine package's
	std::string bundlePath = BundlePath();
	// A tab or newline in the path would break the line format: such an applet is not recorded
	if(bundlePath.empty() || (bundlePath[0] != '/') || (bundlePath.find_first_of("\t\n") != std::string::npos))
		return;
	std::string record = line + "\t" + bundlePath + "\n";
	uid_t user = getuid();
	std::string path = std::string(kRecordsFolder) + "/" + std::to_string((unsigned long)user) + ".list";
	int file = open(path.c_str(), O_RDWR | O_CREAT | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0644);
	if(file < 0)
	{
		// No folder: no command-engine package (or an older one); nothing to say
		if(errno != ENOENT)
			OMCLogMessage("Cannot open %s to record the Swift runtime this applet uses: %s", path.c_str(), strerror(errno));
		return;
	}
	struct stat info;
	if((fstat(file, &info) != 0) || !S_ISREG(info.st_mode) || (info.st_uid != user) || (info.st_nlink != 1))
	{
		OMCLogMessage("%s is not this user's own plain file: the Swift runtime this applet uses is not recorded", path.c_str());
		close(file);
		return;
	}
	if(info.st_size > kMaxRecordsSize)
	{
		OMCLogMessage("%s is over %ld bytes: the Swift runtime this applet uses is not recorded", path.c_str(), (long)kMaxRecordsSize);
		close(file);
		return;
	}
	if(!HasRecord(file, info.st_size, record))
	{
		ssize_t written = write(file, record.data(), record.size());
		if(written != (ssize_t)record.size())
			OMCLogMessage("Cannot add to %s: %s", path.c_str(), (written < 0) ? strerror(errno) : "short write");
	}
	close(file);
}
