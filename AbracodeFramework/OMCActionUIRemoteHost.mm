//
//  OMCActionUIRemoteHost.mm
//  Abracode
//
//  See the header for what this owns and why its lifetime is shaped the way it is.
//

#import "OMCActionUIRemoteHost.h"

#include "DebugSettings.h"
#include "OMCEngineTempDir.h"

#include <stdlib.h>
#include <unistd.h>

// The server, its process-wide lifecycle and the ACTIONUI_REMOTE_ENDPOINT export all live here.
// @import rather than a hand-written extern "C" block (the pattern the optional add-ons use a few
// files over): ActionUIRemote emits a generated header for its @_cdecl entry points, and taking
// the declarations from it means a signature change is a compile error here rather than undefined
// behavior at run time.
@import ActionUIRemote;

NSString * const kOMCActionUIRemoteEndpointVariable = @"OMC_ACTIONUI_REMOTE_ENDPOINT";

// sun_path holds 104 bytes on Darwin, one of which is the terminator. Checked here rather than
// left to bind(2) so the log line names the real problem instead of reporting EINVAL.
static const size_t kMaxUnixSocketPathLength = 103;

@implementation OMCActionUIRemoteHost
{
    BOOL mStartAttempted;
    NSString *mEndpoint;
}

+ (instancetype)shared
{
    static OMCActionUIRemoteHost *sShared = nil;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        sShared = [[OMCActionUIRemoteHost alloc] init];
    });
    return sShared;
}

- (NSString *)endpoint
{
    return mEndpoint;
}

// The applet's own name, so actionui.hello identifies the window's owner rather than saying
// "OMCApplet" for every applet built from the same engine binary.
- (NSString *)hostName
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *name = [mainBundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
    if(name.length == 0)
        name = [[[mainBundle bundlePath] lastPathComponent] stringByDeletingPathExtension];
    if(name.length == 0)
        name = @"OMC";
    return name;
}

// The engine version, taken from Abracode.framework's own Info.plist, where CFBundleVersion is
// substituted from OMC_BUNDLE_VERSION in Common/OmcVersion.xcconfig. A client asking what it is
// talking to wants the OMC version, not the applet's, which it already has from the name.
- (NSString *)hostVersion
{
    NSBundle *frameworkBundle = [NSBundle bundleForClass:[self class]];
    NSString *version = [frameworkBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if(version.length == 0)
        return @"0";
    return version;
}

- (void)ensureStarted
{
    if(mStartAttempted)
        return;
    mStartAttempted = YES;   // set before the work: one attempt per bind, success or failure

    char socketPath[PATH_MAX];
    char leafName[64];
    int leafLength = snprintf(leafName, sizeof(leafName), "aui-%d.sock", (int)getpid());
    if((leafLength < 0) || ((size_t)leafLength >= sizeof(leafName)))
    {
        NSLog(@"[OMCActionUIRemoteHost] could not build the socket file name; remote bridge not started");
        return;
    }

    if(!OMCGetEngineTempFilePath(leafName, true, socketPath, sizeof(socketPath)))
    {
        NSLog(@"[OMCActionUIRemoteHost] could not resolve the engine temp directory; remote bridge not started");
        return;
    }

    // Deliberately no second, /tmp-based location when this one is too long. OMCEngineTempDir.h
    // exists precisely because the shared /tmp/OMC directory was replaceable by any local user,
    // and a private path that does not fit is a better outcome than a reachable one that does.
    // OMCGetUserTempDir already falls back as far as is safe.
    size_t pathLength = strlen(socketPath);
    if(pathLength > kMaxUnixSocketPathLength)
    {
        NSLog(@"[OMCActionUIRemoteHost] socket path is %zu bytes, over the %zu the platform allows: '%s'; remote bridge not started",
              pathLength, kMaxUnixSocketPathLength, socketPath);
        return;
    }

    NSString *hostName = [self hostName];
    NSString *hostVersion = [self hostVersion];
    if(!actionUIRemoteStartServer(socketPath, [hostName UTF8String], [hostVersion UTF8String]))
    {
        // ActionUIRemote has already logged the reason through the engine's logger.
        NSLog(@"[OMCActionUIRemoteHost] remote bridge did not start on '%s'", socketPath);
        return;
    }

    const char *boundPath = actionUIRemoteServerEndpoint();
    if(boundPath == NULL)
    {
        NSLog(@"[OMCActionUIRemoteHost] remote bridge started but reported no endpoint; stopping it");
        actionUIRemoteStopServer();
        return;
    }

    mEndpoint = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:boundPath
                                                                            length:strlen(boundPath)];
    if(mEndpoint == nil)
    {
        NSLog(@"[OMCActionUIRemoteHost] could not represent the socket path as a string; stopping the bridge");
        actionUIRemoteStopServer();
        return;
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
    setenv([kOMCActionUIRemoteEndpointVariable UTF8String], boundPath, 1);

    TRACE_CSTR("OMCActionUIRemoteHost: remote bridge listening\n");
}

- (void)stop
{
    if(mEndpoint == nil)
        return;

    actionUIRemoteStopServer();   // closes connections, unlinks the socket, unsets ACTIONUI_REMOTE_ENDPOINT
    unsetenv([kOMCActionUIRemoteEndpointVariable UTF8String]);
    mEndpoint = nil;

    // Startable again. Nothing in OMC calls -stop before termination, but actionUIRemoteStopServer
    // is public C API that any other user of ActionUIRemote in this process may call, and leaving
    // the one-shot latched would make that permanent: no later window could restart the bridge,
    // while the OMC_-prefixed variable stayed in environ pointing at a socket that is gone.
    mStartAttempted = NO;
}

@end

extern "C" const char *OMCGetActionUIRemoteEndpoint(void)
{
    return actionUIRemoteServerEndpoint();
}
