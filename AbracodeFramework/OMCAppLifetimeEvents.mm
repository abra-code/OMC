//
//  OMCAppLifetimeEvents.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 10/25/25.
//

#import "OMCCommandExecutor.h"
#include "DebugSettings.h"
#include "OMCPrivateConstants.h"

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

    return self;
}

// On app launch precompile all .py code in Resources/Scripts if
// the Python distribution is embedded in app bundle at Library/Python/.
// Python only precompiles imported modules. It does not automatically create cache
// for the main execution scripts. This function also precompiles the top level .py files.
// Compiling .py code more than one time is a no-op: Python is smart enough not to re-compile .pyc files
// if the source code has not changed.

+ (void)compilePythonScriptsIfEmbedded:(NSBundle *)bundle
{
    NSString *bundlePath = [bundle bundlePath];
    NSString *pythonPath = [bundlePath stringByAppendingPathComponent:@"Contents/Library/Python/bin/python3"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:pythonPath])
    {
        NSString *scriptsPath = [bundlePath stringByAppendingPathComponent:@"Contents/Resources/Scripts"];
        NSString *command = [NSString stringWithFormat:@"export PYTHONPYCACHEPREFIX=\"%@\"; \"%@\" -m compileall \"%@\"", @(PYTHONPYCACHEPREFIX), pythonPath, scriptsPath];
        // simple system() call is synchronous and does not enter a runloop to wait for the execution to end
        system([command UTF8String]);
    }
}

- (void)appWillFinishLaunching:(NSNotification *)notification
{
    TRACE_CSTR("App will finish launching\n");
    [OMCAppLifetimeEvents compilePythonScriptsIfEmbedded:[NSBundle mainBundle]];

    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.will.launch"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                                  delegate:self];
}

- (void)appDidFinishLaunching:(NSNotification *)notification
{
    TRACE_CSTR("App did finish launching");
    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.did.launch"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                                  delegate:self];
}

- (void)appWillTerminate:(NSNotification *)notification
{
    TRACE_CSTR("App will terminate");
    __unused OSStatus err = [OMCCommandExecutor runCommand:@"app.will.terminate"
                                            forCommandFile:@"Command.plist"
                                               withContext:nil
                                              useNavDialog:NO
                                                  delegate:self];

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
