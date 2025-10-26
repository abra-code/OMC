//
//  OMCAppLifetimeEvents.mm
//  Abracode
//
//  Created by Tomasz Kukielka on 10/25/25.
//

#import "OMCCommandExecutor.h"
#include "DebugSettings.h"

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

- (void)appWillFinishLaunching:(NSNotification *)notification
{
    TRACE_CSTR("App will finish launching\n");
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
