//
//  OMCAppLifetimeEvents.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 10/25/25.
//

#import "OMCCommandExecutor.h"
#import "OMCActionUIRemoteHost.h"
#include "DebugSettings.h"
#include "OMCPrivateConstants.h"
#include <string.h>

// Optional ActionUI add-ons: register extra element types so dialogs can use them.
// Each is linked via its own ActionUI Swift package (see project setup) and exposes a plain
// C entry point (@_cdecl) rather than an Objective-C class, so we forward-declare it here - it is
// not emitted into a generated -Swift.h. Call each once on the main thread before any dialog is built.
extern "C" void ActionUIQuickLook_register(void);
extern "C" void ActionUICachedImage_register(void);
extern "C" void ActionUIRichText_register(void);
extern "C" void ActionUIDiff_register(void);
extern "C" void ActionUIChat_register(void);

// NSTemporaryDirectory() on macOS is confstr(_CS_DARWIN_USER_TEMP_DIR): the /var/folders/<...>/T
// directory launchd creates per uid, mode 0700. It does NOT consult $TMPDIR - checking the
// variable first is swift-corelibs-foundation's behavior, not Apple's - and the difference is in
// our favor. Every process of this uid computes the same path whatever the environment says, so
// the app, OMCService and the contextual menu plugin share one cache, and no environment variable
// can redirect where an applet loads bytecode from.
//
// For a sandboxed host it resolves to that container's own tmp, writable where the old fixed
// /tmp/Pyc was not. No OMC host is sandboxed today, so treat that as a property worth having
// rather than a problem being solved.
//
// Deliberately no /tmp fallback. See the header for what is stored here and why a world-writable
// parent is the wrong place for it. NSTemporaryDirectory() effectively never comes back empty; if
// it does, a directory under the user's own home is the next safest thing, and failing that we
// report NULL and let the caller leave the variable alone.
//
// Computed once, because the answer cannot change for the life of the process. dispatch_once
// rather than a plain static because the OMCExecuteCommand entry points are public C API a client
// may call from any thread; the framework's own code is runloop-driven and single-threaded.
const char *OMCGetPythonPycachePrefix(void)
{
    static const char *sPycachePrefix = NULL;
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
        // Own pool: a client may make the first call from a thread that has none, and
        // fileSystemRepresentation hands back a buffer the pool owns rather than the string.
        @autoreleasepool
        {
            NSString *baseDir = NSTemporaryDirectory();
            if ([baseDir length] == 0)
            {
                // Unlike $TMPDIR's directory this one is never swept, so it takes the
                // bundle-identifier subdirectory ~/Library/Caches expects.
                NSString *homeDir = NSHomeDirectory();
                if ([homeDir length] > 0)
                    baseDir = [homeDir stringByAppendingPathComponent:@"Library/Caches/com.abracode.OMC"];
            }
            if ([baseDir length] > 0)
            {
                // strdup while the pool is still open: the buffer dies with it, the copy does not.
                const char *fsPath = [[baseDir stringByAppendingPathComponent:@"Pyc"] fileSystemRepresentation];
                if (fsPath != NULL)
                    sPycachePrefix = strdup(fsPath); // never freed on purpose: it lives as long as the process
            }
        }
    });
    return sPycachePrefix;
}

@interface OMCAppLifetimeEvents : NSObject
@end

@implementation OMCAppLifetimeEvents

- (id)init
{
    self = [super init];
    if(self == nil)
        return nil;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillFinishLaunching:)
                                                 name:NSApplicationWillFinishLaunchingNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidFinishLaunching:)
                                                 name:NSApplicationDidFinishLaunchingNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillTerminate:)
                                                 name:NSApplicationWillTerminateNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidBecomeActive:)
                                                 name:NSApplicationDidBecomeActiveNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appDidResignActive:)
                                                 name:NSApplicationDidResignActiveNotification
                                               object:nil];

    return self;
}

