//
//  OMCNibWindowController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#include <CoreServices/CoreServices.h>
#import <Quartz/Quartz.h>
#import <PDFKit/PDFKit.h>
#import "OMCNibWindowController.h"
#import "OMCPopUpButton.h"
#include "OnMyCommand.h"
#include "ACFDict.h"
#include "OMCNibDialog.h"
#include "CommandRuntimeData.h"
#include <vector>
#import "OMCTableViewController.h"
#import "OMCTableView.h"
#import "OMCComboBox.h" //for shouldExecutAction
#import "OMCButton.h" //for droppedItems
#import "OMCWebKitView.h"
#import "OMCView.h"


@implementation OMCNibWindowController


- (id)initWithOmc:(OnMyCommandCM *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
{
   self = [super initWithOmc:inOmc commandRuntimeData:inCommandRuntimeData];
	if(self == nil)
		return nil;
    
    mOMCDialogProxy.Adopt( new OMCNibDialog() );
    mOMCDialogProxy->SetControlAccessor((__bridge void *)self);
    self->mCommandRuntimeData->SetAssociatedDialogUUID(mOMCDialogProxy->GetDialogUUID());

	CommandDescription &currCommand = self->mPlugin->GetCurrentCommand();

	ACFDict params( currCommand.nibDialog );
    CFObj<CFStringRef> nibName;
	params.CopyValue( CFSTR("NIB_NAME"), nibName );

	if(nibName == nullptr)
		return self;//no nib name, no dialog
    
    NSString *__strong dialogNibName = (NSString *)CFBridgingRelease(nibName.Detach());

//	We can't get the window by name from nib in Cocoa
//	CFStringRef nibWindowName = NULL;
//	params.GetValue( CFSTR("WINDOW_NAME"), nibWindowName );

    CFObj<CFStringRef> initSubcommandID;
	params.CopyValue( CFSTR("INIT_SUBCOMMAND_ID"), initSubcommandID );
    self.dialogInitSubcommandID = (NSString *)CFBridgingRelease(initSubcommandID.Detach());
    
    CFObj<CFStringRef> endOKSubcommandID;
	params.CopyValue( CFSTR("END_OK_SUBCOMMAND_ID"), endOKSubcommandID );
    self.endOKSubcommandID = (NSString *)CFBridgingRelease(endOKSubcommandID.Detach());

    CFObj<CFStringRef> endCancelSubcommandID;
	params.CopyValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), endCancelSubcommandID );
    self.endCancelSubcommandID = (NSString *)CFBridgingRelease(endCancelSubcommandID.Detach());

	Boolean isBlocking = true;//default is modal
	params.GetValue( CFSTR("IS_BLOCKING"), isBlocking );
	mIsModal = isBlocking;

	//now we need to find out where our nib is

	if(mExternBundleRef != NULL)
	{//extern bundle exists? most likely it will be there
		CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( mExternBundleRef ) );
		if(bundleURL != NULL)
		{
			CFObj<CFStringRef> absolutePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
			if(absolutePath != nullptr)
			{
                [self findNib:dialogNibName forBundlePath:(__bridge NSString *)absolutePath.Get()];
			}
		}
	}

	if(_omcCocoaNib == nil)
	{//still not found, check main default bundle
        [self findNib:dialogNibName forBundlePath:NULL];
	}

	if(_omcCocoaNib == nil)
	{
		CFBundleRef frameworkBundleRef = mPlugin->GetBundleRef();
#if DEBUG
        NSLog(@"[OMCNibWindowController initWithOmc], frameworkBundleRef=%@", (__bridge id)frameworkBundleRef);
		CFShow(frameworkBundleRef);
#endif
		if(frameworkBundleRef != NULL)
		{
			CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( frameworkBundleRef ) );
			if(bundleURL != NULL)
			{
				CFObj<CFStringRef> absolutePath = CreatePathFromCFURL(bundleURL, kEscapeNone);
				if(absolutePath != nullptr)
				{
                    [self findNib:dialogNibName forBundlePath:(__bridge NSString *)absolutePath.Get()];
				}
			}
		}
	}

	if(_omcCocoaNib != nil)
	{
        self.window = [_omcCocoaNib getFirstWindow];
		if(self.window != nil)
		{
			[self.window setReleasedWhenClosed:NO];//we will release it when unloading the nib

            NSView *contentView = [self.window contentView];
			if(contentView != nil)
			{
				[self initSubview:contentView];
			}
			
            OneObjProperties *associatedObj = mCommandRuntimeData->GetAssociatedObject();
            if(associatedObj != nullptr)
            {
                CFURLRef fileURL = associatedObj->url.Get();
                if(fileURL != NULL)
                {
                    NSURL *__weak associatedFileURL = (__bridge NSURL *)(fileURL);
                    self.window.representedURL = associatedFileURL;
                    [self.window setTitleWithRepresentedFilename:associatedFileURL.path];
                    // associating file with a window makes it appear as a document for user
                    // we may arrive here via different ways which may not end up calling `noteNewRecentDocumentURL:`
                    // but calling it twice on the same URL is not a problem
                    [NSDocumentController.sharedDocumentController noteNewRecentDocumentURL:associatedFileURL];
                }
            }
            
			[self.window setDelegate: self];
		}
		else
			NSLog(@"Cocoa nib file does not contain a window");
	}
	else
		NSLog(@"Cannot find Cocoa nib file");


    return self;
}

