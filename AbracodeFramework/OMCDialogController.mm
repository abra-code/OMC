//
//  OMCDialogController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#include <CoreServices/CoreServices.h>
#import <Quartz/Quartz.h>
#import <PDFKit/PDFKit.h>
#import "OMCDialogController.h"
#import "OMCPopUpButton.h"
#include "OnMyCommand.h"
#include "ACFDict.h"
#include "OMCCocoaDialog.h"
#include "CommandRuntimeData.h"
#include <vector>
#import "OMCTableViewController.h"
#import "OMCTableView.h"
#import "OMCComboBox.h" //for shouldExecutAction
#import "OMCButton.h" //for droppedItems
#import "OMCWebKitView.h"
#import "OMCView.h"

/*
 Method argument types. (Deprecated. These constants are used internally by NSInvocation—you should not use them directly.)
 
 enum _NSObjCValueType {
 NSObjCNoType = 0,
 NSObjCVoidType = 'v',
 NSObjCCharType = 'c',
 NSObjCShortType = 's',
 NSObjCLongType = 'l',
 NSObjCLonglongType = 'q',
 NSObjCFloatType = 'f',
 NSObjCDoubleType = 'd',
 
 NSObjCBoolType = 'B',
 
 NSObjCSelectorType = ':',
 NSObjCObjectType = '@',
 NSObjCStructType = '{',
 NSObjCPointerType = '^',
 NSObjCStringType = '*',
 NSObjCArrayType = '[',
 NSObjCUnionType = '(',
 NSObjCBitfield = 'b'
 };
 
 
 argument types:
 @ = id
 : = selector
 c = signed char
 C = unsigned char
 s = signed short
 S = unsigned short
 i = signed int
 I = unsigned int, some enums too
 q = long long
 Q = unsigned long long
 f = float
 d = double
 ^@ = *id
 v = void
 ^v  = void *
 {_NSRange=II} = NSRange {unsigned int, unsigned int}
 {_NSPoint=ff} = NSPoint {float, float}
 {_NSRect={_NSPoint=ff}{_NSSize=ff}}
 r* = const char *
 r^^{_NSRect} = const NSRect **
 */

typedef enum ObjCSelectorArgumentType
{
	kObjCArgNoType = 0,
	kObjCArgVoidType = 'v',
	kObjCArgCharType = 'c',
	kObjCArgUCharType = 'C',
	kObjCArgShortType = 's',
	kObjCArgUShortType = 'S',
	kObjCArgIntType = 'i',
	kObjCArgUIntType = 'I',
	kObjCArgLongType = 'l',
	kObjCArgULongType = 'L',
	kObjCArgLonglongType = 'q',
	kObjCArgULonglongType = 'Q',
	kObjCArgFloatType = 'f',
	kObjCArgDoubleType = 'd',
	
	kObjCArgBoolType = 'B',
	
	kObjCArgSelectorType = ':',
	kObjCArgObjectType = '@',
	kObjCArgStructType = '{',
	kObjCArgPointerType = '^',
	kObjCArgStringType = '*',
	kObjCArgArrayType = '[',
	kObjCArgUnionType = '(',
	kObjCArgBitfield = 'b'
} ObjCSelectorArgumentType;

static ObjCSelectorArgumentType
FindArgumentType(const char *argTypeStr)
{
	if(argTypeStr == NULL)
		return kObjCArgNoType;
	if(argTypeStr[0] == 'r')//const - skip it
		return (ObjCSelectorArgumentType)argTypeStr[1];
	return (ObjCSelectorArgumentType)argTypeStr[0];
}

static NSMutableSet<OMCDialogController *> *
GetAllDialogControllers()
{
    static NSMutableSet<OMCDialogController *> *sAllDialogControllers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sAllDialogControllers = [[NSMutableSet alloc] init];
    });

    return sAllDialogControllers;
}

@implementation OMCDialogController


- (id)initWithOmc:(OnMyCommandCM *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
{
   self = [super init];
	if(self == nil)
		return nil;

    mIsModal = true;
	mIsRunning = false;

    mPlugin.Adopt(inOmc, kARefCountRetain);
    assert(inCommandRuntimeData != nullptr);
    mCommandRuntimeData.Adopt(inCommandRuntimeData, kARefCountRetain);
    
    NSMutableSet<OMCDialogController *> *allDialogControllers = GetAllDialogControllers();
    [allDialogControllers addObject:self];
    
    mOMCDialogProxy.Adopt( new OMCCocoaDialog((__bridge OMCDialogControllerRef)self) );
    mCommandRuntimeData->SetAssociatedDialogUUID(mOMCDialogProxy->GetDialogUUID());

	mExternBundleRef.Adopt(inOmc->GetCurrentCommandExternBundle(), kCFObjRetain);

	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	mCommandName.Adopt(currCommand.name, kCFObjRetain);

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
    _dialogInitSubcommandID = (NSString *)CFBridgingRelease(initSubcommandID.Detach());
    
    CFObj<CFStringRef> endOKSubcommandID;
	params.CopyValue( CFSTR("END_OK_SUBCOMMAND_ID"), endOKSubcommandID );
    _endOKSubcommandID = (NSString *)CFBridgingRelease(endOKSubcommandID.Detach());

    CFObj<CFStringRef> endCancelSubcommandID;
	params.CopyValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), endCancelSubcommandID );
    _endCancelSubcommandID = (NSString *)CFBridgingRelease(endCancelSubcommandID.Detach());

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
        NSLog(@"[OMCDialogController initWithOmc], frameworkBundleRef=%@", (__bridge id)frameworkBundleRef);
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
        _window = [_omcCocoaNib getFirstWindow];
		if(_window != nil)
		{
			[_window setReleasedWhenClosed:NO];//we will release it when unloading the nib

            NSView *contentView = [_window contentView];
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
                    _window.representedURL = associatedFileURL;
                    [_window setTitleWithRepresentedFilename:associatedFileURL.path];
                }
            }
            
			[_window setDelegate: self];
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
	if(inPath != NULL)
	{//bundle with explicit path
		NSBundle *myBundle = [NSBundle bundleWithPath:inPath];
		if(myBundle != NULL)
		{
			NSNib *myNib = [[NSNib alloc] initWithNibNamed:inNibName bundle:myBundle];
			if(myNib != NULL)
			{
                self.omcCocoaNib = [[OMCCocoaNib alloc] initWithNib:myNib];
			}
		}
	}
	else
	{//main bundle
		NSNib *myNib = [[NSNib alloc] initWithNibNamed:inNibName bundle:NULL];
		if(myNib != NULL)
		{
			self.omcCocoaNib = [[OMCCocoaNib alloc] initWithNib:myNib];
		}
	}
	return (self.omcCocoaNib != nil);
}

