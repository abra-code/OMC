//
//  OMCAppLifecycleObserver.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 10/25/25 (as OMCAppLifetimeEvents.mm).
//
//  The macOS side of OMCAppLifecycle.h: forwards NSApplication's launch, activation and
//  termination notifications to OMCHandleAppLifecycleEvent, which does the work. Also the macOS
//  OMCGetPythonPycachePrefix (OMCPrivateConstants.h).
//

#import <Cocoa/Cocoa.h>
#include "OMCAppLifecycle.h"
#include "OMCPrivateConstants.h"
#include <string.h>

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

@interface OMCAppLifecycleObserver : NSObject
@end

@implementation OMCAppLifecycleObserver

- (id)init
{
    self = [super init];
    if(self == nil)
        return nil;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(appWillFinishLaunching:) name:NSApplicationWillFinishLaunchingNotification object:nil];
    [center addObserver:self selector:@selector(appDidFinishLaunching:) name:NSApplicationDidFinishLaunchingNotification object:nil];
    [center addObserver:self selector:@selector(appWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    [center addObserver:self selector:@selector(appDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:self selector:@selector(appDidResignActive:) name:NSApplicationDidResignActiveNotification object:nil];
    return self;
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
// SetPythonPycachePrefixIfEmbedded (OMCAppLifecycle.cpp) and OmcExecutor.cp both export
// PYTHONPYCACHEPREFIX, so a lazily written .pyc goes to the cache prefix and never into the
// signed bundle.
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
    OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::WillLaunch);
}

- (void)appDidFinishLaunching:(NSNotification *)notification
{
    OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::DidLaunch);
}

- (void)appDidBecomeActive:(NSNotification *)notification
{
    OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::DidActivate);
}

- (void)appDidResignActive:(NSNotification *)notification
{
    OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::DidDeactivate);
}

- (void)appWillTerminate:(NSNotification *)notification
{
    OMCHandleAppLifecycleEvent(OMCAppLifecycleEvent::WillTerminate);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// Every process that loads the framework observes from the start, as before: the notifications
// only arrive in an app, and the work runs only for them
class OMCAppLifecycleObserverRegistration
{
public:
    OMCAppLifecycleObserverRegistration()
    {
        mObserver = [[OMCAppLifecycleObserver alloc] init];
    }

    ~OMCAppLifecycleObserverRegistration()
    {
        mObserver = nil;
    }

    OMCAppLifecycleObserver *mObserver;
};

OMCAppLifecycleObserverRegistration gAppLifecycleObserverRegistration;