- (Boolean)findNib:(NSString *)inNibName forBundlePath:(NSString *)inPath
{
	if(inPath != nil)
	{//bundle with explicit path
		NSBundle *myBundle = [NSBundle bundleWithPath:inPath];
		if(myBundle != NULL)
		{
			NSNib *myNib = [[NSNib alloc] initWithNibNamed:inNibName bundle:myBundle];
			if(myNib != nil)
			{
                self.omcCocoaNib = [[OMCCocoaNib alloc] initWithNib:myNib];
			}
		}
	}
	else
	{//main bundle
		NSNib *myNib = [[NSNib alloc] initWithNibNamed:inNibName bundle:nil];
		if(myNib != nil)
		{
			self.omcCocoaNib = [[OMCCocoaNib alloc] initWithNib:myNib];
		}
	}
	return (self.omcCocoaNib != nil);
}

- (void)dealloc
{
	OMCNibDialog *nibDialog = (OMCNibDialog *)mOMCDialogProxy.Get();
	if(nibDialog != nullptr)
		nibDialog->SetControlAccessor(nil);
	
	if(self.window != nil)
	{
		//the window may outlive us
		//we are dying we need to unregister all delegates, targets, observers, etc
		id contentViewObject = [self.window contentView];
		if( (contentViewObject != nil) && [contentViewObject isKindOfClass:[NSView class] ] )
		{
			[self resetSubview: (NSView*)contentViewObject];
		}
	
		[self.window setDelegate:nil];//we are dying
	}
}

- (void) initSubview:(NSView *)inView
{
	//init self - add self as target and action handler for all controls

	if( [inView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)inView;
		//each table view has its own controller object which serves as data source and delegate
		OMCTableViewController *tableController = [[OMCTableViewController alloc] initWithTableView:myTable dialogController:self];

		[myTable setDataSource:tableController];
		[myTable setDelegate:tableController];

		//the table DOES NOT retain its data source nor delegate!
		[self keepItem: tableController];//we retain all controllers and they will be released when this dialog controller is released

		if( [myTable target] == nil )//don't override targets preset in IB
		{
			[myTable setTarget:self];
			//[myTable setAction:@selector(handleAction:)];
			[myTable setDoubleAction:@selector(handleDoubleClickAction:)];
		}
	}
	else if( [inView isKindOfClass:[NSControl class] ] )
	{//for controls - faster
		NSControl *myControl = (NSControl *)inView;
		if( [myControl target] == nil )//don't override targets preset in IB
		{
			[myControl setTarget:self];
			[myControl setAction:@selector(handleAction:)];
		}
	}
	else
	{//for non-controls which may support target/action  - slower
		bool setTarget = true;
		if( [inView respondsToSelector:@selector(target)] )
			if( [inView performSelector:@selector(target)] != nil )//don't override targets preset in IB
				setTarget = false;

		if(setTarget)
		{
			if( [inView respondsToSelector:@selector(setTarget:)] )
			{
				[inView performSelector:@selector(setTarget:) withObject:self];
                
                if ([inView conformsToProtocol:@protocol(OMCActionProtocol)])
                {
                    id<OMCActionProtocol> actionView = (id<OMCActionProtocol>)inView;
                    //if( [inView respondsToSelector:@selector(setAction:)] )
                    [actionView setAction:@selector(handleAction:)]; //only if target is ourselves we can set action
                }
			}
		}
        
        if([inView conformsToProtocol:@protocol(OMCViewSetupProtocol)])
        {
            id<OMCViewSetupProtocol> viewToSetup = (id<OMCViewSetupProtocol>)inView;
            if(mCommandRuntimeData != nullptr)
            {
                CFDictionaryRef envVars = mPlugin->CreateEnvironmentVariablesDict(NULL, *mCommandRuntimeData);
                NSDictionary *__strong envVarsDict = CFBridgingRelease(envVars); // transfer ownership to strong var
                [viewToSetup setupWithEnvironmentVariables:envVarsDict];
            }
        }
	}

	if([inView isKindOfClass:[NSTabView class]])
	{//init tabs view recursively
        for(NSTabViewItem *oneTab in ((NSTabView*)inView).tabViewItems)
        {
            NSView *tabView = [oneTab view];
            if(tabView != nil)
            {
                [self initSubview:tabView];
            }
        }
	}
	else if(inView != nil)
	{
		//init subviews recursively
        for(NSView *subView in inView.subviews)
        {
            [self initSubview:subView];
        }
	}
}