- (void)dealloc
{
	mOMCDialogProxy->SetController(NULL);
	
	if(_window != NULL)
	{
		//the window may outlive us
		//we are dying we need to unregister all delegates, targets, observers, etc
		id contentViewObject = [_window contentView];
		if( (contentViewObject != NULL) && [contentViewObject isKindOfClass:[NSView class] ] )
		{
			[self resetSubview: (NSView*)contentViewObject];
		}
	
		[_window setDelegate:NULL];//we are dying
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

		if( [myTable target] == NULL )//don't override targets preset in IB
		{
			[myTable setTarget:self];
			//[myTable setAction:@selector(handleAction:)];
			[myTable setDoubleAction:@selector(handleDoubleClickAction:)];
		}
	}
	else if( [inView isKindOfClass:[NSControl class] ] )
	{//for controls - faster
		NSControl *myControl = (NSControl *)inView;
		if( [myControl target] == NULL )//don't override targets preset in IB
		{
			[myControl setTarget:self];
			[myControl setAction:@selector(handleAction:)];
		}
	}
	else
	{//for non-controls which may support target/action  - slower
		bool setTarget = true;
		if( [inView respondsToSelector:@selector(target)] )
			if( [inView performSelector:@selector(target)] != NULL )//don't override targets preset in IB
				setTarget = false;

		if(setTarget)
		{
			if( [inView respondsToSelector:@selector(setTarget:)] )
			{
				[inView performSelector:@selector(setTarget:) withObject:self];
                
                if ([inView conformsToProtocol:@protocol(OMCActionProtocol)]) {
                    id<OMCActionProtocol> actionView = (id<OMCActionProtocol>)inView;
                    //if( [inView respondsToSelector:@selector(setAction:)] )
                    [actionView setAction:@selector(handleAction:)]; //only if target is ourselves we can set action
                }
			}
		}
	}

	if([inView isKindOfClass:[NSTabView class]])
	{//init tabs view recursively
        for(NSTabViewItem *oneTab in ((NSTabView*)inView).tabViewItems)
        {
            NSView *tabView = [oneTab view];
            if(tabView != NULL)
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

//TODO: this method could use some serious refactoring to eliminate duplicate code
- (void) setControlValues:(CFDictionaryRef)inControlDict
{
	if( inControlDict == NULL )
		return;
	
	CFIndex itemCount = ::CFDictionaryGetCount(inControlDict);
	if(itemCount == 0)
		return;

	ACFDict controlValues(inControlDict);

	CFDictionaryRef removeListItemsDict;
	if( controlValues.GetValue(CFSTR("REMOVE_LIST_ITEMS"), removeListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(removeListItemsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(removeListItemsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
					if( controlOrView != NULL )
					{
						if( [controlOrView isKindOfClass:[NSPopUpButton class]] )
						{
							NSPopUpButton *myPopupButton = (NSPopUpButton *)controlOrView;
							[myPopupButton removeAllItems];
						}
						else if( [controlOrView isKindOfClass:[NSComboBox class]] )
						{
							NSComboBox *myCombo = (NSComboBox *)controlOrView;
							[myCombo removeAllItems];
						}
					}
				}
			}
		}
	}

	//"set" operation replaces existing list items
	CFDictionaryRef setListItemsDict;
	if( controlValues.GetValue(CFSTR("SET_LIST_ITEMS"), setListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(setListItemsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(setListItemsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
					if( controlOrView != NULL )
					{
						CFIndex itemCount = ::CFArrayGetCount(theArr);
						if( [controlOrView isKindOfClass:[NSPopUpButton class]] )
						{
							NSPopUpButton *myPopupButton = (NSPopUpButton *)controlOrView;
							[myPopupButton removeAllItems];
							
							for(CFIndex i = 0; i < itemCount; i++)
							{
								CFTypeRef oneItem = ::CFArrayGetValueAtIndex(theArr,i);
								CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
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
								CFTypeRef oneItem = ::CFArrayGetValueAtIndex(theArr,i);
								CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
								if(oneString != NULL)
                                    [myCombo addItemWithObjectValue:(__bridge NSString *)oneString];
							}
						}
					}
				}
			}
		}
	}

	//"append" operation preserving existing list items
	CFDictionaryRef appendListItemsDict;
	if( controlValues.GetValue(CFSTR("APPEND_LIST_ITEMS"), appendListItemsDict) )
	{
		itemCount = ::CFDictionaryGetCount(appendListItemsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(appendListItemsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
					if( controlOrView != NULL )
					{
						CFIndex itemCount = ::CFArrayGetCount(theArr);
						if( [controlOrView isKindOfClass:[NSPopUpButton class]] )
						{
							NSPopUpButton *myPopupButton = (NSPopUpButton *)controlOrView;
							for(CFIndex i = 0; i < itemCount; i++)
							{
								CFTypeRef oneItem = ::CFArrayGetValueAtIndex(theArr,i);
								CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
								if(oneString != NULL)
                                    [myPopupButton addItemWithTitle:(__bridge NSString *)oneString];
							}
						}
						else if( [controlOrView isKindOfClass:[NSComboBox class]] )
						{
							NSComboBox *myCombo = (NSComboBox *)controlOrView;
							
							for(CFIndex i = 0; i < itemCount; i++)
							{
								CFTypeRef oneItem = ::CFArrayGetValueAtIndex(theArr,i);
								CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
								if(oneString != NULL)
                                    [myCombo addItemWithObjectValue:(__bridge NSString *)oneString];
							}							
						}
					}
				}
			}
		}
	}

	//empty the table without refresh/reload
	CFDictionaryRef emptyTableDict;
	if( controlValues.GetValue(CFSTR("PREPARE_TABLE_EMPTY"), emptyTableDict) )
	{
		itemCount = ::CFDictionaryGetCount(emptyTableDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(emptyTableDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
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
			}
		}
	}

	//empty the table and refresh
	CFDictionaryRef removeTableRowsDict;
	if( controlValues.GetValue(CFSTR("REMOVE_TABLE_ROWS"), removeTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(removeTableRowsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(removeTableRowsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
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
			}
		}
	}

	//"set" operation replaces existing content and refreshes
	CFDictionaryRef setTableRowsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_ROWS"), setTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(setTableRowsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(setTableRowsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
					if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)controlOrView;
						id myDelegate = [myTable delegate];
						if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
						{
							[myDelegate removeRows];
							[myDelegate addRows:theArr];
							[myDelegate reloadData];
						}
					}
				}
			}
		}
	}

	//this is "append" operation
	CFDictionaryRef addTableRowsDict;
	if( controlValues.GetValue(CFSTR("ADD_TABLE_ROWS"), addTableRowsDict) )
	{
		itemCount = ::CFDictionaryGetCount(addTableRowsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(addTableRowsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
					if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)controlOrView;
						id myDelegate = [myTable delegate];
						if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
						{
							[myDelegate addRows:theArr];
							[myDelegate reloadData];
						}
					}
				}
			}
		}
	}

	CFDictionaryRef addTableColumnsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_COLUMNS"), addTableColumnsDict) )
	{
		itemCount = ::CFDictionaryGetCount(addTableColumnsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(addTableColumnsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
					if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)controlOrView;
						id myDelegate = [myTable delegate];
						
						//BOOL isKindOf = [myDelegate isKindOfClass:[OMCTableViewController class]];
						//BOOL isMemberOf = [myDelegate isMemberOfClass:[OMCTableViewController class]];
						//NSLog(@"OMC tableview controller: isKindOf=%d, isMemberOf=%d", (int)isKindOf, (int)isMemberOf);
						
						if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
                            [myDelegate setColumns:(__bridge NSArray *)theArr];
					}
				}
			}
		}
	}

	CFDictionaryRef setTableWidthsDict;
	if( controlValues.GetValue(CFSTR("SET_TABLE_WIDTHS"), setTableWidthsDict) )
	{
		itemCount = ::CFDictionaryGetCount(setTableWidthsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(setTableWidthsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString*)controlID];
					if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)controlOrView;
						id myDelegate = [myTable delegate];
						if( (myDelegate != nil) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
                            [myDelegate setColumnWidths:(__bridge NSArray *)theArr];
					}
				}
			}
		}
	}

	{
	CFDictionaryRef valuesDict = NULL;
	if( controlValues.GetValue(CFSTR("VALUES"), valuesDict) )
	{
		itemCount = ::CFDictionaryGetCount(valuesDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(valuesDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				if(controlID != NULL)
				{
                    [self setControlStringValue:(__bridge NSString *)ACFType<CFStringRef>::DynamicCast( valueList[i] )
                                   forControlID:(__bridge NSString*)controlID];
				}
			}
		}
	}
	}
	
	{
	CFDictionaryRef enableDisableDict = NULL;
	if( controlValues.GetValue(CFSTR("ENABLE_DISABLE"), enableDisableDict) )
	{
		itemCount = ::CFDictionaryGetCount(enableDisableDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(enableDisableDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString *)controlID];
					if(controlOrView != nil)
					{
						Boolean doEnable = ::CFBooleanGetValue(theVal);
						if( [controlOrView respondsToSelector:@selector(setEnabled:)] )
								[(NSControl *)controlOrView setEnabled:doEnable];
						else
						{
							//NSView does not have enable/disable
						}
					}
				}
			}
		}
	}
	}

	{
	CFDictionaryRef showHideDict = NULL;
	if( controlValues.GetValue(CFSTR("SHOW_HIDE"), showHideDict) )
	{
		itemCount = ::CFDictionaryGetCount(showHideDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(showHideDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
				{
                    id controlOrView = [self findControlOrViewWithID:(__bridge NSString *)controlID];
					if( (controlOrView != nil) && [controlOrView respondsToSelector:@selector(setHidden:)] )
					{
						BOOL makeVisible = (BOOL)::CFBooleanGetValue(theVal);
						[controlOrView setHidden:(!makeVisible)];
					}
				}
			}
		}
	}
	}

	{
	CFDictionaryRef commandIdsDict = NULL;
	if( controlValues.GetValue(CFSTR("COMMAND_IDS"), commandIdsDict) )
	{
		itemCount = ::CFDictionaryGetCount(commandIdsDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);

			::CFDictionaryGetKeysAndValues(commandIdsDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFStringRef theVal = ACFType<CFStringRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
				{
                    NSView *controlOrView = [self findControlOrViewWithID:(__bridge NSString *)controlID];
					if( (controlOrView != nil) && [controlOrView respondsToSelector:@selector(setCommandID:)] )
					{
                        [controlOrView performSelector:@selector(setCommandID:) withObject:(__bridge NSString *)theVal];
					}
				}
			}
		}
	}
	}

	{
	CFDictionaryRef selectDict = NULL;
	if( controlValues.GetValue(CFSTR("SELECT"), selectDict) )
	{
		itemCount = ::CFDictionaryGetCount(selectDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			
			::CFDictionaryGetKeysAndValues(selectDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				//we don't care about the bool value
				//CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) /*&& (theVal != NULL)*/ )
				{
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						//the message targets our dialog window
						[self.window makeKeyAndOrderFront:self];//bring it to front and select
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
					{
						NSApplication *myApp = [NSApplication sharedApplication];
						if(myApp != nil)
							[myApp activateIgnoringOtherApps:YES];
					}
					else
					{
						//"selecting" a control means putting a focus in it/making it the first responder
                        NSView *controlOrView = [self findControlOrViewWithID:(__bridge NSString *)controlID];
						if(controlOrView != nil)
							[self.window makeFirstResponder:controlOrView];
					}
				}
			}
		}
	}
	}
	

	{
	CFDictionaryRef terminateDict = NULL;
	if( controlValues.GetValue(CFSTR("TERMINATE"), terminateDict) )
	{
		itemCount = ::CFDictionaryGetCount(terminateDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			
			::CFDictionaryGetKeysAndValues(terminateDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFBooleanRef theVal = ACFType<CFBooleanRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theVal != NULL) )
				{
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						//the message targets our dialog window
						Boolean terminateOK = ::CFBooleanGetValue(theVal);
						NSString *commandID;
						if(terminateOK)
                        {
                            commandID = self.endOKSubcommandID ?: @"omc.dialog.ok";
                        }
						else
                        {
                            commandID = self.endCancelSubcommandID ?: @"omc.dialog.cancel";
                        }
						
						self.lastCommandID = commandID;

						[self.window close];//our windowWillClose will be called, which calls "terminate", which executes the proper termination command
						return;
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
					{
						NSApplication *myApp = [NSApplication sharedApplication];
						if(myApp != NULL)
						{
							[myApp terminate:self];
							return;
						}
					}
					else
					{//can a control/view respond to some kind of terminate message? probably not
						//NSView *controlOrView = [self findControlOrViewWithID:controlId];
						//if(controlOrView != NULL)
						//	[controlOrView setHidden:(BOOL)::CFBooleanGetValue(theVal)];
					}
				}
			}
		}
	}
	}

	{
		CFDictionaryRef moveDict = NULL;
		if( controlValues.GetValue(CFSTR("MOVE"), moveDict) )
		{
			itemCount = ::CFDictionaryGetCount(moveDict);
			if(itemCount > 0)
			{
				std::vector<CFTypeRef> keyList(itemCount);
				std::vector<CFTypeRef> valueList(itemCount);
				
				::CFDictionaryGetKeysAndValues(moveDict, (const void **)keyList.data(), (const void **)valueList.data());
				for(CFIndex i = 0; i < itemCount; i++)
				{
					CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
					CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
					
					if( (controlID != NULL) && (theArr != NULL) )
					{
						NSPoint newTopLeftOrigin = {0, 0};
						CFIndex theCount = ::CFArrayGetCount(theArr);
						if(theCount > 0)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 0);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.x = ::CFStringGetIntValue(numString);
						}

						if(theCount > 1)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 1);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.y = ::CFStringGetIntValue(numString);
						}

						if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
						{
							[self setWindowTopLeftPosition:newTopLeftOrigin];
						}
						else
						{
                            id controlOrView = [self findControlOrViewWithID:(__bridge NSString *)controlID];
							if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSView class]] )
							{
								float viewHeight = NSHeight([controlOrView bounds]);
								NSView *superView = [controlOrView superview];
								float superHeight = NSHeight([superView bounds]);
								float bottomOrigin = superHeight - viewHeight - newTopLeftOrigin.y;
								[controlOrView setFrameOrigin: NSMakePoint(newTopLeftOrigin.x, bottomOrigin) ];
								[controlOrView setNeedsDisplay:YES];
								//[[controlOrView superview] setNeedsDisplay: YES];//can it mess up the superview?
							}
						}
					}
				}
			}
		}
	}

	{
		CFDictionaryRef moveDict = NULL;
		if( controlValues.GetValue(CFSTR("SCROLL"), moveDict) )
		{
			itemCount = ::CFDictionaryGetCount(moveDict);
			if(itemCount > 0)
			{
				std::vector<CFTypeRef> keyList(itemCount);
				std::vector<CFTypeRef> valueList(itemCount);
				
				::CFDictionaryGetKeysAndValues(moveDict, (const void **)keyList.data(), (const void **)valueList.data());
				for(CFIndex i = 0; i < itemCount; i++)
				{
					CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
					CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
					
					if( (controlID != NULL) && (theArr != NULL) )
					{
						NSPoint newTopLeftOrigin = {0, 0};
						CFIndex theCount = ::CFArrayGetCount(theArr);
						if(theCount > 0)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 0);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.x = ::CFStringGetIntValue(numString);
						}
						
						if(theCount > 1)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 1);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newTopLeftOrigin.y = ::CFStringGetIntValue(numString);
						}

						//NSInteger controlId = ::CFStringGetIntValue(theKey);
                        id myView = [self findControlOrViewWithID:(__bridge NSString *)controlID];
						
						if( myView != nil )
						{
							NSClipView *clipView = nil;
							NSView *docView = nil;
							if( [myView isKindOfClass:[NSScrollView class] ] )
							{//we target scroll view
								docView = [(NSScrollView *)myView documentView];
								NSView *superView = [docView superview];
								if( [superView isKindOfClass:[NSClipView class] ] )
									clipView = (NSClipView *)superView;
							}
							else if( [myView isKindOfClass:[PDFView	class] ] )
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
							else if( [myView isKindOfClass:[IKImageView	class]] )
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
									newTopLeftOrigin.y = /*NSMaxY([myView frame])*/imgSize.height - superHeight - newTopLeftOrigin.y;
								}

								[docView scrollPoint:newTopLeftOrigin];
								clipView = nil;//set to null to prevent scrolling attempts below
							}
							else if( [myView isKindOfClass:[NSView	class]] ) 
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
									newTopLeftOrigin.y = /*NSMaxY([myView frame])*/viewHeight - superHeight - newTopLeftOrigin.y;
								}
								
								[docView scrollPoint:newTopLeftOrigin];
							}
						}
					}
				}
			}
		}
	}
	
	{
		CFDictionaryRef resizeDict = NULL;
		if( controlValues.GetValue(CFSTR("RESIZE"), resizeDict) )
		{
			itemCount = ::CFDictionaryGetCount(resizeDict);
			if(itemCount > 0)
			{
				std::vector<CFTypeRef> keyList(itemCount);
				std::vector<CFTypeRef> valueList(itemCount);
				
				::CFDictionaryGetKeysAndValues(resizeDict, (const void **)keyList.data(), (const void **)valueList.data());
				for(CFIndex i = 0; i < itemCount; i++)
				{
					CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
					CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
					if( (controlID != NULL) && (theArr != NULL) )
					{
						NSSize newSize = { 0, 0 };
						CFIndex theCount = ::CFArrayGetCount(theArr);
						if(theCount > 0)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 0);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newSize.width = ::CFStringGetIntValue(numString);
						}
						
						if(theCount > 1)
						{
							CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(theArr, 1);
							CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
							if(numString != NULL)
								newSize.height = ::CFStringGetIntValue(numString);
						}

						if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
						{
							//the message targets our dialog window
							[self.window setContentSize:newSize];
						}
						else
						{
                            id controlOrView = [self findControlOrViewWithID:(__bridge NSString *)controlID];
							
							if( (controlOrView != nil) && [controlOrView isKindOfClass:[NSView class]] )
							{
								[controlOrView setFrameSize:newSize];
								[controlOrView setNeedsDisplay:YES];
							}
						}
					}
				}
			}
		}
	}

	{
	CFDictionaryRef invokeDict;
	if( controlValues.GetValue(CFSTR("INVOKE"), invokeDict) )
	{
		itemCount = ::CFDictionaryGetCount(invokeDict);
		if(itemCount > 0)
		{
			std::vector<CFTypeRef> keyList(itemCount);
			std::vector<CFTypeRef> valueList(itemCount);
			
			::CFDictionaryGetKeysAndValues(invokeDict, (const void **)keyList.data(), (const void **)valueList.data());
			for(CFIndex i = 0; i < itemCount; i++)
			{
				CFStringRef controlID = ACFType<CFStringRef>::DynamicCast( keyList[i] );
				CFArrayRef theArr = ACFType<CFArrayRef>::DynamicCast( valueList[i] );
				if( (controlID != NULL) && (theArr != NULL) )
				{
					id messageTarget = nil;
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						//the message targets our dialog window
						messageTarget = (id)self.window;
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
					{
						messageTarget = (id)[NSApplication sharedApplication];
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_workspace"), 0) )
					{
						messageTarget = (id)[NSWorkspace sharedWorkspace];
					}
					else
					{
                        messageTarget = [self findControlOrViewWithID:(__bridge NSString *)controlID];
					}

					if(messageTarget != nil)
					{
						CFIndex messageCount = ::CFArrayGetCount(theArr);
						if(messageCount > 0)
						{
							for(CFIndex msgIndex = 0; msgIndex < messageCount; msgIndex++)
							{
								CFArrayRef oneObjCMessage = ACFType<CFArrayRef>::DynamicCast( ::CFArrayGetValueAtIndex(theArr, msgIndex) );
								if(oneObjCMessage != NULL)
									[self sendObjCMessage:oneObjCMessage toTarget:(id)messageTarget];
							}
						}
					}
				}
			}
		}
	}
	}
}

