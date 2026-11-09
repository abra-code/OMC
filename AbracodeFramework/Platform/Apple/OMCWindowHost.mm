//
//  OMCWindowHost.mm
//  Abracode
//
//  The macOS host of the built-in ActionUI documents (Platform/OMCWindowHost.h): an NSWindow whose
//  content view controller is the ObjC adapter's hosting controller for the document.
//

#import <Cocoa/Cocoa.h>
#include "OMCWindowHost.h"
#include "CFObj.h"
#include "ACFString.h"
#include "ActionUIC.h"
@import ActionUIObjCAdapter;

class OMCAppleHostedWindow;

@interface OMCHostedWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic, assign) OMCAppleHostedWindow *owner; // cleared by the owner before it goes away
@end

class OMCAppleHostedWindow : public OMCHostedWindow
{
public:
							OMCAppleHostedWindow(NSWindow *inWindow, NSViewController *inController, CFStringRef inWindowUUID,
												std::function<void()> inOnClosedByUser)
								: mWindow(inWindow), mController(inController), mWindowUUID(inWindowUUID, kCFObjRetain),
								mOnClosedByUser(std::move(inOnClosedByUser))
							{
								mDelegate = [OMCHostedWindowDelegate new];
								mDelegate.owner = this;
								mWindow.delegate = mDelegate;
							}

	virtual					~OMCAppleHostedWindow() override
							{
								mDelegate.owner = nullptr;
								Close();
								mWindow.delegate = nil;
								mWindow.contentViewController = nil;
								mController = nil;
								std::string uuid = ACFStringToUTF8(mWindowUUID);
								actionUIRemoveWindow(uuid.c_str());
							}

	virtual CFStringRef		GetWindowUUID() const override { return mWindowUUID; }

	virtual void			Show() override
							{
								if(!mClosed)
									[mWindow makeKeyAndOrderFront:nil];
							}

	virtual void			Close() override
							{
								if(mClosed)
									return;
								mClosed = true; // before close: windowWillClose then knows it was not the user
								[mWindow close];
							}

	// From the window's delegate
	void					WindowWillClose()
							{
								if(mClosed)
									return;
								mClosed = true;
								if(mOnClosedByUser)
									mOnClosedByUser(); // may delete this
							}

private:
	NSWindow *				mWindow;
	NSViewController *		mController;
	OMCHostedWindowDelegate *mDelegate;
	CFObj<CFStringRef>		mWindowUUID;
	std::function<void()>	mOnClosedByUser;
	bool					mClosed {false};
};

@implementation OMCHostedWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
	OMCAppleHostedWindow *owner = self.owner;
	if(owner != nullptr)
		owner->WindowWillClose();
}

@end

std::unique_ptr<OMCHostedWindow>
OMCCreateHostedWindow(const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser)
{
	if(inSpec.documentName == nullptr)
		return nullptr;

	NSBundle *frameworkBundle = [NSBundle bundleForClass:[OMCHostedWindowDelegate class]];
	NSURL *documentURL = [frameworkBundle URLForResource:(__bridge NSString *)inSpec.documentName withExtension:@"json"];
	if(documentURL == nil)
	{
		NSLog(@"OMC: the built-in document %@ is missing from %@", (__bridge NSString *)inSpec.documentName, frameworkBundle.bundlePath);
		return nullptr;
	}

	NSString *windowUUID = [NSUUID UUID].UUIDString;
	NSViewController *controller = [ActionUIObjC loadHostingControllerWithURL:documentURL windowUUID:windowUUID isContentView:YES];
	if(controller == nil)
	{
		NSLog(@"OMC: cannot load the built-in document %@", documentURL.path);
		return nullptr;
	}

	NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable;
	if(inSpec.closable)
		style |= NSWindowStyleMaskClosable;
	if(inSpec.resizable)
		style |= NSWindowStyleMaskResizable;

	NSSize contentSize = controller.view.fittingSize;
	if(inSpec.contentWidth > 0)
		contentSize.width = inSpec.contentWidth;
	if(inSpec.contentHeight > 0)
		contentSize.height = inSpec.contentHeight;

	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, contentSize.width, contentSize.height)
												   styleMask:style backing:NSBackingStoreBuffered defer:YES];
	window.releasedWhenClosed = NO;
	window.identifier = windowUUID; // the document's window UUID: tests read the document through it
	window.contentViewController = controller;
	[window setContentSize:contentSize];
	// after the hosting controller is installed: it resets the title (NSHostingView)
	if(inSpec.title != nullptr)
		window.title = (__bridge NSString *)inSpec.title;
	if(inSpec.level == OMCHostedWindowLevel::floating)
		window.level = NSFloatingWindowLevel;

	[window center];
	if(inSpec.frameAutosaveName != nullptr)
		[window setFrameAutosaveName:(__bridge NSString *)inSpec.frameAutosaveName]; // restores a saved frame

	return std::unique_ptr<OMCHostedWindow>(new OMCAppleHostedWindow(window, controller, (__bridge CFStringRef)windowUUID, std::move(inOnClosedByUser)));
}