- (void) resetSubview:(NSView *)inView
{
	//reset self - remove self as target and action handler for all controls
	if( [inView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)inView;
		[myTable setDataSource:NULL];
		[myTable setDelegate:NULL];

		if( [myTable target] == self )//don't override targets preset in IB
		{
			[myTable setTarget:NULL];
			[myTable setAction:NULL];
			[myTable setDoubleAction:NULL];
		}
	}
	else if( [inView isKindOfClass:[NSControl class] ] )
	{
		NSControl *myControl = (NSControl *)inView;
		if( [myControl target] == self )//don't override targets preset in IB
		{
			[myControl setTarget:NULL];
			[myControl setAction:NULL];
		}
	}

	if([inView isKindOfClass:[NSTabView class] ])
	{//reset tabs view recursively
        for(NSTabViewItem *oneTab in ((NSTabView*)inView).tabViewItems)
        {
            NSView *tabView = [oneTab view];
            if(tabView != nil)
            {
                [self resetSubview:tabView];
            }
        }
	}
	else if(inView != nil)
	{
		//reset subviews recursively
        for(NSView *subView in inView.subviews)
        {
            [self resetSubview:subView];
        }
	}
}

// may return NSView or NSCell
- (id)findControlOrViewWithID:(NSString *)inControlID
{
	id contentViewObject = [self.window contentView];
	if(contentViewObject != nil)
	{
		NSView *contentView = (NSView*)contentViewObject;
		return [self findViewInParent:contentView forControlID:inControlID];
	}
	return nil;
}

//may return NSView or NSCell
- (id)findViewInParent:(NSView *)inParentView forControlID:(NSString *)inControlID
{
    if(inControlID == nil)
    {
        return nil;
    }

	NSString *controlID = nil;
    NSInteger tagNum = [inParentView tag];
    if(tagNum > 0)
    {
        controlID = [NSString stringWithFormat:@"%ld", (long)tagNum];
    }

	if((controlID != nil) && [controlID isEqualToString:inControlID])
    {
        return inParentView;
    }

    if([inParentView respondsToSelector:@selector(identifier)])
    {
        controlID = [inParentView identifier];
        if((controlID != nil) && [controlID isEqualToString:inControlID])
        {
            return inParentView;
        }
    }

	if([inParentView isKindOfClass:[NSTabView class]])
	{//search tabs view recursively
        for(NSTabViewItem *oneTab in ((NSTabView*)inParentView).tabViewItems)
        {
            NSView *tabView = [oneTab view];
            if(tabView != nil)
            {
                NSView *resultView = [self findViewInParent:tabView forControlID:inControlID];
                if(resultView != nil)
                {
                    return resultView;
                }
            }
        }
	}
	else if(inParentView != nil)
	{
		//search subviews recursively
        for(NSView *subView in inParentView.subviews)
        {
            NSView *resultView = [self findViewInParent:subView forControlID:inControlID];
            if(resultView != nil)
            {
                return resultView;
            }
        }
	}
    
	return nil;
}

// private helper
-(CFMutableDictionaryRef)storeValue:(nullable id)inValue forControlID:(NSString*)controlID forPart:(NSString *)controlPart inControlValues:(NSMutableDictionary *)ioControlValues
{
	CFObj<CFMutableDictionaryRef> partIdAndValueDict;
	id partValues = ioControlValues[controlID];
	if(partValues == nil)
	{
		partIdAndValueDict.Adopt( ::CFDictionaryCreateMutable(
					kCFAllocatorDefault,
					0,
					&kCFTypeDictionaryKeyCallBacks,
					&kCFTypeDictionaryValueCallBacks), kCFObjDontRetain );

        [ioControlValues setValue:(__bridge id)(CFMutableDictionaryRef)partIdAndValueDict forKey:controlID];
	}
	else
	{
        partIdAndValueDict.Adopt((__bridge CFMutableDictionaryRef)partValues, kCFObjRetain);
	}

    if(inValue != nil)
    {
        CFDictionarySetValue(partIdAndValueDict, (const void *)controlPart, (const void *)inValue);
    }
    else
    {
        CFDictionaryRemoveValue(partIdAndValueDict, (const void *)controlPart);
    }
    
	return partIdAndValueDict;
}

