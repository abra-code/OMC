//
//  OMCOutputWindowController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 5/14/08.
//  Copyright 2008 Abracode Inc. All rights reserved.
//

#import "OMCOutputWindowController.h"
#include "OutputWindowHandler.h"
#import "OMCWindow.h"
#import "OMCPanel.h"
#import "OMCCustomWindow.h"

#ifndef __LP64__

EventHandlerUPP gOMCWindowCarbonEventHandlerUPP = NULL;

pascal OSStatus
OMCWindowCarbonEventHandlerProc( EventHandlerCallRef inCallRef,
									EventRef inEvent,
									void* inUserData )
{
	OSStatus err = eventNotHandledErr;
	UInt32     eventKind  = GetEventKind( inEvent );
	UInt32     eventClass  = GetEventClass( inEvent );

	if(eventClass == kEventClassCommand)
	{
		switch( eventKind )
		{
			case  kEventCommandUpdateStatus:
			{
				HICommand myCommand;
				GetEventParameter( inEvent, kEventParamDirectObject, typeHICommand, NULL, sizeof(HICommand), NULL, &myCommand );
				if(myCommand.commandID == kHICommandClose)
				{
					//NSLog(@"OMCWindowCarbonEventHandlerProc: capturing request for status of kHICommandClose");
					if( (myCommand.attributes == kHICommandFromMenu) && (myCommand.menu.menuRef != NULL) )
					{
						//NSLog(@"OMCWindowCarbonEventHandlerProc: kHICommandClose coming from menu - trying to disable");
						//NSLog(@"OMCWindowCarbonEventHandlerProc: kHICommandClose menu item index = %d", (int)myCommand.menu.menuItemIndex);
						err = noErr;

						DisableMenuItem(
							myCommand.menu.menuRef,
							myCommand.menu.menuItemIndex);
					}
				}
			}
			break;
		}
	}
	
	return err;
}

#endif //__LP64__


static NSPoint sCascadeOffset = NSZeroPoint;

OMCOutputWindowControllerRef
CreateOutputWindowController(const OutputWindowSettings &inSettings, OutputWindowHandler *inHandler)
{
	OMCOutputWindowController *controller = NULL;

	/*BOOL isOK =*/ NSApplicationLoad();

	@autoreleasepool
	{
		@try
		{
			if(inSettings.windowType == kOMCWindowRegular)
				controller = [[OMCOutputWindowController alloc] initWithWindowNibName:@"OMCOutputWindow"];
			else if(inSettings.windowType == kOMCWindowFloating || inSettings.windowType == kOMCWindowGlobalFloating)
				controller = [[OMCOutputWindowController alloc] initWithWindowNibName:@"OMCOutputPanel"];
			else if(inSettings.windowType == kOMCWindowCustom)
			{
				OMCCustomWindow *customWindow = [[OMCCustomWindow alloc] initWithSettings:&inSettings];
				[customWindow autorelease];
				controller = [[OMCOutputWindowController alloc] initWithWindow:customWindow];
			}
			else
				NSLog(@"Unsupported window type");
			
			if(controller != NULL)
			{
				[controller setup: &inSettings withHandler:inHandler];

		#ifndef __LP64__
				NSWindow *nsWindow = [controller window];
				if(nsWindow != NULL)
				{
					WindowRef carbonWindowRef = (WindowRef)[nsWindow windowRef];
					if(carbonWindowRef != NULL)
					{
						EventTypeSpec windowEvents[1];
						windowEvents[0].eventClass = kEventClassCommand;
						windowEvents[0].eventKind = kEventCommandUpdateStatus;
						if ( gOMCWindowCarbonEventHandlerUPP == NULL )
							gOMCWindowCarbonEventHandlerUPP = NewEventHandlerUPP( OMCWindowCarbonEventHandlerProc );
						/*OSStatus err =*/ InstallWindowEventHandler( carbonWindowRef,
												gOMCWindowCarbonEventHandlerUPP,
												GetEventTypeCount(windowEvents),
												windowEvents, NULL, NULL );
					}
				}
		#endif //__LP64__
			}
		}
		@catch (NSException *localException)
		{
			NSLog(@"CreateOutputWindowController received exception: %@", localException);
		}
	} //@autoreleasepool

	return (OMCOutputWindowControllerRef)controller;
}

void ReleaseOutputWindowController(OMCOutputWindowControllerRef inControllerRef)
{
	@autoreleasepool
	{
		@try
		{
			[(OMCOutputWindowController *)inControllerRef close];
			[(OMCOutputWindowController *)inControllerRef release];
		}
		@catch (NSException *localException)
		{
			NSLog(@"ReleaseOutputWindowController received exception: %@", localException);
		}
	} //@autoreleasepool
}