// Python writes bytecode caches next to the source by default, which for an embedded interpreter
// means INSIDE the app bundle - files we did not sign, breaking the code signature seal.
// OmcExecutor exports PYTHONPYCACHEPREFIX (OmcExecutor.cp) for the script handlers IT spawns, but
// that only covers its own children. Anything spawned from inside the app process inherits the
// APP's environment, which never carried the variable - most visibly ActionUIChat's ACP agent,
// which in turn spawns MCP stdio servers off the bundled python and had them cache into the
// bundle. Setting it on our own process is what makes the variable actually inheritable, so every
// descendant gets it without each spawn site having to know about it.
//
// Guarded on the embedded interpreter for the same reason OmcExecutor guards its export: with no
// bundled Python there is nothing of ours to redirect, and we must not silently relocate the
// caches of a system python a handler happens to call.
//
// Not overwritten if already present (setenv overwrite=0), mirroring the add-if-absent semantics
// of CFDictionaryAddValue in OmcExecutor: a deliberately set external value is honored, and any
// prefix keeps the caches out of the bundle, which is the point. The honoring reaches this process
// only - CreateEnviron (omc_popen.c) merges the per-command dictionary OVER the real environ key
// by key, so a spawned handler sees OmcExecutor's value rather than an inherited one.

+ (void)setPythonPycachePrefixIfEmbedded:(NSBundle *)bundle
{
    NSString *pythonPath = [[bundle bundlePath] stringByAppendingPathComponent:@"Contents/Library/Python/bin/python3"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:pythonPath])
    {
        const char *pycachePrefix = OMCGetPythonPycachePrefix();
        if (pycachePrefix != NULL)
            setenv("PYTHONPYCACHEPREFIX", pycachePrefix, 0);
    }
}

// DISABLED 2026-08-23. Kept, with the measurements, so the investigation is not repeated.
//
// The original intent is the comment that used to head this function:
//
//     "Python only precompiles imported modules. It does not automatically create cache
//      for the main execution scripts. This function also precompiles the top level .py files."
//
// The first two sentences are true. The third - the reason the function existed - cannot work.
// CPython never CONSULTS a bytecode cache for __main__; it compiles the main script from source
// on every run. So the .pyc files this produced for the top-level handlers were dead the moment
// they were written.
//
// How that was established, because the two obvious tests are not tests:
//   - Corrupting the .pyc proves nothing. A bad magic number makes CPython fall back to source
//     silently, so a consulted cache and an ignored one behave identically.
//   - Running with an empty cache and seeing no __main__ .pyc appear shows only that it is never
//     WRITTEN, not that a pre-existing one would be ignored.
// The decisive test is a .pyc that is valid and FRESH but holds different bytecode: correct
// MAGIC_NUMBER, flags 0, mtime and size fields copied from the source, wrapping a code object
// compiled from other text. Whichever text runs tells you which one was used. It needs a positive
// control in the same run - an imported module forged the same way - or "ran from source" is
// indistinguishable from a botched forgery. Result:
//     imported module, forged .pyc  ->  ran the FORGED bytecode   (cache is consulted)
//     __main__ script, forged .pyc  ->  ran the SOURCE            (cache is ignored)
// Corroborated by `python -v`, which prints "# code object from '...pyc'" for the imported module
// and nothing for __main__, and by access times: the run never opens the __main__ .pyc at all.
//
// What the call really did was precompile the modules the handlers IMPORT - which, as its own
// comment said, Python already does by itself. It also lands in the right place without help:
// setPythonPycachePrefixIfEmbedded above and OmcExecutor.cp both export PYTHONPYCACHEPREFIX, so a
// lazily written .pyc goes to the cache prefix and never into the signed bundle.
//
// Measured on ICEdit.app (median of 10-15 runs; bare interpreter startup is 8.1 ms of each):
//     this call at launch, warm cache   23.7 ms  EVERY launch, synchronous on the launch path
//     this call at launch, cold cache  123.0 ms
//     compile time it saved, once        2.1 ms  (Zip 2.9 ms; four of seven applets: 0 ms,
//                                                 their scripts import no sibling module at all)
// It never breaks even: the cost recurs on every launch and one launch already costs an order of
// magnitude more than the one-off saving. Deferred compilation does the useful half by itself.
//
// Consequence for tooling: the embedded-Python thinner may now remove compileall. Applets thinned
// while this call was live logged "No module named compileall" to stderr per launch and nothing
// else, because system()'s status is discarded - which is how it went unnoticed in shipped builds.
//
// If this is ever revived, note that Contents/Library/Packages is where a sizable embedded module
// actually lives (about 14 MB of .py on the MCP applets, ~0.95 s to compile) and it was never
// covered here. Eagerly compiling that would block launch for a second to precompile a tree of
// which only a fraction is ever imported, so it wants -j0 and an asynchronous launch, not system().
#if 0
+ (void)compilePythonScriptsIfEmbedded:(NSBundle *)bundle
{
    NSString *bundlePath = [bundle bundlePath];
    NSString *pythonPath = [bundlePath stringByAppendingPathComponent:@"Contents/Library/Python/bin/python3"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:pythonPath])
    {
        NSString *scriptsPath = [bundlePath stringByAppendingPathComponent:@"Contents/Resources/Scripts"];
        const char *pycachePrefix = OMCGetPythonPycachePrefix();
        if (pycachePrefix == NULL)
            return;
        NSString *command = [NSString stringWithFormat:@"export PYTHONPYCACHEPREFIX=\"%@\"; \"%@\" -m compileall \"%@\"", @(pycachePrefix), pythonPath, scriptsPath];
        // simple system() call is synchronous and does not enter a runloop to wait for the execution to end
        system([command UTF8String]);
    }
}
#endif