// private helper
-(void)readControlValueForID:(NSString *)controlID inValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties forView:(NSView *)inView withIterator:(SelectionIterator *)inSelIterator
{
	NSUInteger columnCount = 0;
	if( [inView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)inView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
		{
			columnCount = [myDelegate columnCount];
			//regular controls only use column index 0
			//tables use columns 1..N  with 0 meaning all columns combined
			for(NSInteger columnIndex = 0; columnIndex <= columnCount; columnIndex++)
			{
				id controlValue = [myDelegate selectionValueForColumn:columnIndex withIterator:inSelIterator];
                NSString *columnIndexStr = [NSString stringWithFormat:@"%ld", columnIndex];
                [self storeValue:controlValue forControlID:controlID forPart:columnIndexStr inControlValues:ioControlValues];
			}
		}
	}
	else if( [inView isKindOfClass:[OMCWebKitView class]])
	{
		//special invalid part name "@" indicates it is a WebView to distinguish from table view
		CFMutableDictionaryRef webViewPartValues = [self storeValue:@"" forControlID:controlID forPart:@"@" inControlValues:ioControlValues];
		OMCWebKitView *omcWKView = (OMCWebKitView *)inView;
        [omcWKView storeElementValuesIn:(__bridge NSMutableDictionary *)webViewPartValues];
	}
	else
	{
		id controlValue = [self controlValue:inView forPart:@"0" withIterator:inSelIterator];
        [self storeValue:controlValue forControlID:controlID forPart:@"0" inControlValues:ioControlValues];
	}

	CFObj<CFDictionaryRef> customProperties([self copyControlProperties:inView]);
	if(customProperties != NULL)
        [ioCustomProperties setValue:(__bridge id)(CFDictionaryRef)customProperties forKey:controlID];
}