void OMCOutputWindowSetText(OMCOutputWindowControllerRef inControllerRef, CFStringRef inText)
{
	@autoreleasepool
	{
		@try
		{
			[((OMCOutputWindowController *)inControllerRef) setText:(NSString *)inText];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCOutputWindowSetText received exception: %@", localException);
		}
	} //@autoreleasepool
}

void OMCOutputWindowAppendText(OMCOutputWindowControllerRef inControllerRef, CFStringRef inText)
{
	@autoreleasepool
	{
		@try
		{
			[((OMCOutputWindowController *)inControllerRef) appendText:(NSString *)inText];
		}
		@catch (NSException *localException)
		{
			NSLog(@"OMCOutputWindowSetText received exception: %@", localException);
		}
	} //@autoreleasepool
}

void
ResetOutputWindowCascading()
{
	sCascadeOffset = NSZeroPoint;
}

@implementation OMCOutputWindowController

- (void)dealloc
{
	mHandler = NULL; //we are being deleted by our dying owner so mHandler is already invalid
/*  
	do not call [self window] in dealloc. Our refcount is 0 now and this will try to:
	- load the window
	- revive the controller and retain

	NSWindow *outputWindow = [self window];
	
	if(outputWindow != NULL)
	{
		[outputWindow close];//give it a chance to animate
	}
*/
	[super dealloc];
}

- (void)setup: (const OutputWindowSettings *)inSettings withHandler:(OutputWindowHandler *)inHandler
{
	mHandler = inHandler;
	NSWindow *outputWindow = [self window];

	if(outputWindow == NULL)
		return;
	
//	[outputWindow setDelegate:self]; //connected in nib
	
	if( textView == NULL )
	{//windows created from nib have the textView, the custom one does not
		NSRect textViewBounds = NSRectFromCGRect(inSettings->textBox);
		textView = [[NSTextView alloc] initWithFrame:textViewBounds];
		[textView setEditable:NO];
		[textView setDrawsBackground:NO];
		[textView setAlphaValue:1.0];
		[textView autorelease];//window will hold a reference
		NSView *contentView = [outputWindow contentView];
		[contentView addSubview:textView];
	}

	NSColor * backgroundColor = [NSColor colorWithDeviceRed: inSettings->backColor.red
													  green: inSettings->backColor.green
													   blue: inSettings->backColor.blue
													  alpha: inSettings->alpha];

	NSColor *textColor = [NSColor colorWithDeviceRed: inSettings->textColor.red
											   green: inSettings->textColor.green
												blue: inSettings->textColor.blue
											   alpha: inSettings->textColor.alpha];


	[textView setBackgroundColor:backgroundColor];
	[textView setTextColor:textColor];
	
	NSFont *theFont = NULL;
	if( (CFStringRef)inSettings->fontName != NULL )
		theFont = [NSFont fontWithName: (NSString*)(CFStringRef)inSettings->fontName size: inSettings->fontSize];
	
	if(theFont != NULL)
		[textView setFont:theFont];

	[self setWindowPosition:outputWindow withSettings:inSettings];
	
	if( (CFStringRef)inSettings->title != NULL )
		[outputWindow setTitle:(NSString *)(CFStringRef)inSettings->title];
	
	if(inSettings->windowType == kOMCWindowFloating)
		[outputWindow setLevel:NSFloatingWindowLevel];
	else if(inSettings->windowType == kOMCWindowGlobalFloating)
	{
		[outputWindow setLevel:kCGUtilityWindowLevel /*NSStatusWindowLevel*/];
		[outputWindow setHidesOnDeactivate:NO];
	}
	else if(inSettings->windowType == kOMCWindowCustom)
	{
		[outputWindow setLevel:kCGOverlayWindowLevel];
	}

	[outputWindow setOpaque:NO];
	
	if( [outputWindow isKindOfClass:[OMCWindow class]] ||
		[outputWindow isKindOfClass:[OMCPanel class]] ||
		[outputWindow isKindOfClass:[OMCCustomWindow class]] )
	{
		OMCWindow *omcWindow = (OMCWindow *)outputWindow;
		[omcWindow setFadeIn:inSettings->useFadeIn];
		[omcWindow setFadeOut:inSettings->useFadeOut];
		if(inSettings->useFadeIn)
		{
			[omcWindow  setAlphaValue: 0.0];
		}
	}

	[self showWindow:self];
	//[outputWindow makeKeyAndOrderFront:self];
	
}

