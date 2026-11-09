//
//  OMCWindowHost.mm
//  Abracode
//
//  The macOS host of the built-in ActionUI documents (Platform/OMCWindowHost.h): an NSWindow, or a
//  utility NSPanel for the floating levels, whose content view controller is the ObjC adapter's
//  hosting controller for the document.
//

#import <Cocoa/Cocoa.h>
#include "OMCWindowHost.h"
#include "CFObj.h"
#include "ACFString.h"
#include "ActionUIC.h"
@import ActionUIObjCAdapter;

class OMCAppleHostedWindow;
static void PlaceWindow(NSWindow *inWindow, const OMCHostedWindowSpec &inSpec);

@interface OMCHostedWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic, assign) OMCAppleHostedWindow *owner; // cleared by the owner before it goes away
@end

// Command-W closes a closable window, also in a process with no menu bar (a background app)
static BOOL HandleCloseKey(NSWindow *inWindow, NSEvent *inEvent)
{
	NSEventModifierFlags modifiers = inEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
	if( (modifiers != NSEventModifierFlagCommand) || ![inEvent.charactersIgnoringModifiers isEqualToString:@"w"] )
		return NO;
	if( (inWindow.styleMask & NSWindowStyleMaskClosable) == 0 )
		return NO;
	[inWindow performClose:nil];
	return YES;
}

@interface OMCHostedNSWindow : NSWindow
@end

@implementation OMCHostedNSWindow
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
	return HandleCloseKey(self, event) || [super performKeyEquivalent:event];
}
@end

@interface OMCHostedNSPanel : NSPanel
@end

@implementation OMCHostedNSPanel
- (BOOL)performKeyEquivalent:(NSEvent *)event
{
	return HandleCloseKey(self, event) || [super performKeyEquivalent:event];
}
@end

static int sOpenHostedWindowCount = 0;

class OMCAppleHostedWindow : public OMCHostedWindow
{
public:
							OMCAppleHostedWindow(NSWindow *inWindow, NSViewController *inController, CFStringRef inWindowUUID,
												const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser)
								: mWindow(inWindow), mController(inController), mWindowUUID(inWindowUUID, kCFObjRetain),
								mOnClosedByUser(std::move(inOnClosedByUser)), mPlacement(inSpec)
							{
								// only the size and placement are kept: the strings are not retained
								mPlacement.documentName = nullptr;
								mPlacement.title = nullptr;
								mPlacement.frameAutosaveName = nullptr;
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
								if(mClosed)
									return;
								if(!mShown)
								{
									mShown = true;
									sOpenHostedWindowCount++;
								}
								[mWindow makeKeyAndOrderFront:nil];
							}

	virtual void			SizeToContent() override
							{
								if(mClosed || mShown)
									return;
								[mController.view layoutSubtreeIfNeeded];
								NSSize fitting = mController.view.fittingSize;
								NSSize contentSize = [mWindow contentRectForFrameRect:mWindow.frame].size;
								if(mPlacement.contentWidth <= 0)
									contentSize.width = fitting.width;
								if(mPlacement.contentHeight <= 0)
									contentSize.height = fitting.height;
								[mWindow setContentSize:contentSize];
								if(mPlacement.placement != OMCHostedWindowPlacement::cascade) // it would step on again
									PlaceWindow(mWindow, mPlacement);
							}

	virtual void			Close() override
							{
								if(mClosed)
									return;
								MarkClosed(); // before close: windowWillClose then knows it was not the user
								[mWindow close];
							}

	virtual void			RunModal() override
							{
								if(mClosed || mInModal)
									return;
								Show();
								mInModal = true;
								mModalEnded = false;
								[NSApp runModalForWindow:mWindow];
								mInModal = false;
							}

	virtual void			EndModal() override
							{
								if(!mInModal || mModalEnded)
									return;
								mModalEnded = true;
								[NSApp stopModal];
								// stopModal takes effect when the modal loop handles its next event: when this
								// runs outside of an event (a timer), that event has to be sent
								NSEvent *wakeUp = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
																modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
								[NSApp postEvent:wakeUp atStart:NO];
							}

	// From the window's delegate
	void					WindowWillClose()
							{
								if(mClosed)
									return;
								MarkClosed();
								if(mOnClosedByUser)
									mOnClosedByUser(); // may delete this
							}

private:
	void					MarkClosed()
							{
								EndModal();
								mClosed = true;
								if(mShown)
								{
									mShown = false;
									sOpenHostedWindowCount--;
								}
							}

	NSWindow *				mWindow;
	NSViewController *		mController;
	OMCHostedWindowDelegate *mDelegate;
	CFObj<CFStringRef>		mWindowUUID;
	std::function<void()>	mOnClosedByUser;
	OMCHostedWindowSpec		mPlacement;
	bool					mShown {false};
	bool					mClosed {false};
	bool					mInModal {false};
	bool					mModalEnded {false};
};

@implementation OMCHostedWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
	OMCAppleHostedWindow *owner = self.owner;
	if(owner != nullptr)
		owner->WindowWillClose();
}

@end

static NSPoint sCascadePoint = NSZeroPoint;

void
OMCResetHostedWindowCascading()
{
	sCascadePoint = NSZeroPoint;
}

int
OMCOpenHostedWindowCount()
{
	return sOpenHostedWindowCount;
}

