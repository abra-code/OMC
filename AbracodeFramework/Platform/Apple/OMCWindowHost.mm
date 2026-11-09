//
//  OMCWindowHost.mm
//  Abracode
//
//  The macOS host of the built-in ActionUI documents and the ActionUI command windows
//  (Platform/OMCWindowHost.h): an NSWindow, or a utility NSPanel for the floating levels, whose
//  content view controller is the ObjC adapter's hosting controller for the document.
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
// sizeLimitsFromDocument: the document's limits, which are those of the area below the titlebar
@property (nonatomic) BOOL hasSizeLimits;
@property (nonatomic) NSSize minLayoutSize;
@property (nonatomic) NSSize maxLayoutSize;
@end

// The height the titlebar takes out of the content view: 0 unless the content spans the titlebar.
// Not a constant: a toolbar makes the titlebar taller, and SwiftUI installs its toolbar only once
// the hosting view has laid out in a window, hence the layout pass before measuring.
static CGFloat TitlebarHeight(NSWindow *inWindow)
{
	[inWindow layoutIfNeeded];
	CGFloat height = NSHeight([inWindow contentRectForFrameRect:inWindow.frame]) - NSHeight(inWindow.contentLayoutRect);
	return (height < 0.0) ? 0.0 : height;
}

// Applies the document's size limits, converted from the area below the titlebar to the content
// view by adding the titlebar's height. Run again when that height may have changed (the toolbar
// appearing); cheap and idempotent.
static void ApplySizeLimits(NSWindow *inWindow, OMCHostedWindowDelegate *inLimits)
{
	if( (inWindow == nil) || (inLimits == nil) || !inLimits.hasSizeLimits )
		return;

	CGFloat titlebarHeight = TitlebarHeight(inWindow);
	NSSize minContentSize = inLimits.minLayoutSize;
	minContentSize.height += titlebarHeight;
	NSSize maxContentSize = inLimits.maxLayoutSize;
	// the maximum is CGFLOAT_MAX (or infinity) for flexible content: leave an unlimited axis alone
	if(maxContentSize.height < (CGFLOAT_MAX - titlebarHeight))
		maxContentSize.height += titlebarHeight;

	inWindow.contentMinSize = minContentSize;
	inWindow.contentMaxSize = maxContentSize;

	// Raising the minimum does not resize the window, so a window sized before the toolbar appeared
	// would keep squeezing its content: grow it to the new minimum
	NSSize currentSize = inWindow.contentLayoutRect.size;
	currentSize.height += titlebarHeight;
	if( ((currentSize.height + 0.5) < minContentSize.height) || ((currentSize.width + 0.5) < minContentSize.width) )
	{
		NSSize grown = NSMakeSize(MAX(currentSize.width, minContentSize.width), MAX(currentSize.height, minContentSize.height));
		[inWindow setContentSize:grown];
	}
}

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
							OMCAppleHostedWindow(NSWindow *inWindow, NSViewController *inController, OMCHostedWindowDelegate *inDelegate,
												CFStringRef inWindowUUID, const OMCHostedWindowSpec &inSpec, std::function<void()> inOnClosedByUser)
								: mWindow(inWindow), mController(inController), mDelegate(inDelegate), mWindowUUID(inWindowUUID, kCFObjRetain),
								mOnClosedByUser(std::move(inOnClosedByUser)), mPlacement(inSpec)
							{
								// only the size, placement and flags are kept: the references are not retained
								mPlacement.documentName = nullptr;
								mPlacement.documentURL = nullptr;
								mPlacement.windowUUID = nullptr;
								mPlacement.title = nullptr;
								mPlacement.frameAutosaveName = nullptr;
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
								if(mPlacement.removesModelWhenDestroyed)
								{
									std::string uuid = ACFStringToUTF8(mWindowUUID);
									actionUIRemoveWindow(uuid.c_str());
								}
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

	virtual void			SetRepresentedFile(CFURLRef inFileURL) override
							{
								NSURL *fileURL = (__bridge NSURL *)inFileURL;
								if(fileURL == nil)
									return;
								mWindow.representedURL = fileURL;
								[mWindow setTitleWithRepresentedFilename:fileURL.path];
							}

	virtual void			SetTitle(CFStringRef inTitle) override
							{
								if(inTitle != nullptr)
									mWindow.title = (__bridge NSString *)inTitle;
							}

	virtual bool			IsKey() const override { return mWindow.isKeyWindow; }

	virtual void			SetTopLeftPosition(double inLeft, double inTop) override
							{
								OMCHostedWindowSpec position;
								position.placement = OMCHostedWindowPlacement::absolute;
								position.absoluteLeft = inLeft;
								position.absoluteTop = inTop;
								PlaceWindow(mWindow, position);
							}

	virtual void			SetLayoutSize(double inWidth, double inHeight) override
							{
								[mWindow setContentSize:NSMakeSize(inWidth, inHeight + TitlebarHeight(mWindow))];
							}

	virtual void			SetKeyChangeCallbacks(std::function<void()> inOnBecameKey, std::function<void()> inOnResignedKey) override
							{
								mOnBecameKey = std::move(inOnBecameKey);
								mOnResignedKey = std::move(inOnResignedKey);
							}

	virtual void *			GetNativeWindow() const override { return (__bridge void *)mWindow; }

	// From the window's delegate
	void					BecameKey()
							{
								// a copy: the callback may delete this, and with it the member while it runs
								std::function<void()> callback = mOnBecameKey;
								if(callback)
									callback(); // may delete this
							}

	void					ResignedKey()
							{
								// a copy: the callback may delete this, and with it the member while it runs
								std::function<void()> callback = mOnResignedKey;
								if(callback)
									callback(); // may delete this
							}

	void					WindowWillClose()
							{
								if(mClosed)
									return;
								MarkClosed();
								// a copy: the callback may delete this, and with it the member while it runs
								std::function<void()> callback = mOnClosedByUser;
								if(callback)
									callback(); // may delete this
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
	std::function<void()>	mOnBecameKey;
	std::function<void()>	mOnResignedKey;
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

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	OMCAppleHostedWindow *owner = self.owner;
	if(owner != nullptr)
		owner->BecameKey();
}

- (void)windowDidResignKey:(NSNotification *)notification
{
	OMCAppleHostedWindow *owner = self.owner;
	if(owner != nullptr)
		owner->ResignedKey();
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
	if( (inSpec.placement == OMCHostedWindowPlacement::standard) || (inSpec.placement == OMCHostedWindowPlacement::restoredElseCentered) || (mainScreen == nil) )
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
	NSURL *documentURL = (__bridge NSURL *)inSpec.documentURL;
	if(documentURL == nil)
	{
		if(inSpec.documentName == nullptr)
			return nullptr;
		NSBundle *frameworkBundle = [NSBundle bundleForClass:[OMCHostedWindowDelegate class]];
		documentURL = [frameworkBundle URLForResource:(__bridge NSString *)inSpec.documentName withExtension:@"json"];
		if(documentURL == nil)
		{
			NSLog(@"OMC: the built-in document %@ is missing from %@", (__bridge NSString *)inSpec.documentName, frameworkBundle.bundlePath);
			return nullptr;
		}
	}

	NSString *windowUUID = (inSpec.windowUUID != nullptr) ? [(__bridge NSString *)inSpec.windowUUID copy] : [NSUUID UUID].UUIDString;
	NSViewController *controller = [ActionUIObjC loadHostingControllerWithURL:documentURL windowUUID:windowUUID isContentView:YES];
	if(controller == nil)
	{
		NSLog(@"OMC: cannot load the ActionUI document %@", documentURL.path);
		return nullptr;
	}

	OMCHostedWindowDelegate *delegate = [OMCHostedWindowDelegate new];

	// The document's limits: the minimum is what the content reports for a zero size proposal, the
	// maximum for an infinite one (measured on the bare root element: the window-level toast and
	// modal wrapper always expands to fill). A root with a fixed frame (exact width and height)
	// reports the same minimum and maximum, which makes a window of fixed size.
	bool isFixedSize = false;
	if(inSpec.sizeLimitsFromDocument)
	{
		NSSize minLayoutSize = [ActionUIObjC minContentSizeForWindowUUID:windowUUID];
		NSSize maxLayoutSize = [ActionUIObjC maxContentSizeForWindowUUID:windowUUID];
		delegate.hasSizeLimits = (minLayoutSize.width > 10.0) && (minLayoutSize.height > 10.0);
		delegate.minLayoutSize = minLayoutSize;
		delegate.maxLayoutSize = maxLayoutSize;
		isFixedSize = delegate.hasSizeLimits &&
						((maxLayoutSize.width - minLayoutSize.width) < 1.0) &&
						((maxLayoutSize.height - minLayoutSize.height) < 1.0);
	}

	bool isPanel = (inSpec.level != OMCHostedWindowLevel::normal);
	NSWindowStyleMask style = NSWindowStyleMaskTitled;
	if(isPanel)
		style |= NSWindowStyleMaskUtilityWindow;
	else if(inSpec.miniaturizable)
		style |= NSWindowStyleMaskMiniaturizable;
	if(inSpec.closable)
		style |= NSWindowStyleMaskClosable;
	if(inSpec.resizable && !isFixedSize)
		style |= NSWindowStyleMaskResizable;
	// NSWindowStyleMaskFullSizeContentView is required, not cosmetic, for the command windows. On
	// macOS 27 (the same layout rendered correctly on 26), AppKit gives each column of SwiftUI's
	// NavigationSplitView an NSTitlebarBackgroundView (carrying the scroll-edge-effect pocket) at the
	// top of the split view's own bounds, which is only right while the split view starts at the top
	// of the window. Without this bit the content view starts below the titlebar, the split view can
	// never get there, and those bands paint over the detail column's first ~52 points: the top of
	// the detail pane is hidden behind a strip of glass. Spanning the full height also puts the window
	// title beside the sidebar, where the system apps put it. SwiftUI insets the content by the
	// window's safe area either way, so plain (non-split) documents keep their layout. The one visible
	// difference is a root background: it shows through the titlebar, the way it does in a SwiftUI
	// WindowGroup window. A split-view root with padding of its own needs ActionUI's
	// windowRootSafeArea as well, or the padding keeps it below the titlebar.
	if(inSpec.contentSpansTitlebar)
		style |= NSWindowStyleMaskFullSizeContentView;

	NSSize contentSize = controller.view.fittingSize;
	if(inSpec.contentWidth > 0)
		contentSize.width = inSpec.contentWidth;
	if(inSpec.contentHeight > 0)
		contentSize.height = inSpec.contentHeight;

	NSRect contentRect = NSMakeRect(0, 0, contentSize.width, contentSize.height);
	NSWindow *window = nil;
	if(isPanel)
	{
		NSPanel *panel = [[OMCHostedNSPanel alloc] initWithContentRect:contentRect styleMask:style backing:NSBackingStoreBuffered defer:YES];
		panel.floatingPanel = YES; // before the level below: it sets the level too
		window = panel;
	}
	else
	{
		window = [[OMCHostedNSWindow alloc] initWithContentRect:contentRect styleMask:style backing:NSBackingStoreBuffered defer:YES];
	}
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

	ApplySizeLimits(window, delegate);

	if(inSpec.placement == OMCHostedWindowPlacement::restoredElseCentered)
	{
		BOOL frameRestored = NO;
		if(inSpec.frameAutosaveName != nullptr)
		{
			NSString *autosaveName = (__bridge NSString *)inSpec.frameAutosaveName;
			[window setFrameAutosaveName:autosaveName];
			frameRestored = [window setFrameUsingName:autosaveName];
		}

		if(!frameRestored)
		{
			// The hosting view's fitting size is the content's ideal size plus the window's safe area
			// (the titlebar, when the content spans it): unlike the limits it needs nothing added
			NSSize fittingSize = controller.view.fittingSize;
			if( (fittingSize.width > 10) && (fittingSize.height > 10) )
				[window setContentSize:fittingSize];
			[window center];
		}
		else if(isFixedSize)
		{
			// a frame saved before the document became fixed-size may carry a stale size: the
			// document's size wins, the saved position stays
			NSSize fixedSize = delegate.minLayoutSize;
			fixedSize.height += TitlebarHeight(window);
			[window setContentSize:fixedSize];
		}
	}
	else
	{
		PlaceWindow(window, inSpec);
		if(inSpec.frameAutosaveName != nullptr)
			[window setFrameAutosaveName:(__bridge NSString *)inSpec.frameAutosaveName]; // restores a saved frame
	}

	if(delegate.hasSizeLimits)
	{
		// SwiftUI installs its NSToolbar the first time the hosting view lays out in a window, and a
		// toolbar makes the titlebar taller: apply the limits again once that has settled, so the
		// window's minimum still matches what the document needs
		__weak NSWindow *weakWindow = window;
		__weak OMCHostedWindowDelegate *weakDelegate = delegate;
		dispatch_async(dispatch_get_main_queue(), ^{
			ApplySizeLimits(weakWindow, weakDelegate);
		});
	}

	return std::unique_ptr<OMCHostedWindow>(new OMCAppleHostedWindow(window, controller, delegate, (__bridge CFStringRef)windowUUID, inSpec, std::move(inOnClosedByUser)));
}