//internal implementation
-(void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties inView:(NSView *)inView withIterator:(SelectionIterator *)inSelIterator
{
    if(inView == nil)
        return;

	//in general a view with subviews should not have a value but we check all non-empty, non-zero IDs
	NSString *controlID = nil;
	NSInteger tagNum = [inView tag];
	if(tagNum > 0)
		controlID = [NSString stringWithFormat:@"%ld", (long)tagNum];

	static NSCharacterSet *nonAlphanumericCharacterSet = [[NSCharacterSet alphanumericCharacterSet] invertedSet];

	if((controlID == nil) && [inView respondsToSelector:@selector(identifier)])
	{
		controlID = [inView identifier];
		
		// AppKit adds unique identifiers to controls which have no id assigned in the nib
		// We see IDs like _NS:36 here
		// Apple header says slash '/', backslash '\', and colon ':' characters are reserved
		// so when we encounter them, we can skip the control as not interesting
		// but in general for OMC we declare that a presence of any non-alphanumeric character invalidates the ID
		if(controlID != nil)
		{
			NSRange illegalCharRange = [controlID rangeOfCharacterFromSet:nonAlphanumericCharacterSet];
			//Returns a range of {NSNotFound, 0} if none of the characters in aSet are found.
			if(illegalCharRange.location != NSNotFound)
				controlID = nil; //something found, ID not valid
		}
	}

	if((controlID != nil) && ([controlID length] > 0) && ![controlID isEqualToString:@"0"])
	{
		[self readControlValueForID:controlID inValues:ioControlValues andProperties:ioCustomProperties forView:inView withIterator:inSelIterator];
	}

	if([inView isKindOfClass:[NSTabView class]])
	{//search tabs view recursively
        for(NSTabViewItem *oneTab in ((NSTabView*)inView).tabViewItems)
        {
            NSView *tabView = [oneTab view];
            if(tabView != nil)
            {
                [self allControlValues:ioControlValues andProperties:ioCustomProperties inView:tabView withIterator:inSelIterator];
            }
        }
	}
	else if(inView != nil)
	{
		//search subviews recursively
        for(NSView *subView in inView.subviews)
        {
            [self allControlValues:ioControlValues andProperties:ioCustomProperties inView:subView withIterator:inSelIterator];
        }
	}
}

// public API
-(void)allControlValues:(NSMutableDictionary *)ioControlValues andProperties:(NSMutableDictionary *)ioCustomProperties withIterator:(SelectionIterator *)inSelIterator
{
	id contentViewObject = [self.window contentView];
	if( (contentViewObject != nil) && [contentViewObject isKindOfClass:[NSView class] ] )
	{
		[self allControlValues:ioControlValues andProperties:ioCustomProperties inView:(NSView*)contentViewObject withIterator:inSelIterator];
	}
}

-(CFDictionaryRef)copyControlProperties:(id)controlOrView
{
	CFMutableDictionaryRef outDict = NULL;
	NSString *escapingMode = nil;
	if( [controlOrView respondsToSelector:@selector(escapingMode)] )
		escapingMode = [controlOrView escapingMode];

	NSString *combinedSelectionPrefix = nil;
	if( [controlOrView respondsToSelector:@selector(combinedSelectionPrefix)] )
		combinedSelectionPrefix = [controlOrView combinedSelectionPrefix];

	NSString *combinedSelectionSuffix = nil;
	if( [controlOrView respondsToSelector:@selector(combinedSelectionSuffix)] )
		combinedSelectionSuffix = [controlOrView combinedSelectionSuffix];

	NSString *combinedSelectionSeparator = nil;
	if( [controlOrView respondsToSelector:@selector(combinedSelectionSeparator)] )
		combinedSelectionSeparator = [controlOrView combinedSelectionSeparator];

	if( (escapingMode != nil) ||
		(combinedSelectionPrefix != nil) ||
		(combinedSelectionSuffix != nil) ||
		(combinedSelectionSeparator != nil) )
	{
		outDict = ::CFDictionaryCreateMutable(
										kCFAllocatorDefault,
										0,
										NULL,//keyCallBacks,
										&kCFTypeDictionaryValueCallBacks );
		if(outDict != NULL)
		{
			if(escapingMode != nil)
				::CFDictionarySetValue( outDict,
										(const void *)kCustomEscapeMethodKey,
                                       (const void *)(__bridge CFStringRef)escapingMode);
			
			if(combinedSelectionPrefix != nil)
				::CFDictionarySetValue( outDict,
										(const void *)kCustomPrefixKey,
                                       (const void *)(__bridge CFStringRef)combinedSelectionPrefix);

			if(combinedSelectionSuffix != nil)
				::CFDictionarySetValue( outDict,
										(const void *)kCustomSuffixKey,
                                       (const void *)(__bridge CFStringRef)combinedSelectionSuffix);

			if(combinedSelectionSeparator != nil)
				::CFDictionarySetValue( outDict,
										(const void *)kCustomSeparatorKey,
                                       (const void *)(__bridge CFStringRef)combinedSelectionSeparator);
		}
	}
	return outDict;
}

- (id)controlValue:(id)controlOrView forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator
{
	if( [controlOrView isKindOfClass:[NSPopUpButton class]] && ![controlOrView isKindOfClass:[OMCPopUpButton class]] )
	{
		NSPopUpButton *myPopup = (NSPopUpButton *)controlOrView;
		NSInteger itemIndex = [myPopup indexOfSelectedItem] + 1;//0-based to 1-based
		return [NSString stringWithFormat: @"%ld", (long)itemIndex];
	}
	else if([controlOrView isKindOfClass:[NSPathControl class]] || [controlOrView isKindOfClass:[NSPathCell class]])
	{
		NSURL *fileURL = [controlOrView URL];
		if(fileURL != nil)
		{
			NSString *filePath = [fileURL path];
			if(filePath != nil)
				return filePath;
		}
		return [controlOrView stringValue];
	}
	else if( [controlOrView isKindOfClass:[NSText class]] )
	{
		NSText *myText = (NSText *)controlOrView;
		return [myText string];
	}
	else if( [controlOrView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)controlOrView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
		{
			NSInteger columnIndex = [inControlPart integerValue];
			if( (inSelIterator != NULL) && SelectionIterator_IsAllRows(inSelIterator) )
				return [myDelegate allRowsForColumn:columnIndex];
			else
				return [myDelegate selectionValueForColumn:columnIndex withIterator:inSelIterator];
		}
	}

	//nothing else produced a value, try "stringValue"
	if( [controlOrView respondsToSelector:@selector(stringValue)] )
	{
		return [controlOrView stringValue];//OMC controls do their mappings internally and return proper string
	}
	return nil;
}

//inControlPart can be a column index for table or element ID for WebView
- (id)controlValueForID:(NSString *)inControlID forPart:(NSString *)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if(controlOrView != nil)
	{
		if(outCustomProperties != NULL)
			*outCustomProperties = [self copyControlProperties:controlOrView];
		return [self controlValue:controlOrView forPart:inControlPart withIterator:inSelIterator];
	}
	return nil;
}

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( controlOrView != nil )
	{
		if( [controlOrView isKindOfClass:[NSPopUpButton class]] )
		{
			NSPopUpButton *myPopup = (NSPopUpButton *)controlOrView;
			NSScanner *strScanner = [NSScanner scannerWithString:inValue];
			int intValue = -1;
			//0-based index for popup menu items
			if( [strScanner scanInt:&intValue] && (intValue > 0) && (intValue <= [myPopup numberOfItems]) )
				[myPopup selectItemAtIndex:intValue-1];//successful conversion to number in range
			else
				[myPopup selectItemWithTitle:inValue];
		}
		else if([controlOrView isKindOfClass:[NSPathControl class]] || [controlOrView isKindOfClass:[NSPathCell class]])
		{
			NSURL *fileURL = [NSURL fileURLWithPath:inValue];
			if(fileURL != nil)
				[controlOrView setURL:fileURL];
		}
		else if( [controlOrView respondsToSelector:@selector(setStringValue:)] )
		{
			[controlOrView setStringValue:inValue];//OMC controls do their mappings internally
		}
		else if( [controlOrView isKindOfClass:[NSText class]] )
		{
			NSText *myText = (NSText *)controlOrView;
			[myText setString:inValue];
		}
	}
}

