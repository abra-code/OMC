//
//  OMCActionUIRemoteHost.cpp
//  Abracode
//
//  See the header for what this owns and why its lifetime is shaped the way it is. Portable C++.
//

#include "OMCActionUIRemoteHost.h"

#include "CFObj.h"
#include "DebugSettings.h"
#include "OMCEngineTempDir.h"
#include "OMCLog.h"

#include <CoreFoundation/CoreFoundation.h>
#include <algorithm>
#include <deque>
#include <limits.h>
#include <stdlib.h>
#include <string>
#include <string.h>
#include <sys/un.h>
#include <unistd.h>

// The server, its process-wide lifecycle and the ACTIONUI_REMOTE_ENDPOINT export all live here.
// ActionUIRemote's generated header declares its @c entry points for plain C and C++, and taking
// the declarations from it, rather than from a hand-written extern "C" block (the pattern the
// optional add-ons use), means a signature change is a compile error here rather than undefined
// behavior at run time.
#include "ActionUIRemote-Swift.h"

extern CFStringRef kBundleIDString; // OnMyCommand.cp: Abracode.framework's bundle identifier

static const char kOMCActionUIRemoteEndpointVariable[] = "OMC_ACTIONUI_REMOTE_ENDPOINT";

// sun_path holds 104 bytes on Darwin (108 on Linux), one of which is the terminator. Checked here
// rather than left to bind(2) so the log line names the real problem instead of reporting EINVAL.
static const size_t kMaxUnixSocketPathLength = sizeof(((struct sockaddr_un *)nullptr)->sun_path) - 1;

// How many grants may be live at once before the oldest are withdrawn.
//
// The policy is deliberately loose - a grant outlives the handler it was minted for, because a
// handler can background work that still needs the bridge and nothing knows when a command's
// descendants have finished (see the commit note). Loose must not mean unbounded, though: one
// grant per spawned process, never withdrawn, is a slow leak in an applet that stays up, and an
// applet running a command on a timer would accumulate tens of thousands a day. This bounds it.
//
// 256 is far more concurrent handlers than an applet has, so in practice nothing is ever
// withdrawn early; an applet that does reach it has run 256 commands since the oldest, by which
// point a handler still holding that grant is not a case worth keeping alive.
static const size_t kMaxLiveTokenLabels = 256;

// The process's one host. Main thread only: the window creation and command execution that reach
// here are main-thread events.
static bool sStartAttempted = false;
static bool sRunning = false; // bound and published by this host

// One entry per grant, in mint order. Never freed, as the Objective-C host's array was not: no
// destructor runs at exit under a mint or a stop that comes late.
static std::deque<std::string> &MintedLabels()
{
	static std::deque<std::string> *sMintedLabels = new std::deque<std::string>();
	return *sMintedLabels;
}

// A CFString as UTF-8, or an empty string when there is none or it does not convert
static std::string
CopyUTF8(CFStringRef inString)
{
	if(inString == nullptr)
		return std::string();
	CFIndex maxSize = CFStringGetMaximumSizeForEncoding(CFStringGetLength(inString), kCFStringEncodingUTF8) + 1;
	std::string buffer((size_t)maxSize, '\0');
	if(!CFStringGetCString(inString, &buffer[0], maxSize, kCFStringEncodingUTF8))
		return std::string();
	buffer.resize(strlen(buffer.c_str()));
	return buffer;
}

// The applet's own name, so actionui.hello identifies the window's owner rather than saying
// "OMCApplet" for every applet built from the same engine binary.
static std::string
CopyHostName()
{
	CFBundleRef mainBundle = CFBundleGetMainBundle();
	if(mainBundle != nullptr)
	{
		CFTypeRef nameValue = CFBundleGetValueForInfoDictionaryKey(mainBundle, kCFBundleNameKey);
		if((nameValue != nullptr) && (CFGetTypeID(nameValue) == CFStringGetTypeID()))
		{
			std::string name = CopyUTF8((CFStringRef)nameValue);
			if(!name.empty())
				return name;
		}

		CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL(mainBundle) );
		if(bundleURL != nullptr)
		{
			CFObj<CFURLRef> withoutExtension( CFURLCreateCopyDeletingPathExtension(kCFAllocatorDefault, bundleURL) );
			if(withoutExtension != nullptr)
			{
				CFObj<CFStringRef> leafName( CFURLCopyLastPathComponent(withoutExtension) );
				std::string name = CopyUTF8(leafName);
				if(!name.empty())
					return name;
			}
		}
	}
	return "OMC";
}