- (void)appWillFinishLaunching:(NSNotification *)notification
{
    TRACE_CSTR("App will finish launching\n");

    // Before anything can spawn a child: this is what every descendant inherits from.
    [OMCAppLifetimeEvents setPythonPycachePrefixIfEmbedded:[NSBundle mainBundle]];

    // Register optional ActionUI add-on element types before any dialog window is built.
    ActionUIQuickLook_register();
    ActionUICachedImage_register();
    ActionUIRichText_register();
    ActionUIDiff_register();
    ActionUIChat_register();

    // Disabled: eager compileall cost 23.7 ms of synchronous launch time on every start to save
    // 2.1 ms once, and the part it was written for - precompiling the top-level handler scripts -
    // cannot work, because CPython never reads a bytecode cache for __main__. Deferred compilation
    // covers the rest. See compilePythonScriptsIfEmbedded above for the measurements and the test.
    // [OMCAppLifetimeEvents compilePythonScriptsIfEmbedded:[NSBundle mainBundle]];

    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.will.launch"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                      allowKeyWindowSubcommand:NO
                                                  delegate:self];
}

- (void)appDidFinishLaunching:(NSNotification *)notification
{
    TRACE_CSTR("App did finish launching");
    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.did.launch"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                      allowKeyWindowSubcommand:NO
                                                  delegate:self];
}

- (void)appDidBecomeActive:(NSNotification *)notification
{
    TRACE_CSTR("App did become active");
    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.did.activate"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                      allowKeyWindowSubcommand:NO
                                                  delegate:self];
}

- (void)appDidResignActive:(NSNotification *)notification
{
    TRACE_CSTR("App did resign active");
    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.did.deactivate"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                      allowKeyWindowSubcommand:NO
                                                  delegate:self];
}

- (void)appWillTerminate:(NSNotification *)notification
{
    TRACE_CSTR("App will terminate");
    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.will.terminate"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                      allowKeyWindowSubcommand:NO
                                                  delegate:self];

    // Last chance to unlink the socket: NSApplication's terminate ends in libc exit(), so nothing
    // that runs after the run loop would ever fire. ActionUIRemote keeps an atexit backstop for
    // hosts that skip this notification entirely, but doing it here is the orderly path.
    [[OMCActionUIRemoteHost shared] stop];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end


class OMCAppLifetimeEventsRegistration
{
public:
    OMCAppLifetimeEventsRegistration()
    {
        mListener = [[OMCAppLifetimeEvents alloc] init];
    }
    
    ~OMCAppLifetimeEventsRegistration()
    {
        mListener = nil;
    }
    
    OMCAppLifetimeEvents *mListener;
};

OMCAppLifetimeEventsRegistration gAppLifetimeEventsRegistration;