- (void)setControlEnabled:(BOOL)enabled forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if(controlOrView != nil)
	{
		if( [controlOrView respondsToSelector:@selector(setEnabled:)] )
			[(NSControl *)controlOrView setEnabled:enabled];
	}
}

- (void)setControlVisible:(BOOL)visible forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView respondsToSelector:@selector(setHidden:)] )
		[controlOrView setHidden:(!visible)];
}

- (void)removeAllListItemsForControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( controlOrView != NULL )
	{
		if( [controlOrView isKindOfClass:[NSPopUpButton class]] )
		{
			[(NSPopUpButton *)controlOrView removeAllItems];
		}
		else if( [controlOrView isKindOfClass:[NSComboBox class]] )
		{
			[(NSComboBox *)controlOrView removeAllItems];
		}
	}
}

- (void)setListItems:(CFArrayRef)items forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( controlOrView != NULL )
	{
		CFIndex itemCount = ::CFArrayGetCount(items);
		if( [controlOrView isKindOfClass:[NSPopUpButton class]] )
		{
			NSPopUpButton *myPopupButton = (NSPopUpButton *)controlOrView;
			[myPopupButton removeAllItems];
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(items, i) );
				if(oneString != NULL)
					[myPopupButton addItemWithTitle:(__bridge NSString *)oneString];
			}
		}
		else if( [controlOrView isKindOfClass:[NSComboBox class]] )
		{
			NSComboBox *myCombo = (NSComboBox *)controlOrView;
			[myCombo removeAllItems];
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(items, i) );
				if(oneString != NULL)
					[myCombo addItemWithObjectValue:(__bridge NSString *)oneString];
			}
		}
	}
}

- (void)appendListItems:(CFArrayRef)items forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( controlOrView != NULL )
	{
		CFIndex itemCount = ::CFArrayGetCount(items);
		if( [controlOrView isKindOfClass:[NSPopUpButton class]] )
		{
			NSPopUpButton *myPopupButton = (NSPopUpButton *)controlOrView;
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(items, i) );
				if(oneString != NULL)
					[myPopupButton addItemWithTitle:(__bridge NSString *)oneString];
			}
		}
		else if( [controlOrView isKindOfClass:[NSComboBox class]] )
		{
			NSComboBox *myCombo = (NSComboBox *)controlOrView;
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( ::CFArrayGetValueAtIndex(items, i) );
				if(oneString != NULL)
					[myCombo addItemWithObjectValue:(__bridge NSString *)oneString];
			}
		}
	}
}

- (void)emptyTableForControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)controlOrView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
		{
			[myDelegate removeRows];
			//intentional no reload here
		}
	}
}

- (void)removeTableRowsForControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)controlOrView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
		{
			[myDelegate removeRows];
			[myDelegate reloadData];
		}
	}
}

- (void)setTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)controlOrView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
		{
			[myDelegate removeRows];
			[myDelegate addRows:rows];
			[myDelegate reloadData];
		}
	}
}

- (void)addTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)controlOrView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
		{
			[myDelegate addRows:rows];
			[myDelegate reloadData];
		}
	}
}