// The engine version, taken from Abracode.framework's own Info.plist, where CFBundleVersion is
// substituted from OMC_BUNDLE_VERSION in Common/OmcVersion.xcconfig. A client asking what it is
// talking to wants the OMC version, not the applet's, which it already has from the name.
static std::string
CopyHostVersion()
{
	CFBundleRef frameworkBundle = CFBundleGetBundleWithIdentifier(kBundleIDString);
	if(frameworkBundle != nullptr)
	{
		CFTypeRef versionValue = CFBundleGetValueForInfoDictionaryKey(frameworkBundle, kCFBundleVersionKey);
		if((versionValue != nullptr) && (CFGetTypeID(versionValue) == CFStringGetTypeID()))
		{
			std::string version = CopyUTF8((CFStringRef)versionValue);
			if(!version.empty())
				return version;
		}
	}
	return "0";
}

// The bind and everything that goes with it, for both callers: OMCEnsureActionUIRemoteBridgeStarted,
// which picks the engine's own path, and OMCStartActionUIRemoteBridgeAtPath, which a test launch
// gives one.
static bool
StartAtSocketPath(const char *socketPath)
{
	// Deliberately no second, /tmp-based location when this one is too long. OMCEngineTempDir.h
	// exists precisely because the shared /tmp/OMC directory was replaceable by any local user,
	// and a private path that does not fit is a better outcome than a reachable one that does.
	// OMCGetUserTempDir already falls back as far as is safe.
	size_t pathLength = strlen(socketPath);
	if(pathLength > kMaxUnixSocketPathLength)
	{
		OMCLogMessage("[OMCActionUIRemoteHost] socket path is %zu bytes, over the %zu the platform allows: '%s'; remote bridge not started",
					  pathLength, kMaxUnixSocketPathLength, socketPath);
		return false;
	}

	std::string hostName = CopyHostName();
	std::string hostVersion = CopyHostVersion();
	if(!actionUIRemoteStartServer(socketPath, hostName.c_str(), hostVersion.c_str()))
	{
		// ActionUIRemote has already logged the reason through the engine's logger.
		OMCLogMessage("[OMCActionUIRemoteHost] remote bridge did not start on '%s'", socketPath);
		return false;
	}

	// The token ActionUIRemote minted and exported must not stay in this process's environment:
	// CreateEnviron (omc_popen.c) builds every handler's environment by copying ours, so a
	// variable here is a variable in every child - and a python3 or node child shows its
	// environment to any same-uid `ps`, having no CS_RESTRICT. Done here, before any command can
	// run, so no handler ever inherits it. Each handler gets its own token on a descriptor
	// instead; see OMCMintActionUIRemoteToken and omc_popen_with_token.
	//
	// The grant itself stays live and stays readable through actionUIRemoteServerToken(), which
	// is a snapshot taken at start; unexporting costs this process nothing.
	(void)actionUIRemoteUnexportToken();

	// And the descriptor's name, which this process has no business carrying: an applet launched
	// by another applet's handler inherits ACTIONUI_REMOTE_TOKEN_FD pointing at a descriptor
	// that means nothing here. Left in place it would reach every handler, and a client reads
	// that descriptor when it is imported - so it would consume bytes from whatever fd 3 happens
	// to be in this process. omc_popen_with_token sets the real one per spawn.
	unsetenv("ACTIONUI_REMOTE_TOKEN_FD");

	const char *boundPath = actionUIRemoteServerEndpoint();
	if(boundPath == nullptr)
	{
		OMCLogMessage("[OMCActionUIRemoteHost] remote bridge started but reported no endpoint; stopping it");
		actionUIRemoteStopServer();
		return false;
	}

	// ActionUIRemote set ACTIONUI_REMOTE_ENDPOINT itself; this is the OMC-prefixed alias, so both
	// spellings reach the three execution modes that build no environment dictionary at all.
	//
	// On the setenv/getenv race: unlike OMC_APP_PROCESS_ID's, this one is NOT early - it fires
	// when the first window opens, and by then ActionUIRemote's accept queue and the CFSocket
	// manager thread exist. What makes it safe is narrower and worth writing down. The framework
	// starts no threads of its own; the only code in OMC that walks environ is CreateEnviron
	// (omc_popen.c), which runs on this same thread; nothing in ActionUIRemote reads environ at
	// all; and both names are new, so no reader can be holding a getenv pointer into either.
	setenv(kOMCActionUIRemoteEndpointVariable, boundPath, 1);
	sRunning = true;

	TRACE_CSTR("OMCActionUIRemoteHost: remote bridge listening\n");
	return true;
}

