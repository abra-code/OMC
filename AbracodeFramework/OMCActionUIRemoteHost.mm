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
static const NSUInteger kMaxLiveTokenLabels = 256;

// One entry per grant, in mint order. Main thread only, like the rest of this class:
// -ensureStarted and the command execution that reaches here are both main-thread events.
static NSMutableArray<NSString *> *sMintedLabels = nil;

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

    // Stopping drops every grant with the server, so the mint-order bookkeeping goes too. Left
    // behind, it would name tokens that no longer exist, and a restarted bridge would spend its
    // first 256 mints evicting them before bounding anything real.
    [sMintedLabels removeAllObjects];

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

extern "C" bool OMCMintActionUIRemoteToken(const char *inLabel, char *outToken, size_t inTokenSize)
{
    if((inLabel == NULL) || (inLabel[0] == 0) || (outToken == NULL))
        return false;

    // Minting lives in ActionUIRemote so that one CSPRNG and one encoding serve every host, and
    // so that the value is registered with the server in the same step - a token this process
    // holds but the server does not know is worse than no token at all.
    if(!actionUIRemoteMintToken(inLabel, outToken, inTokenSize))
        return false;

    NSString *label = [NSString stringWithUTF8String:inLabel];
    if(label != nil)
    {
        if(sMintedLabels == nil)
            sMintedLabels = [[NSMutableArray alloc] init];

        // One entry per grant, not per label: a command that spawns several processes mints
        // several, and each must count against the bound.
        [sMintedLabels addObject:label];
        while([sMintedLabels count] > kMaxLiveTokenLabels)
        {
            NSString *oldest = [sMintedLabels objectAtIndex:0];
            [sMintedLabels removeObjectAtIndex:0];
            // Revocation is BY LABEL and takes every grant carrying it, so the oldest entry may
            // not be withdrawn while newer siblings share its label - a command that spawns
            // several processes mints several under its one GUID, and in the extreme a caller
            // reusing one label would have this withdraw the token it was handed a moment ago.
            // Withdraw only when the last grant under that label has aged out.
            if(![sMintedLabels containsObject:oldest])
                actionUIRemoteRevokeTokensWithLabel([oldest UTF8String]);
        }
    }
    return true;
}

extern "C" void OMCRevokeActionUIRemoteTokens(const char *inLabel)
{
    if((inLabel == NULL) || (inLabel[0] == 0))
        return;
    actionUIRemoteRevokeTokensWithLabel(inLabel);
}
