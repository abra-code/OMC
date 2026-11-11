//
//  OMCLinuxPortTests/main.cpp
//  Abracode
//
//  Linux checks of omc_dialog_control's port: the engine's listener (Platform/Linux/
//  OMCMessagePortListener.cpp) and the real omc_dialog_control tool sending to it
//  (Common/Linux/OMCDialogControlSender.c), with the cases of the probe
//  ~/git/AppleCoreLibrariesForLinux/build/probe/dialog-control-socket/REPORT.md; and the Linux
//  half of ACFPropertyList's atomic write (Common/Linux/OMCFileModePlatform.h).
//
//  Usage: OMCLinuxPortTests <path to the Linux omc_dialog_control>
//  Exit status: 0 all passed, 1 a check failed, 2 bad arguments.
//

#include "OMCMessagePortListener.h"
#include "OMCDialogControlPortName.h"
#include "OMCEngineTempDir.h"
#include "CFObj.h"
#include "ACFPropertyList.h"
#include <glib.h>
#include <fcntl.h>
#include <ftw.h>
#include <spawn.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <memory>
#include <string>
#include <vector>

extern char **environ;

namespace
{

const char *sTool = nullptr;
int sPassed = 0;
int sFailed = 0;

void
Check(const char *inName, bool inOK, const std::string &inDetail = std::string())
{
	if(inOK)
	{
		sPassed++;
		printf("ok   %s\n", inName);
	}
	else
	{
		sFailed++;
		printf("FAIL %s%s%s\n", inName, inDetail.empty() ? "" : ": ", inDetail.c_str());
	}
	fflush(stdout);
}

// Removes a folder and what is in it, without following symbolic links
int
RemoveEntry(const char *inPath, const struct stat *, int, struct FTW *)
{
	return remove(inPath);
}

void
RemoveTree(const std::string &inPath)
{
	(void)nftw(inPath.c_str(), RemoveEntry, 16, FTW_DEPTH | FTW_PHYS);
}

std::string
NewUUID()
{
	CFObj<CFUUIDRef> uuid( CFUUIDCreate(kCFAllocatorDefault) );
	CFObj<CFStringRef> text( CFUUIDCreateString(kCFAllocatorDefault, uuid) );
	char buffer[64] = {};
	CFStringGetCString(text, buffer, sizeof(buffer), kCFStringEncodingUTF8);
	return buffer;
}

std::string
CString(CFStringRef inString)
{
	if(inString == nullptr)
		return std::string();
	char buffer[1024] = {};
	CFStringGetCString(inString, buffer, sizeof(buffer), kCFStringEncodingUTF8);
	return buffer;
}

// What a dialog got: each message's VALUES as "<control>=<value>" (omc_dialog_control <uuid> <control> <value>)
struct Inbox
{
	std::vector<std::string>							values;
	std::function<void()>								afterReceive;
};

void
Receive(void *inContext, CFDataRef inMessage)
{
	Inbox *inbox = static_cast<Inbox *>(inContext);
	CFObj<CFPropertyListRef> plist( CFPropertyListCreateWithData(kCFAllocatorDefault, inMessage, kCFPropertyListImmutable, nullptr, nullptr) );
	std::string entry = "(not a dictionary)";
	if( (plist != nullptr) && (CFGetTypeID(plist) == CFDictionaryGetTypeID()) )
	{
		CFTypeRef values = CFDictionaryGetValue((CFDictionaryRef)plist.Get(), CFSTR("VALUES"));
		entry = "(no VALUES)";
		if( (values != nullptr) && (CFGetTypeID(values) == CFDictionaryGetTypeID()) && (CFDictionaryGetCount((CFDictionaryRef)values) == 1) )
		{
			const void *key = nullptr;
			const void *value = nullptr;
			CFDictionaryGetKeysAndValues((CFDictionaryRef)values, &key, &value);
			if( (CFGetTypeID(key) == CFStringGetTypeID()) && (CFGetTypeID(value) == CFStringGetTypeID()) )
				entry = CString((CFStringRef)key) + "=" + CString((CFStringRef)value);
		}
	}
	inbox->values.push_back(entry);
	if(inbox->afterReceive)
		inbox->afterReceive();
}

pid_t
SpawnTool(const std::string &inUUID, const char *inControl, const char *inValue)
{
	std::string uuid = inUUID;
	char *argv[] = { const_cast<char *>(sTool), const_cast<char *>(uuid.c_str()), const_cast<char *>(inControl), const_cast<char *>(inValue), nullptr };
	pid_t pid = 0;
	if(posix_spawn(&pid, sTool, nullptr, nullptr, argv, environ) != 0)
		return -1;
	return pid;
}

int
WaitTool(pid_t inPID)
{
	int status = 0;
	if( (inPID <= 0) || (waitpid(inPID, &status, 0) != inPID) )
		return -1;
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

int
RunTool(const std::string &inUUID, const char *inControl, const char *inValue)
{
	return WaitTool(SpawnTool(inUUID, inControl, inValue));
}

// Runs the main loop until inDone says so or inTimeoutMs passes; returns inDone()
bool
PumpUntil(const std::function<bool()> &inDone, int inTimeoutMs)
{
	auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(inTimeoutMs);
	while( !inDone() && (std::chrono::steady_clock::now() < end) )
	{
		if( !g_main_context_iteration(nullptr, FALSE) )
			g_usleep(1000);
	}
	return inDone();
}

std::unique_ptr<OMCMessagePortListener>
Listen(const std::string &inUUID, Inbox &inInbox)
{
	CFObj<CFStringRef> portName( OMCCreateDialogControlPortName(inUUID.c_str(), true /*listener*/) );
	return OMCMessagePortListener::Create(portName, Receive, &inInbox);
}

std::string
SocketPath(const std::string &inUUID)
{
	CFObj<CFStringRef> portName( OMCCreateDialogControlPortName(inUUID.c_str(), false) );
	return CString(portName);
}

bool
Exists(const std::string &inPath)
{
	struct stat info;
	return (lstat(inPath.c_str(), &info) == 0);
}

std::string
Joined(const std::vector<std::string> &inValues)
{
	std::string text;
	for(const std::string &value : inValues)
		text += (text.empty() ? "" : ",") + value;
	return text;
}

} // namespace

int
main(int argc, char **argv)
{
	if(argc != 2)
	{
		fprintf(stderr, "usage: OMCLinuxPortTests <path to omc_dialog_control>\n");
		return 2;
	}
	sTool = argv[1];

	{
		Inbox inbox;
		std::string uuid = NewUUID();
		std::unique_ptr<OMCMessagePortListener> listener = Listen(uuid, inbox);
		Check("a dialog's port is made", listener != nullptr);
		Check("as a socket in the private folder", Exists(SocketPath(uuid)), SocketPath(uuid));
		Check("omc_dialog_control sends to it", RunTool(uuid, "4", "hello") == 0);
		PumpUntil([&]{ return inbox.values.size() >= 1; }, 3000);
		Check("the message arrives through the main loop", Joined(inbox.values) == "4=hello", Joined(inbox.values));

		inbox.values.clear();
		std::string expected;
		for(int i = 0; i < 20; i++)
		{
			std::string value = "v" + std::to_string(i);
			(void)RunTool(uuid, "5", value.c_str());
			expected += (expected.empty() ? "" : ",") + std::string("5=") + value;
		}
		PumpUntil([&]{ return inbox.values.size() >= 20; }, 5000);
		Check("twenty senders one after another arrive in order", Joined(inbox.values) == expected, Joined(inbox.values));

		inbox.values.clear();
		std::vector<pid_t> senders;
		for(int i = 0; i < 16; i++)
			senders.push_back(SpawnTool(uuid, "6", "x"));
		PumpUntil([&]{ return inbox.values.size() >= 16; }, 5000);
		for(pid_t pid : senders)
			(void)WaitTool(pid);
		Check("sixteen senders at once all arrive", inbox.values.size() == 16, std::to_string(inbox.values.size()));

		inbox.values.clear();
		pid_t pid = SpawnTool(uuid, "7", "queued");
		int status = WaitTool(pid); // the main loop does not run meanwhile, as in a blocking wait
		Check("a sender finishes while the main thread is busy", status == 0);
		Check("and nothing is delivered before the port is serviced", inbox.values.empty());
		listener->ServicePending();
		Check("ServicePending delivers what is waiting", Joined(inbox.values) == "7=queued", Joined(inbox.values));

		std::string socketPath = SocketPath(uuid);
		listener.reset();
		Check("a closed port's socket file is removed", !Exists(socketPath));
		Check("then omc_dialog_control still succeeds", RunTool(uuid, "8", "late") == 0);
		char filePath[PATH_MAX] = {};
		std::string leaf = uuid + ".plist";
		bool havePath = OMCGetEngineTempFilePath(leaf.c_str(), false, filePath, sizeof(filePath));
		Check("writing the message file instead", havePath && Exists(filePath), filePath);
		if(havePath)
			(void)unlink(filePath);
	}

	{
		Inbox inbox;
		std::string uuid = NewUUID();
		CFObj<CFStringRef> portName( OMCCreateDialogControlPortName(uuid.c_str(), true) );
		std::string socketPath = CString(portName);
		FILE *stale = fopen(socketPath.c_str(), "w");
		if(stale != nullptr)
			fclose(stale);
		std::unique_ptr<OMCMessagePortListener> listener = OMCMessagePortListener::Create(portName, Receive, &inbox);
		Check("a file left at the socket's path does not stop the port", listener != nullptr);
		(void)RunTool(uuid, "1", "after-stale");
		PumpUntil([&]{ return inbox.values.size() >= 1; }, 3000);
		Check("and messages arrive", Joined(inbox.values) == "1=after-stale", Joined(inbox.values));
	}

	{
		Inbox inbox;
		std::string uuid = NewUUID();
		std::unique_ptr<OMCMessagePortListener> listener = Listen(uuid, inbox);
		inbox.afterReceive = [&]{ listener.reset(); }; // the dialog closes on its first message
		for(int i = 0; i < 3; i++)
			(void)RunTool(uuid, "2", ("m" + std::to_string(i)).c_str());
		PumpUntil([&]{ return listener == nullptr; }, 3000);
		for(int i = 0; i < 50; i++)
			(void)g_main_context_iteration(nullptr, FALSE);
		Check("a dialog closed by its own message gets no more", Joined(inbox.values) == "2=m0", Joined(inbox.values));
	}

	{
		// A message larger than the socket's buffer, from stdin, to a dialog whose main thread is busy: the
		// tool blocks writing it; the dialog closes meanwhile. The tool must fail with an error, not die of
		// SIGPIPE (a script would see a signal instead of omc_dialog_control's message).
		Inbox inbox;
		std::string uuid = NewUUID();
		std::unique_ptr<OMCMessagePortListener> listener = Listen(uuid, inbox);
		std::string bigFile = std::string(g_get_tmp_dir()) + "/omc-port-test-big-" + std::to_string(getpid());
		FILE *big = fopen(bigFile.c_str(), "w");
		if(big != nullptr)
		{
			std::string chunk(1024 * 1024, 'a');
			for(int i = 0; i < 4; i++)
				fwrite(chunk.data(), 1, chunk.size(), big);
			fclose(big);
		}
		posix_spawn_file_actions_t actions;
		posix_spawn_file_actions_init(&actions);
		posix_spawn_file_actions_addopen(&actions, 0, bigFile.c_str(), O_RDONLY, 0);
		std::string uuidArg = uuid;
		char *toolArgv[] = { const_cast<char *>(sTool), const_cast<char *>(uuidArg.c_str()), const_cast<char *>("9"), const_cast<char *>("omc_set_value_from_stdin"), nullptr };
		pid_t pid = 0;
		int spawned = posix_spawn(&pid, sTool, &actions, nullptr, toolArgv, environ);
		posix_spawn_file_actions_destroy(&actions);
		g_usleep(500 * 1000); // the tool fills the socket's buffer and blocks
		listener.reset();
		int status = 0;
		bool waited = (spawned == 0) && (waitpid(pid, &status, 0) == pid);
		(void)unlink(bigFile.c_str());
		std::string detail = !waited ? "not run" : WIFSIGNALED(status) ? ("signal " + std::to_string(WTERMSIG(status))) : ("exit " + std::to_string(WEXITSTATUS(status)));
		Check("a sender cut off by a closing dialog exits, not killed by a signal", waited && WIFEXITED(status), detail);
		Check("and reports the failure", waited && WIFEXITED(status) && (WEXITSTATUS(status) != 0), detail);
		Check("and the dialog got nothing", inbox.values.empty(), Joined(inbox.values));
	}

	{
		// No $XDG_RUNTIME_DIR, and a cache folder whose path leaves no room in sun_path's 107 bytes. In
		// the home folder: the engine refuses a private folder on a path others can write to, like /tmp.
		std::string longCache = std::string(g_get_home_dir()) + "/.omc-port-test-" + std::to_string(getpid()) + "/" + std::string(80, 'c');
		g_mkdir_with_parents(longCache.c_str(), 0700);
		unsetenv("XDG_RUNTIME_DIR");
		setenv("XDG_CACHE_HOME", longCache.c_str(), 1);
		Inbox inbox;
		std::string uuid = NewUUID();
		std::unique_ptr<OMCMessagePortListener> listener = Listen(uuid, inbox);
		std::string socketPath = SocketPath(uuid);
		Check("the socket's path is longer than sun_path holds", socketPath.size() > 107, std::to_string(socketPath.size()));
		Check("and the port is made anyway", listener != nullptr);
		(void)RunTool(uuid, "3", "long");
		PumpUntil([&]{ return inbox.values.size() >= 1; }, 3000);
		Check("and omc_dialog_control reaches it", Joined(inbox.values) == "3=long", Joined(inbox.values));
	}

	{
		// ACFPropertyList's atomic write through a symbolic link: on Linux a link's own mode is 0777,
		// which must not become the new file's; the target's read and write bits do, never looser
		// than 0666 less the umask (Common/Linux/OMCFileModePlatform.h)
		std::string folder = std::string(g_get_home_dir()) + "/.omc-port-test-" + std::to_string(getpid()) + "/write";
		g_mkdir_with_parents(folder.c_str(), 0700);
		auto MakeFile = [](const std::string &inPath, mode_t inMode) {
			int fd = open(inPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
			if(fd >= 0)
				(void)close(fd);
			(void)chmod(inPath.c_str(), inMode);
		};
		auto ModeOf = [](const std::string &inPath, struct stat &outInfo) -> std::string {
			if(lstat(inPath.c_str(), &outInfo) != 0)
				return "missing";
			char mode[16];
			snprintf(mode, sizeof(mode), "%o", (unsigned)(outInfo.st_mode & 07777));
			return mode;
		};
		std::string privateTarget = folder + "/private.plist";	// 0600: a link to it gives a private file
		std::string openTarget = folder + "/open.plist";		// 0666: a link to it gives 0644 under umask 022
		std::string privateLink = folder + "/private-link.plist";
		std::string openLink = folder + "/open-link.plist";
		std::string danglingLink = folder + "/dangling-link.plist";
		std::string kept = folder + "/kept.plist";
		MakeFile(privateTarget, 0600);
		MakeFile(openTarget, 0666);
		MakeFile(kept, 0640);
		(void)symlink(privateTarget.c_str(), privateLink.c_str());
		(void)symlink(openTarget.c_str(), openLink.c_str());
		(void)symlink((folder + "/nothing.plist").c_str(), danglingLink.c_str());

		mode_t oldMask = umask(022);
		CFObj<CFMutableDictionaryRef> plist(CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks));
		CFDictionarySetValue(plist, CFSTR("key"), CFSTR("value"));
		auto WriteTo = [&](const std::string &inPath) {
			CFObj<CFURLRef> url(CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)inPath.c_str(), (CFIndex)inPath.size(), false));
			return WritePropertyList(plist, url, kACFPropertyListFormat_xml);
		};
		bool wrotePrivate = WriteTo(privateLink);
		bool wroteOpen = WriteTo(openLink);
		bool wroteDangling = WriteTo(danglingLink);
		bool wroteKept = WriteTo(kept);
		(void)umask(oldMask);

		struct stat info;
		std::string mode = ModeOf(privateLink, info);
		Check("an atomic write through a symbolic link succeeds", wrotePrivate);
		Check("and replaces the link with a file", (mode != "missing") && S_ISREG(info.st_mode));
		Check("a link to a 0600 file gives a 0600 file, not the link's 0777", mode == "600", mode);
		mode = ModeOf(privateTarget, info);
		Check("and the link's target is left alone", (mode == "600") && (info.st_size == 0), mode);
		mode = ModeOf(openLink, info);
		Check("a link to a 0666 file gives no more than 0666 less the umask", wroteOpen && (mode == "644"), mode);
		mode = ModeOf(danglingLink, info);
		Check("a dangling link gives 0666 less the umask", wroteDangling && (mode == "644") && S_ISREG(info.st_mode), mode);
		mode = ModeOf(kept, info);
		Check("an existing file keeps its mode", wroteKept && (mode == "640"), mode);
	}

	// The folder the last two blocks made in the home folder
	RemoveTree(std::string(g_get_home_dir()) + "/.omc-port-test-" + std::to_string(getpid()));

	printf("%d passed, %d failed\n", sPassed, sFailed);
	return (sFailed == 0) ? 0 : 1;
}