// The placement rules of OMC's output window, unchanged from the nib window's controller (5.5)
static void PlaceWindow(NSWindow *inWindow, const OMCHostedWindowSpec &inSpec)
{
	NSScreen *mainScreen = [NSScreen mainScreen];
	if( (inSpec.placement == OMCHostedWindowPlacement::standard) || (mainScreen == nil) )
	{
		[inWindow center];
		return;
	}

	NSRect screenRect = mainScreen.visibleFrame;
	NSRect windowFrame = inWindow.frame;
	NSPoint fraction = NSMakePoint(-1.0, -1.0);
	NSPoint origin = NSZeroPoint; // the window's bottom-left corner

	switch(inSpec.placement)
	{
		case OMCHostedWindowPlacement::alert:
			fraction.x = 0.5;
			origin.y = NSMinY(screenRect) + NSHeight(screenRect) * 4.0 / 5.0 - NSHeight(windowFrame);
		break;

		case OMCHostedWindowPlacement::screenCenter:
			fraction = NSMakePoint(0.5, 0.5);
		break;

		case OMCHostedWindowPlacement::cascade:
		{
			if( NSEqualPoints(sCascadePoint, NSZeroPoint) )
			{ // the first one: the screen's top-left corner
				origin.x = NSMinX(screenRect);
				origin.y = NSMaxY(screenRect) - NSHeight(windowFrame);
				if( (origin.y + NSHeight(windowFrame)) < NSMinY(screenRect) )
					origin.y = NSMinY(screenRect) - NSHeight(windowFrame) + 20; // the top visible at the bottom of the screen
				[inWindow setFrameOrigin:origin];
			}
			sCascadePoint = [inWindow cascadeTopLeftFromPoint:sCascadePoint];
			return;
		}

		case OMCHostedWindowPlacement::absolute:
		default:
			fraction = NSMakePoint(inSpec.fractionLeft, inSpec.fractionTop);
			origin.x = NSMinX(screenRect) + inSpec.absoluteLeft;
			origin.y = NSMaxY(screenRect) - inSpec.absoluteTop - NSHeight(windowFrame);
			if( (origin.y + NSHeight(windowFrame)) < NSMinY(screenRect) )
				origin.y = NSMinY(screenRect) - NSHeight(windowFrame) + 20; // the top visible at the bottom of the screen
		break;
	}

	if(fraction.y >= 0.0)
	{ // the window's middle at the fraction, from the top
		if(fraction.y > 1.0)
			fraction.y = 1.0;
		origin.y = NSMinY(screenRect) + NSHeight(screenRect) * (1.0 - fraction.y) - NSHeight(windowFrame) / 2.0;
		if(origin.y < NSMinY(screenRect))
			origin.y = NSMinY(screenRect);
		if( (origin.y + NSHeight(windowFrame)) > NSMaxY(screenRect) )
			origin.y = NSMaxY(screenRect) - NSHeight(windowFrame);
	}

	if(fraction.x >= 0.0)
	{ // the window's middle at the fraction, from the left
		if(fraction.x > 1.0)
			fraction.x = 1.0;
		origin.x = NSMinX(screenRect) + NSWidth(screenRect) * fraction.x - NSWidth(windowFrame) / 2.0;
		if( (origin.x + NSWidth(windowFrame)) > NSMaxX(screenRect) )
			origin.x = NSMaxX(screenRect) - NSWidth(windowFrame);
		if(origin.x < NSMinX(screenRect))
			origin.x = NSMinX(screenRect);
	}

	[inWindow setFrameOrigin:origin];
}

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

	bool isPanel = (inSpec.level != OMCHostedWindowLevel::normal);
	NSWindowStyleMask style = NSWindowStyleMaskTitled;
	if(isPanel)
		style |= NSWindowStyleMaskUtilityWindow;
	else
		style |= NSWindowStyleMaskMiniaturizable;
	if(inSpec.closable)
		style |= NSWindowStyleMaskClosable;
	if(inSpec.resizable)
		style |= NSWindowStyleMaskResizable;

	NSSize contentSize = controller.view.fittingSize;
	if(inSpec.contentWidth > 0)
		contentSize.width = inSpec.contentWidth;
	if(inSpec.contentHeight > 0)
		contentSize.height = inSpec.contentHeight;

	NSRect contentRect = NSMakeRect(0, 0, contentSize.width, contentSize.height);
	NSWindow *window = nil;
	if(isPanel)
		window = [[OMCHostedNSPanel alloc] initWithContentRect:contentRect styleMask:style backing:NSBackingStoreBuffered defer:YES];
	else
		window = [[OMCHostedNSWindow alloc] initWithContentRect:contentRect styleMask:style backing:NSBackingStoreBuffered defer:YES];
	window.releasedWhenClosed = NO;
	window.identifier = windowUUID; // the document's window UUID: tests read the document through it
	window.contentViewController = controller;
	[window setContentSize:contentSize];
	// after the hosting controller is installed: it resets the title (NSHostingView)
	if(inSpec.title != nullptr)
		window.title = (__bridge NSString *)inSpec.title;

	switch(inSpec.level)
	{
		case OMCHostedWindowLevel::normal:
		break;

		case OMCHostedWindowLevel::floating:
			window.level = NSFloatingWindowLevel;
			window.hidesOnDeactivate = YES;
		break;

		case OMCHostedWindowLevel::utility:
			window.level = kCGUtilityWindowLevel;
			window.hidesOnDeactivate = NO;
		break;
	}

	PlaceWindow(window, inSpec);
	if(inSpec.frameAutosaveName != nullptr)
		[window setFrameAutosaveName:(__bridge NSString *)inSpec.frameAutosaveName]; // restores a saved frame

	return std::unique_ptr<OMCHostedWindow>(new OMCAppleHostedWindow(window, controller, (__bridge CFStringRef)windowUUID, inSpec, std::move(inOnClosedByUser)));
}