- (void)dispatchCommand:(NSString *)inCommandID withContext:(CFTypeRef)inContext
{
	//do some dispatching of the command here
	self.lastCommandID = inCommandID;
	
	if( [self commandShouldCloseDialog] )
	{
		[self.window close];//our windowWillClose will be called, which calls "terminate", which executes the proper termination command
	}
	else
	{
		[self processCommandWithContext:inContext];
	}
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

//NSWindow delegate methods
- (void)windowWillClose:(NSNotification *)notification
{
	if( mIsModal )
	{
		[NSApp stopModal];
	//	NSInteger returnCode = 0;
	//	[NSApp stopModalWithCode:returnCode];
	}

	[self terminate];

    NSMutableSet<OMCDialogController *> *allDialogControllers = GetAllDialogControllers();
    [allDialogControllers removeObject:self];
}

- (OMCCocoaDialog *)getOMCDialog
{
	return (OMCCocoaDialog *)mOMCDialogProxy;
}

- (Boolean)isModal
{
	return mIsModal;
}

- (void)run
{
#if DEBUG
	NSLog(@"[OMCDialogController run] self.window=%@", (id)self.window);
#endif
	
	if( mIsModal )
	{
		
//		bool isInited = false;
		if( [self initializeDialog] )
		{
/*
			NSRunLoop *currRunLoop = [NSRunLoop currentRunLoop];
			CFRunLoopRef cfRunLoop = [currRunLoop getCFRunLoop];
			CFStringRef modeString = CFRunLoopCopyCurrentMode(cfRunLoop);
			NSLog(@"OMCCialogController run loop modeString=%@", modeString);
			if(modeString != NULL)
				CFRelease(modeString);
			
			CFShow(cfRunLoop);
			//NSLog( @"OMCCialogController cfRunLoop=%@", cfRunLoop);
*/	
#if 0
			NSModalSession session = [NSApp beginModalSessionForWindow:self.window];
			for (;;)
			{
				if( [NSApp runModalSession:session] != NSRunContinuesResponse )
					break;

			//	CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
			}
			[NSApp endModalSession:session];
#else

			[NSApp runModalForWindow:self.window];
#endif
			
		}
	}
	else
	{
		if( [self initializeDialog] )
			[self.window makeKeyAndOrderFront:self];
	}
}

- (BOOL)isOkeyed
{
	
	if(self.lastCommandID != nil)
	{
		if(self.endOKSubcommandID != nil)
        {
            return [self.lastCommandID isEqualToString:self.endOKSubcommandID];
        }

		return [self.lastCommandID isEqualToString:@"omc.dialog.ok"];
	}
	return false;
}

- (BOOL)isCanceled
{
	if(self.lastCommandID != nil)
	{
		if(self.endCancelSubcommandID != nil)
        {
            return [self.lastCommandID isEqualToString:self.endCancelSubcommandID];
        }

		return [self.lastCommandID isEqualToString:@"omc.dialog.cancel"];
	}
	return false;
}

- (BOOL)commandShouldCloseDialog
{
	return ([self isOkeyed] || [self isCanceled]);
}


- (BOOL)initializeDialog
{
	NSString *origCommand = self.lastCommandID;

	self.lastCommandID = @"omc.dialog.initialize";
	if(self.dialogInitSubcommandID != nil)
    {
        self.lastCommandID = self.dialogInitSubcommandID;
    }
    
	mOMCDialogProxy->StartListening();

    [self processCommandWithContext:NULL];

	self.lastCommandID = origCommand;

	if(mPlugin->GetError() != noErr)
		return NO;//if there was an error during init command don't show the dialog

	return YES;
}

- (BOOL)terminate
{
	BOOL wasOkeyed = [self isOkeyed];
	NSString *origCommand = self.lastCommandID;
	
	self.lastCommandID = wasOkeyed ? @"omc.dialog.terminate.ok" : @"omc.dialog.terminate.cancel";

	if( wasOkeyed && (self.endOKSubcommandID != nil) )
    {
        self.lastCommandID = self.endOKSubcommandID;
    }
	else if( !wasOkeyed && (self.endCancelSubcommandID != nil) )
    {
        self.lastCommandID = self.endCancelSubcommandID;
    }
    
	[self processCommandWithContext:NULL];

    self.lastCommandID = origCommand;

	return YES;
}

- (OSStatus)processCommandWithContext:(CFTypeRef)inContext
{
	if(mPlugin == nullptr)
    {
        return paramErr;
    }
    
	SInt32 cmdIndex = -1;
    if(OMCDialog::IsPredefinedDialogCommandID((__bridge CFStringRef)self.lastCommandID))
    {
        cmdIndex = mPlugin->FindSubcommandIndex(mCommandName, (__bridge CFStringRef)self.lastCommandID); //only strict subcommand for predefined dialog commands
    }
	else																//(command name must match)
    {
        cmdIndex = mPlugin->FindCommandIndex(mCommandName, (__bridge CFStringRef)self.lastCommandID);//relaxed rules for custom command id
        //(for example when used for next command)
    }
    
	if(cmdIndex < 0)
    {
        return errAEEventNotHandled;//did not find the specified subcommand
    }
    
	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	SelectionIterator *oldIterator = mOMCDialogProxy->GetSelectionIterator();
	SelectionIterator *currentSelectionIterator = nullptr;
	if( currCommand.multipleSelectionIteratorParams != nullptr )
		currentSelectionIterator = [self createSelectionIterator:currCommand.multipleSelectionIteratorParams];

	mOMCDialogProxy->SetSelectionIterator(currentSelectionIterator);
	
	OSStatus status = noErr;

	do
	{
		status = mPlugin->ExecuteSubcommand( cmdIndex, mCommandRuntimeData, inContext );//does not throw
	}
	while( (currentSelectionIterator != nullptr) && SelectionIterator_Next(currentSelectionIterator) );

	mOMCDialogProxy->SetSelectionIterator(oldIterator);

	SelectionIterator_Release(currentSelectionIterator);
	
	return status;
}

- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition
{	
	NSRect windowFrame = [self.window frame];
	
	NSScreen *mainScreen = [NSScreen mainScreen];
	NSRect screenRect = [mainScreen visibleFrame];

	{//absolute position
		absolutePosition.x += screenRect.origin.x;
		absolutePosition.y = screenRect.origin.y + screenRect.size.height - absolutePosition.y - windowFrame.size.height;//bottom of the window
		if( (absolutePosition.y + windowFrame.size.height) < screenRect.origin.y )
			absolutePosition.y = screenRect.origin.y - windowFrame.size.height + 20;//winodw top visible at the bottom of the screen
	}

	[self.window setFrameOrigin:absolutePosition];
}

- (void) sendObjCMessage:(CFArrayRef)oneObjCMessage toTarget:(id)messageTarget
{
	CFLocaleRef currentLocale = NULL; 
	CFNumberFormatterRef numberFormatter = NULL;

	@try
	{
		//TODO:
		//check if object responds to given message
		//obtain NSMethodSignature, check argument types
		//create NSInvocation and invoke on object
		CFIndex elementCount = CFArrayGetCount(oneObjCMessage);
		if( elementCount == 0 )
			return;

		NSMutableString *methodName = [NSMutableString string];
		for(CFIndex i = 0; i < elementCount; i+=2)
		{//first obtain method name
			CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(oneObjCMessage, i);
			CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
			if(oneString != NULL)
            {
                [methodName appendString:(__bridge NSString *)oneString];
            }
		}

		SEL methodSelector = NSSelectorFromString(methodName);
		NSMethodSignature *methodSig = [messageTarget methodSignatureForSelector:methodSelector];
		if( methodSig != nil )
		{//good news - object has this method implemented
			
			//const char *returnType = [methodSig methodReturnType];
			//NSLog(@"methodReturnType=%s\n", returnType);

			NSInvocation *messageInvocation = [NSInvocation invocationWithMethodSignature:methodSig];
			if(messageInvocation != NULL)
			{
				BOOL okToAddArgument = YES;
				[messageInvocation setTarget:messageTarget];
				[messageInvocation setSelector:methodSelector];
				char stackBuff[128];//128 bytes should be enough for most structures
				NSUInteger argCount = [methodSig numberOfArguments] - 2;//count only real arguments, skip self and selector
				for(NSUInteger argIndex = 0; argIndex < argCount; argIndex++)
				{
					const char *argTypeStr = [methodSig getArgumentTypeAtIndex:2+argIndex];
	#if DEBUG
					NSLog(@"argument %d type=%s\n", (int)argIndex+1, argTypeStr);
	#endif
					//set argument
					if( (argIndex*2 + 1) < elementCount )
					{
						CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(oneObjCMessage, argIndex*2 + 1);
						CFStringRef argString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
						if(argString != NULL)
						{
							ObjCSelectorArgumentType argType = FindArgumentType(argTypeStr);
							okToAddArgument = YES;
							
							switch(argType)
							{
								case kObjCArgCharType:
								{//this is also BOOL that's why we check for YES/NO true/false
									char charVal = 0;
									if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("YES"), argString, kCFCompareCaseInsensitive)) ||
									   (kCFCompareEqualTo == ::CFStringCompare( CFSTR("true"), argString, kCFCompareCaseInsensitive)) )
									{
										charVal = 1;
									}
									else if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("NO"), argString, kCFCompareCaseInsensitive)) ||
											(kCFCompareEqualTo == ::CFStringCompare( CFSTR("false"), argString, kCFCompareCaseInsensitive)) )
									{
										charVal = 0;
									}
									else
									{
										charVal = (char)CFStringGetIntValue(argString);
									}
									
									*(char *)stackBuff = charVal;
								}
								break;
								
								case kObjCArgUCharType:
								{
									*(unsigned char *)stackBuff = (unsigned char)CFStringGetIntValue(argString);
								}
								break;
								
								case kObjCArgShortType:
								{
									*(short *)stackBuff = (short)CFStringGetIntValue(argString);
								}
								break;
									
								case kObjCArgUShortType:
								{
									*(unsigned short *)stackBuff = (unsigned short)CFStringGetIntValue(argString);
								}
								break;

								case kObjCArgIntType:
								{
									*(int *)stackBuff = (int)CFStringGetIntValue(argString);
								}

								case kObjCArgLongType:
								{
									*(long *)stackBuff = (long)CFStringGetIntValue(argString);
								}
								break;
									
								case kObjCArgULongType:
								case kObjCArgUIntType:
								case kObjCArgLonglongType:
								case kObjCArgULonglongType:
								{
									if(currentLocale == NULL)
										currentLocale = CFLocaleCopyCurrent();
									
									if(numberFormatter == NULL)
										numberFormatter = CFNumberFormatterCreate(kCFAllocatorDefault, currentLocale, kCFNumberFormatterDecimalStyle);

									long long longlongVal = 0;
									okToAddArgument = CFNumberFormatterGetValueFromString(numberFormatter, argString, NULL, kCFNumberLongLongType, &longlongVal);
									if(okToAddArgument)
									{
										if(argType == kObjCArgULongType)
										{
											*(unsigned long *)stackBuff = (unsigned long)longlongVal;
										}
										else if(argType == kObjCArgUIntType)
										{
											*(unsigned int *)stackBuff = (unsigned int)longlongVal;
										}
										else if(argType == kObjCArgLonglongType)
										{
											*(long long *)stackBuff = longlongVal;
										}
										else if(argType == kObjCArgULonglongType)
										{
											*(unsigned long long *)stackBuff = (unsigned long long)longlongVal;
										}
									}
								}
								break;
								
								case kObjCArgFloatType:
								{
									*(float *)stackBuff = (float)CFStringGetDoubleValue(argString);
								}
								break;
									
								case kObjCArgDoubleType:
								{
									*(double *)stackBuff = (double)CFStringGetDoubleValue(argString);
								}
								break;
								
								case kObjCArgBoolType:
								{
									BOOL boolVal = NO;
									if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("YES"), argString, kCFCompareCaseInsensitive)) ||
										(kCFCompareEqualTo == ::CFStringCompare( CFSTR("true"), argString, kCFCompareCaseInsensitive)) )
									{
										boolVal = YES;
									}
									else if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("NO"), argString, kCFCompareCaseInsensitive)) ||
											(kCFCompareEqualTo == ::CFStringCompare( CFSTR("false"), argString, kCFCompareCaseInsensitive)) )
									{
										boolVal = NO;
									}
									else
									{
										SInt32 intVal = CFStringGetIntValue(argString);
										boolVal = (BOOL)intVal;
									}
									*(BOOL *)stackBuff = boolVal;
								}
								break;

								case kObjCArgObjectType:
								{//only NSString */CFStringRef supported as id/NSObject *
									if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc_nil"), argString, kCFCompareCaseInsensitive) )
                                    {
                                        *(CFTypeRef *)stackBuff = nil;
                                    }
                                    else
                                    {
                                        *(CFStringRef *)stackBuff = argString;
                                    }
								}
								break;
									
								case kObjCArgStructType:
								{
									memset(stackBuff, 0, sizeof(stackBuff));
									
									CFArrayRef numberArray = CFStringCreateArrayBySeparatingStrings( kCFAllocatorDefault, argString, CFSTR(",") );
									CFIndex numberCount = 0;
									if(numberArray != NULL)
										numberCount = CFArrayGetCount(numberArray);
									//first char is '{', next follows the structure name
									if(numberCount >= 2)
									{//all structures here require at least 2 numbers
										if( 0 == strncmp("_NSRange", argTypeStr+1, sizeof("_NSRange")-1) )
										{
											NSRange *theRange = (NSRange *)stackBuff;
											
											CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
											CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												theRange->location = ::CFStringGetIntValue(numString);
											else
												okToAddArgument = NO;
											
											oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
											numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												theRange->length =  ::CFStringGetIntValue(numString);
											else
												okToAddArgument = NO;
										}
										else if( 0 == strncmp("_NSPoint", argTypeStr+1, sizeof("_NSPoint")-1) )
										{
											NSPoint *thePoint = (NSPoint *)stackBuff;
											
											CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
											CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												thePoint->x = (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;
											
											oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
											numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												thePoint->y =  (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;
										}
										else if( 0 == strncmp("_NSSize", argTypeStr+1, sizeof("_NSSize")-1) )
										{
											NSSize *theSize = (NSSize *)stackBuff;

											CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
											CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												theSize->width = (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;
											
											oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
											numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												theSize->height =  (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;
										}
										else if( (numberCount >= 4) && (0 == strncmp("_NSRect", argTypeStr+1, sizeof("_NSRect")-1)) )
										{
											NSRect *theRect = (NSRect *)stackBuff;

											CFTypeRef oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
											CFStringRef numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												theRect->origin.x = (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;
											
											oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
											numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												theRect->origin.y =  (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;

											oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 0);
											numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(numString != NULL)
												theRect->size.width = (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;
											
											oneItemRef = ::CFArrayGetValueAtIndex(numberArray, 1);
											numString = ACFType<CFStringRef>::DynamicCast( oneItemRef );
											if(theRect != NULL)
												theRect->size.height =  (CGFloat)::CFStringGetDoubleValue(numString);
											else
												okToAddArgument = NO;
										}
										else
										{
											okToAddArgument = NO;
											NSLog(@"OMCDialogController sendObjCMessage: this structure type unsuppported for argument %d for \"%@\" selector", (int)argIndex+1, methodName);
										}
									}
									else
									{
										okToAddArgument = NO;
										NSLog(@"OMCDialogController sendObjCMessage: invalid count of members for structure argument %d for \"%@\" selector", (int)argIndex+1, methodName);
									}
									
								}
								break;
									
								case kObjCArgPointerType:
								case kObjCArgStringType:
								case kObjCArgArrayType:
								case kObjCArgUnionType:
								case kObjCArgBitfield:
								{
									if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc_nil"), argString, kCFCompareCaseInsensitive) )
                                    {
                                        *(CFTypeRef *)stackBuff = nil;
                                    }
                                    else
									{
										okToAddArgument = NO;
										NSLog(@"OMCDialogController sendObjCMessage: unsupported argument type for argument %d for \"%@\" selector", (int)argIndex+1, methodName);
									}
								}
								break;
								
								case kObjCArgNoType:
								case kObjCArgVoidType:
								case kObjCArgSelectorType:
								default:
								{
									okToAddArgument = NO;
									NSLog(@"OMCDialogController sendObjCMessage: invalid argument %d for \"%@\" selector", (int)argIndex+1, methodName);
								}
								break;
							}
							
							if(okToAddArgument)
							{
								[messageInvocation setArgument:(void *)stackBuff atIndex:2+argIndex];
							}
							else
							{
								break;//we will not be able to process this comamnd 
							}
						}
					}
					else
					{
						NSLog(@"OMCDialogController sendObjCMessage: argument count mismatch for \"%@\" selector", methodName);
					}
				}
				
				if(okToAddArgument)
					[messageInvocation invoke];
			}
		}
		else
		{
			NSLog(@"OMCDialogController sendObjCMessage: target object does not respond to \"%@\" selector", methodName);
		}
	}
	@catch (NSException *localException)
	{
		NSLog(@"OMCDialogController sendObjCMessage received exception while trying to invoke a custom message: %@", localException);
	}
	
	if( currentLocale != NULL )
	   CFRelease(currentLocale);

	if( numberFormatter != NULL )
	   CFRelease(numberFormatter);
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

-(void)keepItem:(id)inItem
{
	if(inItem == NULL)
		return;
	
	if(self.dialogOwnedItems == NULL)
        self.dialogOwnedItems = [[NSMutableSet alloc] init];
	
	[self.dialogOwnedItems addObject:inItem];
}


@end