- (void)setTableColumns:(CFArrayRef)columns forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)controlOrView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
			[myDelegate setColumns:(__bridge NSArray *)columns];
	}
}

- (void)setTableColumnWidths:(CFArrayRef)widths forControlID:(NSString *)inControlID
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)controlOrView;
		id myDelegate = [myTable delegate];
		if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
			[myDelegate setColumnWidths:(__bridge NSArray *)widths];
	}
}

- (void)selectControlWithID:(NSString *)inControlID
{
	NSView *controlOrView = [self findControlOrViewWithID:inControlID];
	if(controlOrView != nil)
		[self.window makeFirstResponder:controlOrView];
}

- (void)setCommandID:(NSString *)commandID forControlID:(NSString *)inControlID
{
	NSView *controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView respondsToSelector:@selector(setCommandID:)] )
		[controlOrView performSelector:@selector(setCommandID:) withObject:commandID];
}

- (void)moveControlWithID:(NSString *)inControlID toPosition:(NSPoint)position
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSView class]] )
	{
		float viewHeight = NSHeight([controlOrView bounds]);
		NSView *superView = [controlOrView superview];
		float superHeight = NSHeight([superView bounds]);
		float bottomOrigin = superHeight - viewHeight - position.y;
		[controlOrView setFrameOrigin: NSMakePoint(position.x, bottomOrigin) ];
		[controlOrView setNeedsDisplay:YES];
	}
}

- (void)resizeControlWithID:(NSString *)inControlID toSize:(NSSize)size
{
	id controlOrView = [self findControlOrViewWithID:inControlID];
	if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSView class]] )
	{
		[controlOrView setFrameSize:size];
		[controlOrView setNeedsDisplay:YES];
	}
}

- (void)scrollControlWithID:(NSString *)inControlID toPosition:(NSPoint)position
{
	id myView = [self findControlOrViewWithID:inControlID];
	if( myView == nil )
		return;

	NSClipView *clipView = nil;
	NSView *docView = nil;
	if( [myView isKindOfClass:[NSScrollView class] ] )
	{//we target scroll view
		docView = [(NSScrollView *)myView documentView];
		NSView *superView = [docView superview];
		if( [superView isKindOfClass:[NSClipView class] ] )
			clipView = (NSClipView *)superView;
	}
	else if( [myView isKindOfClass:[PDFView class] ] )
	{//multiple view hierarchy freak
		docView = [(PDFView *)myView documentView];
		//the superview is matte view
		NSView *matteView = [docView superview];

		NSView *superView = nil;
		if(matteView != nil)
			superView = [matteView superview];//get superview of matte view - this should be clipping view

		if( (superView != nil) && [superView isKindOfClass:[NSClipView class] ] )
		{
			docView = matteView;
			clipView = (NSClipView *)superView;
		}
	}
	else if( [myView isKindOfClass:[IKImageView class]] )
	{
		IKImageView *imgView = (IKImageView *)myView;
		NSSize imgSize = [imgView imageSize];

		docView = myView;
		NSView *superView = [docView superview];
		if( [superView isKindOfClass:[NSClipView class] ] )
			clipView = (NSClipView *)superView;

		if( ![docView isFlipped] )
		{
			float superHeight = NSHeight([clipView bounds]);
			position.y = /*NSMaxY([myView frame])*/imgSize.height - superHeight - position.y;
		}

		[docView scrollPoint:position];
		clipView = nil;//set to null to prevent scrolling attempts below
	}
	else if( [myView isKindOfClass:[NSView class]] )
	{//we target document view which is inside clip view, which in turn is in NSScrollView
		docView = myView;
		NSView *superView = [docView superview];
		if( [superView isKindOfClass:[NSClipView class] ] )
			clipView = (NSClipView *)superView;
	}

	if(clipView != nil)
	{
		if( ![docView isFlipped] )
		{
			float superHeight = NSHeight([clipView bounds]);
			float viewHeight = NSHeight([docView bounds]);
			position.y = /*NSMaxY([myView frame])*/viewHeight - superHeight - position.y;
		}

		[docView scrollPoint:position];
	}
}

- (void)invokeMessagesForControlID:(NSString *)inControlID messages:(CFArrayRef)messages
{
	id messageTarget = [self findControlOrViewWithID:inControlID];
	if(messageTarget != nil)
		[self invokeMessages:messages onTarget:messageTarget];
}