extern "C" void OMCEnsureActionUIRemoteBridgeStarted(void)
{
	if(sStartAttempted)
		return;
	sStartAttempted = true; // set before the work: one attempt per bind, success or failure

	char socketPath[PATH_MAX];
	char leafName[64];
	int leafLength = snprintf(leafName, sizeof(leafName), "aui-%d.sock", (int)getpid());
	if((leafLength < 0) || ((size_t)leafLength >= sizeof(leafName)))
	{
		OMCLogMessage("[OMCActionUIRemoteHost] could not build the socket file name; remote bridge not started");
		return;
	}

	if(!OMCGetEngineTempFilePath(leafName, true, socketPath, sizeof(socketPath)))
	{
		OMCLogMessage("[OMCActionUIRemoteHost] could not resolve the engine temp directory; remote bridge not started");
		return;
	}

	(void)StartAtSocketPath(socketPath);
}

extern "C" void OMCStopActionUIRemoteBridge(void)
{
	if(!sRunning)
		return;

	actionUIRemoteStopServer(); // closes connections, unlinks the socket, unsets ACTIONUI_REMOTE_ENDPOINT
	unsetenv(kOMCActionUIRemoteEndpointVariable);
	sRunning = false;

	// Stopping drops every grant with the server, so the mint-order bookkeeping goes too. Left
	// behind, it would name tokens that no longer exist, and a restarted bridge would spend its
	// first 256 mints evicting them before bounding anything real.
	MintedLabels().clear();

	// Startable again. Nothing in OMC stops the bridge before termination, but
	// actionUIRemoteStopServer is public C API that any other user of ActionUIRemote in this
	// process may call, and leaving the one-shot latched would make that permanent: no later
	// window could restart the bridge, while the OMC_-prefixed variable stayed in environ pointing
	// at a socket that is gone.
	sStartAttempted = false;
}

// One bind per process, as for OMCEnsureActionUIRemoteBridgeStarted: a test launch binds before
// any window exists, so finding a bind already attempted means misuse, and the answer is no.
extern "C" bool OMCStartActionUIRemoteBridgeAtPath(const char *inSocketPath)
{
	if((inSocketPath == NULL) || (inSocketPath[0] == 0))
		return false;

	if(sStartAttempted)
		return false;
	sStartAttempted = true;
	return StartAtSocketPath(inSocketPath);
}

extern "C" bool OMCRegisterActionUIRemoteMethod(const char *inMethod, OMCActionUIRemoteMethod inCallback, void *inContext)
{
	if((inMethod == NULL) || (inCallback == NULL))
		return false;
	return actionUIRemoteRegisterMethod(inMethod, inCallback, inContext);
}

extern "C" bool OMCEnableActionUIRemotePerformAction(void)
{
	return actionUIRemoteEnablePerformAction();
}

extern "C" bool OMCAddActionUIRemoteToken(const char *inToken, const char *inLabel)
{
	return actionUIRemoteAddToken(inToken, inLabel);
}

extern "C" const char *OMCGetActionUIRemoteEndpoint(void)
{
	return actionUIRemoteServerEndpoint();
}

extern "C" bool OMCMintActionUIRemoteToken(const char *inLabel, char *outToken, size_t inTokenSize)
{
	if((inLabel == NULL) || (inLabel[0] == 0) || (outToken == NULL))
		return false;

	// Minting lives in ActionUIRemote so that one CSPRNG and one encoding serve every host, and
	// so that the value is registered with the server in the same step - a token this process
	// holds but the server does not know is worse than no token at all.
	if(!actionUIRemoteMintToken(inLabel, outToken, (ptrdiff_t)inTokenSize))
		return false;

	// One entry per grant, not per label: a command that spawns several processes mints
	// several, and each must count against the bound.
	std::deque<std::string> &mintedLabels = MintedLabels();
	mintedLabels.push_back(inLabel);
	while(mintedLabels.size() > kMaxLiveTokenLabels)
	{
		std::string oldest = mintedLabels.front();
		mintedLabels.pop_front();
		// Revocation is BY LABEL and takes every grant carrying it, so the oldest entry may
		// not be withdrawn while newer siblings share its label - a command that spawns
		// several processes mints several under its one GUID, and in the extreme a caller
		// reusing one label would have this withdraw the token it was handed a moment ago.
		// Withdraw only when the last grant under that label has aged out.
		if(std::find(mintedLabels.begin(), mintedLabels.end(), oldest) == mintedLabels.end())
			actionUIRemoteRevokeTokensWithLabel(oldest.c_str());
	}
	return true;
}

extern "C" void OMCRevokeActionUIRemoteTokens(const char *inLabel)
{
	if((inLabel == NULL) || (inLabel[0] == 0))
		return;
	actionUIRemoteRevokeTokensWithLabel(inLabel);
}