- (void)setWindowPosition:(NSWindow *)inWindow withSettings: (const OutputWindowSettings *)inSettings
{	
	NSSize contentSize = { (CGFloat)inSettings->width, (CGFloat)inSettings->height };
	
	[inWindow setContentSize:contentSize];

	[self setShouldCascadeWindows:NO];

	NSRect windowFrame = [inWindow frame];

	NSScreen *mainScreen = [NSScreen mainScreen];
	NSRect screenRect = [mainScreen visibleFrame];

	NSPoint specialPosition = { inSettings->specialPosition.x, inSettings->specialPosition.y };
	NSPoint absolutePosition = { inSettings->topLeftPosition.x, inSettings->topLeftPosition.y };

	if(inSettings->positionMethod == kWindowAlertPositionOnMainScreen)
	{
		/* Apple Docs say:
		 Center the window horizontally and position it vertically on the screen that contains the menu bar,
		 such that about one-fifth of the screen is above it.
		*/
		
		specialPosition.x = 0.5;
		specialPosition.y = -1.0;
		absolutePosition.y = screenRect.origin.y + screenRect.size.height * 4.0/5.0 - windowFrame.size.height;//bottom of the window
	}
	else if(inSettings->positionMethod == kWindowCenterOnMainScreen)
	{
		specialPosition.x = 0.5;
		specialPosition.y = 0.5;
	}
	else if(inSettings->positionMethod == kWindowCascadeOnMainScreen)
	{
		if( (sCascadeOffset.x == 0.0) && (sCascadeOffset.y == 0.0) )
		{//not initialized yet
			absolutePosition.x = screenRect.origin.x;
			absolutePosition.y = screenRect.origin.y + screenRect.size.height - windowFrame.size.height;//bottom of the window
			if( (absolutePosition.y + windowFrame.size.height) < screenRect.origin.y )
				absolutePosition.y = screenRect.origin.y - windowFrame.size.height + 20;//winodw top visible at the bottom of the screen
			[inWindow setFrameOrigin:absolutePosition];
		}
		
		sCascadeOffset = [inWindow cascadeTopLeftFromPoint:sCascadeOffset];
		/*
		//[self setShouldCascadeWindows:YES];//this is useless because we don't have documents managed
		*/
		return;
	}
	else
	{//absolute position
		absolutePosition.x += screenRect.origin.x;
		absolutePosition.y = screenRect.origin.y + screenRect.size.height - absolutePosition.y - windowFrame.size.height;//bottom of the window
		if( (absolutePosition.y + windowFrame.size.height) < screenRect.origin.y )
			absolutePosition.y = screenRect.origin.y - windowFrame.size.height + 20;//winodw top visible at the bottom of the screen
	}

	if(specialPosition.y >= 0.0f)
	{
		if(specialPosition.y > 1.0f)
			specialPosition.y = 1.0f;
		
		//place the center in desired screen location:
		absolutePosition.y = screenRect.origin.y + screenRect.size.height * (1.0-specialPosition.y) - windowFrame.size.height/2.0;//bottom of the window
		
		if( absolutePosition.y < screenRect.origin.y )
			absolutePosition.y = screenRect.origin.y;

		if( (absolutePosition.y + windowFrame.size.height) > (screenRect.origin.y + screenRect.size.height) )//over the top?
			absolutePosition.y = screenRect.origin.y + screenRect.size.height - windowFrame.size.height;
	}
	
	if(specialPosition.x >= 0.0f)
	{
		if(specialPosition.x > 1.0f)
			specialPosition.x = 1.0f;
		
		//place the center in desired screen location:
		absolutePosition.x = screenRect.origin.x + screenRect.size.width * specialPosition.x - windowFrame.size.width/2.0;
		
		if( (absolutePosition.x + windowFrame.size.width) > (screenRect.origin.x + screenRect.size.width) )
			absolutePosition.x = screenRect.origin.x + screenRect.size.width - windowFrame.size.width;
		
		if( absolutePosition.x < screenRect.origin.x )
			absolutePosition.x = screenRect.origin.x;
	}
	
	[inWindow setFrameOrigin:absolutePosition];
}

- (void)setText:(NSString *)inText
{
	if(inText != NULL)
		[textView setString:inText];
}

- (void)appendText:(NSString *)inText
{
	if(inText != NULL)
		[textView replaceCharactersInRange:NSMakeRange([[textView string] length],0) withString:inText];
}

//NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification
{
	if(mHandler != NULL)
	{//the handler is actually our owner and it will release us when it dies.
	//we just need to let it know that we are ready
		mHandler->ScheduleSelfDestruction(0.0);
		mHandler = NULL;
	}
}

/*
- (void)windowWillLoad
{
	NSLog(@"OMCOutputWindowController windowWillLoad");
}

- (void)windowDidLoad
{
	NSLog(@"OMCOutputWindowController windowDidLoad");
}
*/

@end