- (void)handleAction:(id)sender
{
	NSString *commandID = nil;
	if( [sender respondsToSelector:@selector(commandID)] )
		commandID = [sender commandID];
	
	if(commandID == NULL)
		return;

	if( [sender respondsToSelector:@selector(shouldExecuteAction)] &&
		![sender shouldExecuteAction] )
		return;

	id droppedItems = nil;
	if( [sender respondsToSelector:@selector(droppedItems)] )
        droppedItems = [sender droppedItems];

	[self dispatchCommand:commandID withContext:(__bridge CFTypeRef)droppedItems];
	
	if(droppedItems != nil)
		[sender setDroppedItems:nil]; //reset dropped itmes to nil so they will not persist for next action
}

- (void)handleDoubleClickAction:(id)sender
{
	NSString *commandID = NULL;
	if( [sender respondsToSelector:@selector(doubleClickCommandID)] )
	{
		commandID = [sender doubleClickCommandID];
	}
	
	if(commandID != NULL)
    {
        BOOL executeCommand = YES;
        // for table view only execute double click command if there is a valid selection
        if([sender isKindOfClass:[NSTableView class]])
        {
            NSTableView *tableView = (NSTableView *)sender;
            NSIndexSet *indexSet = [tableView selectedRowIndexes];
            executeCommand = (indexSet != NULL) && (indexSet.count > 0);
        }
        
        if(executeCommand)
        {
            [self dispatchCommand:commandID withContext:NULL];
        }
    }
}

//call only when you have non-null inIteratorParams
-(SelectionIterator *)createSelectionIterator:(CFDictionaryRef)inIteratorParams
{
	ACFDict params( inIteratorParams );
	
	NSString *controlID = NULL;

	CFTypeRef controlIDRef = NULL;
	Boolean keyExists = params.GetValue( CFSTR("CONTROL_ID"), controlIDRef );
	if( keyExists && (controlIDRef != NULL) )
	{
		if( CFNumberGetTypeID() == CFGetTypeID(controlIDRef) )
		{
			CFIndex controlIDNum = 0;
			::CFNumberGetValue( (CFNumberRef)controlIDRef, kCFNumberCFIndexType, &controlIDNum );
			if(controlIDNum != 0)
				controlID = [NSString stringWithFormat:@"%d", (int)controlIDNum];
		}
		else if(CFStringGetTypeID() == CFGetTypeID(controlIDRef) )
		{
            CFRetain(controlIDRef);
            controlID = (NSString *)CFBridgingRelease(controlIDRef);
		}
	}

	if(controlID != NULL)
	{		
		id foundView = [self findControlOrViewWithID:controlID];
		if( (foundView != NULL) && [foundView isKindOfClass:[NSTableView class]] )
		{
			NSTableView *tableView = (NSTableView *)foundView;
			NSIndexSet *indexSet = [tableView selectedRowIndexes];
			if(indexSet != NULL)
			{
				NSUInteger selectedRowsCount = [indexSet count];
				NSUInteger *selectedRows = (NSUInteger *)calloc(selectedRowsCount, sizeof(NSUInteger));//sel iterator takes ownership
				[indexSet getIndexes:selectedRows maxCount:selectedRowsCount inIndexRange:NULL];
			
				Boolean isReverseIter = false;
				params.GetValue( CFSTR("IS_REVERSE"), isReverseIter );
				if( isReverseIter && (selectedRowsCount > 1) )
				{
					NSUInteger temp;
					NSUInteger halfCount = selectedRowsCount/2;//if even number, we will swap all, if odd, the center item will remain unmoved
					for(NSUInteger i = 0; i < halfCount; i++)
					{
						temp = selectedRows[i];
						selectedRows[i] = selectedRows[selectedRowsCount-1-i];
						selectedRows[selectedRowsCount-1-i] = temp;
					}
				}

				static_assert(sizeof(unsigned long) == sizeof(NSUInteger));
				SelectionIterator *outSelIter = SelectionIterator_Create((unsigned long *)selectedRows, selectedRowsCount);
				return outSelIter;
			}
		}
	}
	
	return NULL;
}

- (void)setPropertyKey:(NSString *)propertyKey jsonValue:(NSString *)jsonValue forControlID:(NSString *)inControlID
{
    NSLog(@"[OMCNibWindowController] setPropertyKey:%@ jsonValue:forControlID: %@ — not supported for Nib dialogs", propertyKey, inControlID);
}

- (void)setStateKey:(NSString *)stateKey stringOrJsonValue:(NSString *)value forControlID:(NSString *)inControlID
{
    NSLog(@"[OMCNibWindowController] setStateKey:%@ value:forControlID: %@ — not supported for Nib dialogs", stateKey, inControlID);
}

@end
