//
//  OMCTestPlatform.mm
//  Abracode
//
//  macOS implementation of Platform/OMCTestPlatform.h.
//

#import <Cocoa/Cocoa.h>
#import "OMCWindowController.h"
#include "OMCTestPlatform.h"

bool
OMCTestPlatformDispatchToKeyWindow(CFStringRef inCommandNameOrId, CFTypeRef inContext)
{
	// The same as the menu's hook in OMCCommandExecutor.mm.
	OMCWindowController *keyWindowController = [OMCWindowController findControllerForKeyWindow];
	if(keyWindowController == nil)
		return false;
	[keyWindowController dispatchCommand:(__bridge NSString *)inCommandNameOrId withContext:inContext];
	return true;
}

void
OMCTestPlatformRequestQuit(void)
{
	[NSApp terminate:nil];
}
