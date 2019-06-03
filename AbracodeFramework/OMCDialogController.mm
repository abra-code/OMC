//
//  OMCDialogController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCDialogController.h"
#import "OMCPopUpButton.h"
#include "OnMyCommand.h"
#include "ACFDict.h"
#include "OMCCocoaDialog.h"
#include <vector>
#import "OMCQCView.h"
#import "OMCTableViewController.h"
#import "OMCTableView.h"
#import "OMCComboBox.h" //for shouldExecutAction
#import "OMCButton.h" //for droppedItems

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

ObjCSelectorArgumentType
FindArgumentType(const char *argTypeStr)
{
	if(argTypeStr == NULL)
		return kObjCArgNoType;
	if(argTypeStr[0] == 'r')//const - skip it
		return (ObjCSelectorArgumentType)argTypeStr[1];
	return (ObjCSelectorArgumentType)argTypeStr[0];
}


@implementation OMCDialogController


- (id)initWithOmc:(OnMyCommandCM *)inOmc
{
   self = [super init];
	if(self == NULL)
		return NULL;

	mWindow = NULL;
	mOmcCocoaNib = NULL;
	mLastCommandID = NULL;
	mDialogOwnedItems = NULL;
	mIsModal = false;
	mIsRunning = false;
	mDeleteSelfOnClose = false;

	mOMCDialogProxy.reset( new OMCCocoaDialog(self) );

	mPlugin.Adopt(inOmc, kARefCountRetain);
	mExternBundleRef.Adopt(inOmc->GetCurrentCommandExternBundle(), kCFObjRetain);

	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	mCommandName.Adopt(currCommand.name, kCFObjRetain);

	ACFDict params( currCommand.nibDialog );
	CFStringRef dialogNibName = NULL;
	params.GetValue( CFSTR("NIB_NAME"), dialogNibName );

	if(dialogNibName == NULL)
		return self;//no nib name, no dialog

//	We can't get the window by name from nib in Cocoa
//	CFStringRef nibWindowName = NULL;
//	params.GetValue( CFSTR("WINDOW_NAME"), nibWindowName );

	params.CopyValue( CFSTR("INIT_SUBCOMMAND_ID"), mInitSubcommandID );
	params.CopyValue( CFSTR("END_OK_SUBCOMMAND_ID"), mEndOKSubcommandID );
	params.CopyValue( CFSTR("END_CANCEL_SUBCOMMAND_ID"), mEndCancelSubcommandID );
	
	Boolean isBlocking = true;//default is modal
	params.GetValue( CFSTR("IS_BLOCKING"), isBlocking );
	mIsModal = isBlocking;
	if(mIsModal == false)
	{//modelesss dialog disposes itself automatically but needs to be retained here because our caller will release one instance
		mDeleteSelfOnClose = true;
		[self retain];
	}

	//now we need to find out where our nib is

	if(mExternBundleRef != NULL)
	{//extern bundle exists? most likely it will be there
		CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( mExternBundleRef ) );
		if(bundleURL != NULL)
		{
			CFObj<CFStringRef> absolutePath;
			CFObj<CFURLRef> absoluteURL( CFURLCopyAbsoluteURL(bundleURL) );
			if(absoluteURL != NULL)
			{
				absolutePath.Adopt( ::CFURLCopyFileSystemPath(absoluteURL, kCFURLPOSIXPathStyle) );
				if(absolutePath != NULL)
				{
					[self findNib:(NSString *)dialogNibName forBundlePath:(NSString *)(CFStringRef)absolutePath];
				}
			}
		}
	}

	if(mOmcCocoaNib == NULL)
	{//still not found, check main default bundle
		[self findNib:(NSString *)dialogNibName forBundlePath:NULL];
	}

	if(mOmcCocoaNib == NULL)
	{
		CFBundleRef frameworkBundleRef = mPlugin->GetBundleRef();
#if DEBUG
		NSLog(@"[OMCDialogController initWithOmc], frameworkBundleRef=%@", (id)frameworkBundleRef);
		CFShow(frameworkBundleRef);
#endif
		if(frameworkBundleRef != NULL)
		{
			CFObj<CFURLRef> bundleURL( CFBundleCopyBundleURL( frameworkBundleRef ) );
			if(bundleURL != NULL)
			{
				CFObj<CFStringRef> absolutePath;
				CFObj<CFURLRef> absoluteURL( CFURLCopyAbsoluteURL(bundleURL) );
				if(absoluteURL != NULL)
				{
					absolutePath.Adopt( ::CFURLCopyFileSystemPath(absoluteURL, kCFURLPOSIXPathStyle) );
					if(absolutePath != NULL)
					{
						[self findNib:(NSString *)dialogNibName forBundlePath:(NSString *)(CFStringRef)absolutePath];
					}
				}
			}
		}
	}

	if(mOmcCocoaNib != NULL)
	{
		mWindow = [mOmcCocoaNib getFirstWindow];
		if(mWindow != NULL)
		{
			[mWindow setReleasedWhenClosed:NO];//we will release it when unloading the nib
			[mWindow retain];

			id contentViewObject = [mWindow contentView];
			if( (contentViewObject != NULL) && [contentViewObject isKindOfClass:[NSView class] ] )
			{
				[self initSubview: (NSView*)contentViewObject];
			}
			
			[mWindow setDelegate: self];
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
				mOmcCocoaNib = [[OMCCocoaNib alloc] initWithNib:myNib];
				[myNib release];
			}
		}
	}
	else
	{//main bundle
		NSNib *myNib = [[NSNib alloc] initWithNibNamed:inNibName bundle:NULL];
		if(myNib != NULL)
		{
			mOmcCocoaNib = [[OMCCocoaNib alloc] initWithNib:myNib];
			[myNib release];
		}
	}
	return (mOmcCocoaNib != NULL);
}
/*
- (id)initWithWindow:(NSWindow *)inWindow
{
    if (![super init])
        return NULL;

    mWindow = inWindow;
	mOmcCocoaNib = NULL;
	mLastCommandID = NULL;
	mIsModal = false;
	mIsRunning = false;
	mDeleteSelfOnClose = false;

	mOMCDialogProxy.Adopt( new OMCCocoaDialog(self) );

	if(mWindow != NULL)
	{
		//[mWindow setReleasedWhenClosed:NO];
		[mWindow retain];

		id contentViewObject = [mWindow contentView];
		if( (contentViewObject != NULL) && [contentViewObject isKindOfClass:[NSView class] ] )
		{
			[self initSubview: (NSView*)contentViewObject];
		}

		[mWindow setDelegate: self];
	}

    return self;
}
*/

- (void)dealloc
{
	mOMCDialogProxy->SetController(NULL);
	
	if(mWindow != NULL)
	{
		//the window may outlive us
		//we are dying we need to unregister all delegates, targets, observers, etc
		id contentViewObject = [mWindow contentView];
		if( (contentViewObject != NULL) && [contentViewObject isKindOfClass:[NSView class] ] )
		{
			[self resetSubview: (NSView*)contentViewObject];
		}
	
		[mWindow setDelegate:NULL];//we are dying
		[mWindow release];
		mWindow = NULL;
	}

    [mOmcCocoaNib release];
    [mLastCommandID release];
    [mDialogOwnedItems release];

	[super dealloc];
}

- (void) initSubview:(NSView *)inView
{
	//init self - add self as target and action handler for all controls
	
	//matix cells first if we are a matrix
	if( [inView isKindOfClass:[NSMatrix class]] )
	{
		NSArray *cellsArray = [(NSMatrix*)inView cells];
		if(cellsArray != NULL)
		{
			int subIndex;
			int subCount = [cellsArray count];
			for(subIndex = 0; subIndex < subCount; subIndex++)
			{
				id cellObject = [cellsArray objectAtIndex:subIndex];
				if( cellObject != NULL )
				{
					bool setTarget = true;
					if( [cellObject respondsToSelector:@selector(target)] )
						if( [cellObject target] != NULL )//don't override targets preset in IB
							setTarget = false;
					
					if(setTarget)
					{
						if( [cellObject respondsToSelector:@selector(setTarget:)] )
						{
							[cellObject setTarget:self];
							if( [cellObject respondsToSelector:@selector(setAction:)] ) //only if target is ourselves we can set action
								[cellObject setAction:@selector(handleAction:)];
						}
					}
					
				}
			}
		}
	}	
	
	if( [inView isKindOfClass:[NSTableView class]] )
	{
		NSTableView *myTable = (NSTableView *)inView;
		//each table view has its own controller object which serves as data source and delegate
		OMCTableViewController *tableController = [[OMCTableViewController alloc] initWithTableView:myTable dialogController:self];

		[myTable setDataSource:tableController];
		[myTable setDelegate:tableController];

		//the table DOES NOT retain its.data() source nor delegate!
		[self keepItem: tableController];//we retain it and it will be released when this dialog controller is released
		[tableController release];

		if( [myTable target] == NULL )//don't override targets preset in IB
		{
			[myTable setTarget:self];
			//[myTable setAction:@selector(handleAction:)];
			[myTable setDoubleAction:@selector(handleDoubleClickAction:)];
		}

		//id myDelegate = [myTable delegate];
		//retainCount = [myDelegate retainCount];
		//NSLog(@"Init subview: OMC tableview controller retain count=%d", retainCount);

		//BOOL isKindOf = [myDelegate isKindOfClass:[OMCTableViewController class]];
		//BOOL isMemberOf = [myDelegate isMemberOfClass:[OMCTableViewController class]];
		//NSLog(@"Init subview: OMC tableview controller: isKindOf=%d, isMemberOf=%d", (int)isKindOf, (int)isMemberOf);

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
			if( [inView target] != NULL )//don't override targets preset in IB
				setTarget = false;

		if(setTarget)
		{
			if( [inView respondsToSelector:@selector(setTarget:)] )
			{
				[inView setTarget:self];
				if( [inView respondsToSelector:@selector(setAction:)] ) //only if target is ourselves we can set action
					[inView setAction:@selector(handleAction:)];
			}
		}
	}

	if([inView isKindOfClass:[NSTabView class] ])
	{//init tabs view recursively
		NSArray *tabViewsArray = [(NSTabView*)inView tabViewItems];
		if(tabViewsArray != NULL)
		{
			NSUInteger tabCount = [tabViewsArray count];
			NSUInteger tabIndex;
			for(tabIndex=0; tabIndex < tabCount; tabIndex++)
			{
				id oneTab = [tabViewsArray objectAtIndex:tabIndex];
				if( (oneTab != NULL) && [oneTab isKindOfClass:[NSTabViewItem class]] )
				{
					id viewObject = [(NSTabViewItem*)oneTab view];
					if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
					{
						[self initSubview:(NSView *)viewObject];
					}
				}
			}
		}
	}
	else
	{
		//init subviews recursively
		NSArray *subViewsArray = [inView subviews];
		if(subViewsArray != NULL)
		{
			int subIndex;
			int subCount = [subViewsArray count];
			for(subIndex = 0; subIndex < subCount; subIndex++)
			{
				id viewObject = [subViewsArray objectAtIndex:subIndex];
				if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
				{
					[self initSubview:(NSView *)viewObject];
				}
			}
		}
	}
}

- (void) resetSubview:(NSView *)inView
{
	//reset self - remove self as target and action handler for all controls

	//matrix cells first if we are a matrix
	if([inView isKindOfClass:[NSMatrix class] ])
	{
		NSArray *cellsArray = [(NSMatrix*)inView cells];
		if(cellsArray != NULL)
		{
			int subIndex;
			int subCount = [cellsArray count];
			for(subIndex = 0; subIndex < subCount; subIndex++)
			{
				id cellObject = [cellsArray objectAtIndex:subIndex];
				if( cellObject != NULL )
				{
					bool resetTarget = false;
					if( [cellObject respondsToSelector:@selector(target)] )
						if( [cellObject target] == self )//don't reset other targets
							resetTarget = true;

					if( resetTarget && [cellObject respondsToSelector:@selector(setTarget:)] )
					{
						[cellObject setTarget:NULL];
						if( [cellObject respondsToSelector:@selector(setAction:)] ) //only if target is ourselves we can set action
							[cellObject setAction:NULL];
					}
				}
			}
		}
	}
	
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
		NSArray *tabViewsArray = [(NSTabView*)inView tabViewItems];
		if(tabViewsArray != NULL)
		{
			NSUInteger tabCount = [tabViewsArray count];
			NSUInteger tabIndex;
			for(tabIndex=0; tabIndex < tabCount; tabIndex++)
			{
				id oneTab = [tabViewsArray objectAtIndex:tabIndex];
				if( (oneTab != NULL) && [oneTab isKindOfClass:[NSTabViewItem class]] )
				{
					id viewObject = [(NSTabViewItem*)oneTab view];
					if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
					{
						[self resetSubview:(NSView *)viewObject];
					}
				}
			}
		}
	}
	else
	{
		//reset subviews recursively
		NSArray *subViewsArray = [inView subviews];
		if(subViewsArray != NULL)
		{
			int subIndex;
			int subCount = [subViewsArray count];
			for(subIndex = 0; subIndex < subCount; subIndex++)
			{
				id viewObject = [subViewsArray objectAtIndex:subIndex];
				if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
				{
					[self resetSubview:(NSView *)viewObject];
				}
			}
		}
	}
}

- (id)findControlOrViewWithID:(NSString *)inControlID
{
	id contentViewObject = [mWindow contentView];
	if( (contentViewObject != NULL) && [contentViewObject isKindOfClass:[NSView class] ] )
	{
		NSView *contentView = (NSView*)contentViewObject;
		//return [contentView viewWithTag:aTag];
		return [self findViewInParent:contentView forControlID:inControlID];
	}
	return NULL;
}

- (id)findViewInParent:(NSView *)inParentView forControlID:(NSString *)inControlID //may return NSView or NSCell
//-(id)findViewInParent:(NSView *)inParentView forTag:(NSInteger)aTag
{
    if(inControlID == NULL)
        return NULL;

    NSInteger tagNum = [inParentView tag];
    NSString *controlID = [NSString stringWithFormat:@"%ld", (long)tagNum];
	if( controlID != NULL && [controlID isEqualToString:inControlID] )
		return inParentView;

    if( [inParentView respondsToSelector:@selector(identifier)] ) //identifier available in Mac OS X v10.7
    {
        controlID = [inParentView identifier];
        if( controlID != NULL && [controlID isEqualToString:inControlID] )
            return inParentView;
    }

	if([inParentView isKindOfClass:[NSTabView class] ])
	{//search tabs view recursively
		NSArray *tabViewsArray = [(NSTabView*)inParentView tabViewItems];
		if(tabViewsArray != NULL)
		{
			NSUInteger tabCount = [tabViewsArray count];
			NSUInteger tabIndex;
			for(tabIndex=0; tabIndex < tabCount; tabIndex++)
			{
				id oneTab = [tabViewsArray objectAtIndex:tabIndex];
				if( (oneTab != NULL) && [oneTab isKindOfClass:[NSTabViewItem class]] )
				{
					id viewObject = [(NSTabViewItem*)oneTab view];
					if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
					{
						NSView *resultView = [self findViewInParent:(NSView *)viewObject forControlID:inControlID];
						if(resultView != NULL)
							return resultView;
					}
				}
			}
		}
	}
	else if([inParentView isKindOfClass:[NSMatrix class] ])
	{
		NSArray *cellsArray = [(NSMatrix*)inParentView cells];
		if(cellsArray != NULL)
		{
			int subIndex;
			int subCount = [cellsArray count];
			for(subIndex = 0; subIndex < subCount; subIndex++)
			{
				id cellObject = [cellsArray objectAtIndex:subIndex];
				if( (cellObject != NULL) && [cellObject respondsToSelector:@selector(tag)] )
				{
                    tagNum = [cellObject tag];
                    controlID = [NSString stringWithFormat:@"%ld", (long)tagNum];
					if( controlID != NULL && [controlID isEqualToString:inControlID] )
						return cellObject;
				}
                
                if( (cellObject != NULL) && [cellObject respondsToSelector:@selector(identifier)] ) //identifier available in Mac OS X v10.7
                {
                    controlID = [cellObject identifier];
                    if( controlID != NULL && [controlID isEqualToString:inControlID] )
                        return cellObject;
                }
			}
		}
	}
	else
	{
		//search subviews recursively
		NSArray *subViewsArray = [inParentView subviews];
		if(subViewsArray != NULL)
		{
			int subIndex;
			int subCount = [subViewsArray count];
			for(subIndex = 0; subIndex < subCount; subIndex++)
			{
				id viewObject = [subViewsArray objectAtIndex:subIndex];
				if( (viewObject != NULL) && [viewObject isKindOfClass:[NSView class]] )
				{
					NSView *resultView = [self findViewInParent:(NSView *)viewObject forControlID:inControlID];
					if(resultView != NULL)
						return resultView;
				}
			}
		}
	}
	return NULL;
}

- (CFTypeRef)controlValue:(NSString *)inControlID forPart:(NSInteger)inControlPart withIterator:(SelectionIterator *)inSelIterator outProperties:(CFDictionaryRef *)outCustomProperties
{
	id myControlOrView = [self findControlOrViewWithID:inControlID];
	if( myControlOrView != NULL )
	{
		if(outCustomProperties)
		{
			NSString *escapingMode = NULL;
			if( [myControlOrView respondsToSelector:@selector(escapingMode)] )
				escapingMode = [myControlOrView escapingMode];
			
			NSString *combinedSelectionPrefix = NULL;
			if( [myControlOrView respondsToSelector:@selector(combinedSelectionPrefix)] )
				combinedSelectionPrefix = [myControlOrView combinedSelectionPrefix];
			
			NSString *combinedSelectionSuffix = NULL;
			if( [myControlOrView respondsToSelector:@selector(combinedSelectionSuffix)] )
				combinedSelectionSuffix = [myControlOrView combinedSelectionSuffix];
			
			NSString *combinedSelectionSeparator = NULL;
			if( [myControlOrView respondsToSelector:@selector(combinedSelectionSeparator)] )
				combinedSelectionSeparator = [myControlOrView combinedSelectionSeparator];
			
			if( (escapingMode != NULL) ||
				(combinedSelectionPrefix != NULL) ||
				(combinedSelectionSuffix != NULL) ||
				(combinedSelectionSeparator != NULL) )
			{
				CFMutableDictionaryRef outDict = ::CFDictionaryCreateMutable(
												kCFAllocatorDefault,
												0,
												NULL,//keyCallBacks,
												&kCFTypeDictionaryValueCallBacks );	
				*outCustomProperties = outDict;
				if(outDict != NULL)
				{
					if(escapingMode != NULL)
						::CFDictionarySetValue( outDict,
												(const void *)kCustomEscapeMethodKey,
												(const void *)(CFStringRef)escapingMode);
					
					if(combinedSelectionPrefix != NULL)
						::CFDictionarySetValue( outDict,
												(const void *)kCustomPrefixKey,
												(const void *)(CFStringRef)combinedSelectionPrefix);

					if(combinedSelectionSuffix != NULL)
						::CFDictionarySetValue( outDict,
												(const void *)kCustomSuffixKey,
												(const void *)(CFStringRef)combinedSelectionSuffix);

					if(combinedSelectionSeparator != NULL)
						::CFDictionarySetValue( outDict,
												(const void *)kCustomSeparatorKey,
												(const void *)(CFStringRef)combinedSelectionSeparator);
				}
			}
		}

		if( [myControlOrView isKindOfClass:[NSPopUpButton class]] && ![myControlOrView isKindOfClass:[OMCPopUpButton class]] )
		{
			NSPopUpButton *myPopup = (NSPopUpButton *)myControlOrView;
			NSInteger itemIndex = [myPopup indexOfSelectedItem] + 1;//0-based to 1-based
			return (CFTypeRef)[NSString stringWithFormat: @"%ld", (long)itemIndex];
		}
		else if([myControlOrView isKindOfClass:[NSPathControl class]] || [myControlOrView isKindOfClass:[NSPathCell class]])
		{
			NSURL *fileURL = [myControlOrView URL];
			if(fileURL != NULL)
			{
				NSString *filePath = [fileURL path];
				if(filePath != NULL)
					return (CFTypeRef)filePath;
			}
			return (CFTypeRef)[myControlOrView stringValue];
		}
		else if( [myControlOrView isKindOfClass:[NSText class]] )
		{
			NSText *myText = (NSText *)myControlOrView;
			return (CFTypeRef)[myText string];
		}
		else if( [myControlOrView isKindOfClass:[NSTableView class]] )
		{
			NSTableView *myTable = (NSTableView *)myControlOrView;
			id myDelegate = [myTable delegate];
			if( (myDelegate != NULL) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
			{
				if( (inSelIterator != NULL) && SelectionIterator_IsAllRows(inSelIterator) )
					return (CFTypeRef)[myDelegate allRowsForColumn:inControlPart];
				else
					return [myDelegate selectionValueForColumn:inControlPart withIterator:inSelIterator];
			}
		}
		
		//nothing else produced a value, try "stringValue"
		if( [myControlOrView respondsToSelector:@selector(stringValue)] )
		{
			return [myControlOrView stringValue];//OMC controls do their mappings internally and return proper string
		}
		
	}
	return NULL;
}

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID
{
	id myControlOrView = [self findControlOrViewWithID:inControlID];
	if( myControlOrView != NULL )
	{
		if( [myControlOrView isKindOfClass:[NSPopUpButton class]] )
		{
			NSPopUpButton *myPopup = (NSPopUpButton *)myControlOrView;
			NSScanner *strScanner = [NSScanner scannerWithString:inValue];
			int intValue = -1;
			//0-based index for popup menu items
			if( [strScanner scanInt:&intValue] && (intValue > 0) && (intValue <= [myPopup numberOfItems]) )
				[myPopup selectItemAtIndex:intValue-1];//successful conversion to number in range
			else
				[myPopup selectItemWithTitle:inValue];
		}
		else if([myControlOrView isKindOfClass:[NSPathControl class]] || [myControlOrView isKindOfClass:[NSPathCell class]])
		{
			NSURL *fileURL = [NSURL fileURLWithPath:inValue];
			if(fileURL != NULL)
				[myControlOrView setURL:fileURL];
		}
		else if( [myControlOrView respondsToSelector:@selector(setStringValue:)] )
		{
			[myControlOrView setStringValue:inValue];//OMC controls do their mappings internally
		}
		else if( [myControlOrView isKindOfClass:[NSText class]] )
		{
			NSText *myText = (NSText *)myControlOrView;
			[myText setString:inValue];
		}
	}
}

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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString*)controlID];
					if( myControlOrView != NULL )
					{
						if( [myControlOrView isKindOfClass:[NSPopUpButton class]] )
						{
							NSPopUpButton *myPopupButton = (NSPopUpButton *)myControlOrView;
							[myPopupButton removeAllItems];
						}
						else if( [myControlOrView isKindOfClass:[NSComboBox class]] )
						{
							NSComboBox *myCombo = (NSComboBox *)myControlOrView;
							[myCombo removeAllItems];
						}
					}
				}
			}
		}
	}

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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString*)controlID];
					if( myControlOrView != NULL )
					{
						CFIndex itemCount = ::CFArrayGetCount(theArr);
						if( [myControlOrView isKindOfClass:[NSPopUpButton class]] )
						{
							NSPopUpButton *myPopupButton = (NSPopUpButton *)myControlOrView;
							for(CFIndex i = 0; i < itemCount; i++)
							{
								CFTypeRef oneItem = ::CFArrayGetValueAtIndex(theArr,i);
								CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
								if(oneString != NULL)
									[myPopupButton addItemWithTitle:(NSString *)oneString];
							}
						}
						else if( [myControlOrView isKindOfClass:[NSComboBox class]] )
						{
							NSComboBox *myCombo = (NSComboBox *)myControlOrView;
							
							for(CFIndex i = 0; i < itemCount; i++)
							{
								CFTypeRef oneItem = ::CFArrayGetValueAtIndex(theArr,i);
								CFStringRef oneString = ACFType<CFStringRef>::DynamicCast( oneItem );
								if(oneString != NULL)
									[myCombo addItemWithObjectValue:(NSString *)oneString];
							}							
						}
					}
				}
			}
		}
	}

	//TODO: solve the refresh story
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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString*)controlID];
					if( (myControlOrView != NULL) && [myControlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)myControlOrView;
						id myDelegate = [myTable delegate];
						if( (myDelegate != NULL) && [myDelegate isKindOfClass:[OMCTableViewController class]] )
							[myDelegate removeRows];
					}
				}
			}
		}
	}

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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString*)controlID];
					if( (myControlOrView != NULL) && [myControlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)myControlOrView;
						id myDelegate = [myTable delegate];
						if( (myDelegate != NULL) && [myDelegate isKindOfClass:[OMCTableViewController class]] ) 
							[myDelegate addRows:theArr];
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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString*)controlID];
					if( (myControlOrView != NULL) && [myControlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)myControlOrView;
						id myDelegate = [myTable delegate];
						
						//BOOL isKindOf = [myDelegate isKindOfClass:[OMCTableViewController class]];
						//BOOL isMemberOf = [myDelegate isMemberOfClass:[OMCTableViewController class]];
						//NSLog(@"OMC tableview controller: isKindOf=%d, isMemberOf=%d", (int)isKindOf, (int)isMemberOf);
						
						if( (myDelegate != NULL) && [myDelegate isKindOfClass:[OMCTableViewController class]] ) 
							[myDelegate setColumns:theArr];
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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString*)controlID];
					if( (myControlOrView != NULL) && [myControlOrView isKindOfClass:[NSTableView class]] )
					{
						NSTableView *myTable = (NSTableView *)myControlOrView;
						id myDelegate = [myTable delegate];
						if( (myDelegate != NULL) && [myDelegate isKindOfClass:[OMCTableViewController class]] ) 
							[myDelegate setColumnWidths:theArr];
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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					[self setControlStringValue:(NSString *)ACFType<CFStringRef>::DynamicCast( valueList[i] ) forControlID:(NSString*)controlID];
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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString *)controlID];
					if(myControlOrView != NULL)
					{
						Boolean doEnable = ::CFBooleanGetValue(theVal);
						if( [myControlOrView respondsToSelector:@selector(setEnabled:)] )
								[(NSControl *)myControlOrView setEnabled:doEnable];
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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					id myControlOrView = [self findControlOrViewWithID:(NSString *)controlID];
					if( (myControlOrView != NULL) && [myControlOrView respondsToSelector:@selector(setHidden:)] )
					{
						BOOL makeVisible = (BOOL)::CFBooleanGetValue(theVal);
						[myControlOrView setHidden:(!makeVisible)];
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
					//NSInteger controlId = ::CFStringGetIntValue(theKey);
					NSView *myControlOrView = [self findControlOrViewWithID:(NSString *)controlID];
					if( (myControlOrView != NULL) && [myControlOrView respondsToSelector:@selector(setCommandID:)] )
					{
						[myControlOrView setCommandID:(NSString *)theVal];
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
						//the message targets our dialog window - wow
						[mWindow makeKeyAndOrderFront:self];//bring it to front and select
					}
					else if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_application"), 0) )
					{
						NSApplication *myApp = [NSApplication sharedApplication];
						if(myApp != NULL)
							[myApp activateIgnoringOtherApps:YES];
					}
					else
					{
						//select command for some control?
						//tab control item maybe? but does it have a tag?

						//NSInteger controlId = ::CFStringGetIntValue(theKey);
						//NSView *myControlOrView = [self findControlOrViewWithID:controlID];

						//if( (myControlOrView != NULL) && [myControlOrView respondsToSelector:@selector(setCommandID:)] )
						//{
						//	[myControlOrView setCommandID:theVal];
						//}
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
						//the message targets our dialog window - wow
						Boolean terminateOK = ::CFBooleanGetValue(theVal);
						NSString *commandID;
						if(terminateOK)
							commandID = (mEndOKSubcommandID != NULL) ? (NSString *)(CFStringRef)mEndOKSubcommandID : @"omc.dialog.ok";
						else
							commandID = (mEndCancelSubcommandID != NULL) ? (NSString *)(CFStringRef)mEndCancelSubcommandID : @"omc.dialog.cancel";
						
						if(mLastCommandID != NULL)
							[mLastCommandID release];
						mLastCommandID = [commandID retain];

#if _DEBUG_
						NSLog(@"closing dialog window=%@, retain count=%ld\n", mWindow, (long)[mWindow retainCount]);
#endif
						[mWindow close];//our windowWillClose will be called, which calls "terminate", which executes the proper termination command
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
						
						//NSInteger controlId = ::CFStringGetIntValue(theKey);
						//NSView *myControlOrView = [self findControlOrViewWithID:controlId];
						//if(myControlOrView != NULL)
						//	[myControlOrView setHidden:(BOOL)::CFBooleanGetValue(theVal)];
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
							//NSInteger controlId = ::CFStringGetIntValue(theKey);
							id myControlOrView = [self findControlOrViewWithID:(NSString *)controlID];
							
							if( (myControlOrView != NULL) && [myControlOrView isKindOfClass:[NSView class]] )
							{
								float viewHeight = NSHeight([myControlOrView bounds]);
								NSView *superView = [myControlOrView superview];
								float superHeight = NSHeight([superView bounds]);
								float bottomOrigin = superHeight - viewHeight - newTopLeftOrigin.y;
								[myControlOrView setFrameOrigin: NSMakePoint(newTopLeftOrigin.x, bottomOrigin) ];
								[myControlOrView setNeedsDisplay:YES];
								//[[myControlOrView superview] setNeedsDisplay: YES];//can it mess up the superview?
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
						id myView = [self findControlOrViewWithID:(NSString *)controlID];
						
						if( myView != NULL )
						{
							NSClipView *clipView = NULL;
							NSView *docView = NULL;
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
								
								NSView *superView = NULL;
								if(matteView != NULL)
									superView = [matteView superview];//get superview of matte view - this should be clipping view
								
								if( (superView != NULL) && [superView isKindOfClass:[NSClipView class] ] )
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
								clipView = NULL;//set to null to prevent scrolling attempts below 
							}
							else if( [myView isKindOfClass:[NSView	class]] ) 
							{//we target document view which is inside clip view, which in turn is in NSScrollView
								docView = myView;
								NSView *superView = [docView superview];
								if( [superView isKindOfClass:[NSClipView class] ] )
									clipView = (NSClipView *)superView;
							}
							
							if(clipView != NULL)
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
							//the message targets our dialog window - wow
							[mWindow setContentSize:newSize];
						}
						else
						{
							//NSInteger controlId = ::CFStringGetIntValue(theKey);
							id myControlOrView = [self findControlOrViewWithID:(NSString *)controlID];
							
							if( (myControlOrView != NULL) && [myControlOrView isKindOfClass:[NSView class]] )
							{
								[myControlOrView setFrameSize:newSize];
								[myControlOrView setNeedsDisplay:YES];
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
					id messageTarget = NULL;
					if( kCFCompareEqualTo == CFStringCompare( controlID, CFSTR("omc_window"), 0) )
					{
						//the message targets our dialog window - wow
						messageTarget = (id)mWindow;
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
						//NSInteger controlId = ::CFStringGetIntValue(theKey);
						messageTarget = [self findControlOrViewWithID:(NSString *)controlID];
					}

					if(messageTarget != NULL)
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
	[inCommandID retain];
	if(mLastCommandID != NULL)
		[mLastCommandID release];
	mLastCommandID = inCommandID;
	
	if( [self commandShouldCloseDialog] )
	{
		[mWindow close];//our windowWillClose will be called, which calls "terminate", which executes the proper termination command
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

	CFTypeRef droppedItems = nil;
	if( [sender respondsToSelector:@selector(droppedItems)] )
		droppedItems = [sender droppedItems];

	[self dispatchCommand:commandID withContext:droppedItems];
	
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
		[self dispatchCommand:commandID withContext:NULL];
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

	if(mDeleteSelfOnClose)
	{
		[self autorelease];//defer the release until the pool is destoryed. we don't want to kill ourself and the window yet. this caused crashes
	}
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
	NSLog(@"[OMCDialogController run] mWindow=%@", (id)mWindow);
#endif
	
	if( mIsModal )
	{
		
//		bool isInited = false;
		if( [self initialize] )
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
			NSModalSession session = [NSApp beginModalSessionForWindow:mWindow];
			for (;;)
			{
				if( [NSApp runModalSession:session] != NSRunContinuesResponse )
					break;

			//	CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, false);
			}
			[NSApp endModalSession:session];
#else

			[NSApp runModalForWindow:mWindow];
#endif
			
		}
	}
	else
	{
		if( [self initialize] )
			[mWindow makeKeyAndOrderFront:self];
	}
}

- (BOOL)isOkeyed
{
	
	if(mLastCommandID != NULL)
	{
		if(mEndOKSubcommandID != NULL)
			return [mLastCommandID isEqualToString:(NSString *)(CFStringRef)mEndOKSubcommandID];

		return [mLastCommandID isEqualToString:@"omc.dialog.ok"];
	}
	return false;
}

- (BOOL)isCanceled
{
	if(mLastCommandID != NULL)
	{
		if(mEndCancelSubcommandID != NULL)
			return [mLastCommandID isEqualToString:(NSString *)(CFStringRef)mEndCancelSubcommandID];

		return [mLastCommandID isEqualToString:@"omc.dialog.cancel"];
	}
	return false;
}

- (BOOL)commandShouldCloseDialog
{
	return ([self isOkeyed] || [self isCanceled]);
}


- (BOOL)initialize
{
	NSString *origCommand = mLastCommandID;//retained string we store temporarily

	mLastCommandID = @"omc.dialog.initialize";
	if(mInitSubcommandID != NULL)
		mLastCommandID = (NSString *)(CFStringRef)mInitSubcommandID;
	[mLastCommandID retain];

	mOMCDialogProxy->StartListening();

	//static initialization not needed here, the only thing here might be to find out
	//if there is a table control using the iterator. Then we would check it and create SelectionIterator in processCommand
	//Thinking again: don't do it. Delay until execution.
	//The command using iteration may never be executed so why bother right now?

/*
//static initialization first
//whatever is set in properties of controls in nib
//currently only for clock, HIImageView and ImageWell

	//edit field with lowest id gets the keyboard focus
	NibDialogControl::KeyFocusCandidate focusCandidate = { 0x7FFFFFFF, NULL };
	mUsesSelectionIterator = false;
	NibDialogControl::InitializeAllSubControls(mWindow, NULL, mCommandName, mExternBundleRef, mPlugin->GetBundleRef(), focusCandidate, mUsesSelectionIterator);

	if(focusCandidate.control != NULL)
		::SetKeyboardFocus( mWindow, focusCandidate.control, kControlFocusNextPart);
*/

	[self processCommandWithContext:NULL];

	[mLastCommandID release];
	mLastCommandID = origCommand;

	if(mPlugin->GetError() != noErr)
		return NO;//if there was an error during init command don't show the dialog

	return YES;
}

- (BOOL)terminate
{
	BOOL wasOkeyed = [self isOkeyed];
	NSString *origCommand = mLastCommandID;//retained string we store temporarily
	
	mLastCommandID = wasOkeyed ? @"omc.dialog.terminate.ok" : @"omc.dialog.terminate.cancel";

	if( wasOkeyed && (mEndOKSubcommandID != NULL) )
		mLastCommandID = (NSString *)(CFStringRef)mEndOKSubcommandID;
	else if( !wasOkeyed && (mEndCancelSubcommandID != NULL) )
		mLastCommandID = (NSString *)(CFStringRef)mEndCancelSubcommandID;

	[mLastCommandID retain];

	[self processCommandWithContext:NULL];

	[mLastCommandID release];
	mLastCommandID = origCommand;

	return YES;
}

- (OSStatus)processCommandWithContext:(CFTypeRef)inContext
{
	if(mPlugin == NULL)
		return paramErr;

	SInt32 cmdIndex = -1;
	if( IsPredefinedDialogCommandID((CFStringRef)mLastCommandID) )
		cmdIndex = mPlugin->FindSubcommandIndex(mCommandName, (CFStringRef)mLastCommandID); //only strict subcommand for predefined dialog commands
	else																//(command name must match)
		cmdIndex = mPlugin->FindCommandIndex(mCommandName, (CFStringRef)mLastCommandID);//relaxed rules for custom command id
																	//(for example when used for next command)
	if(cmdIndex < 0 )
		return eventNotHandledErr;//did not find the specified subcommand

	CommandDescription *commandList = mPlugin->GetCommandList();
	if(commandList == NULL)
		return paramErr;

	CommandDescription &currCommand = commandList[cmdIndex];
	
	SelectionIterator *oldIterator = mOMCDialogProxy->GetSelectionIterator();
	SelectionIterator *currentSelectionIterator = NULL;
	if( currCommand.multipleSelectionIteratorParams != NULL )
		currentSelectionIterator = [self createSelectionIterator:currCommand.multipleSelectionIteratorParams];

	mOMCDialogProxy->SetSelectionIterator(currentSelectionIterator);
	
	OSStatus status = noErr;

	do
	{
		status = mPlugin->ExecuteSubcommand( cmdIndex, (OMCCocoaDialog*)mOMCDialogProxy, inContext );//does not throw
	}
	while( (currentSelectionIterator != NULL) && SelectionIterator_Next(currentSelectionIterator) );

	mOMCDialogProxy->SetSelectionIterator(oldIterator);

	SelectionIterator_Release(currentSelectionIterator);
	
	return status;
}

- (id)getCFContext
{
	return (id)mPlugin->GetCFContext();
}

- (void)setWindowTopLeftPosition:(NSPoint)absolutePosition
{	
	NSRect windowFrame = [mWindow frame];
	
	NSScreen *mainScreen = [NSScreen mainScreen];
	NSRect screenRect = [mainScreen visibleFrame];

	{//absolute position
		absolutePosition.x += screenRect.origin.x;
		absolutePosition.y = screenRect.origin.y + screenRect.size.height - absolutePosition.y - windowFrame.size.height;//bottom of the window
		if( (absolutePosition.y + windowFrame.size.height) < screenRect.origin.y )
			absolutePosition.y = screenRect.origin.y - windowFrame.size.height + 20;//winodw top visible at the bottom of the screen
	}

	[mWindow setFrameOrigin:absolutePosition];
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
				[methodName appendString:(NSString *)oneString];
		}

		SEL methodSelector = NSSelectorFromString(methodName);
		NSMethodSignature *methodSig = [messageTarget methodSignatureForSelector:methodSelector];
		if( methodSig != NULL )
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
								{//only NSString */CFStringRef supprted as id/NSObject *
									if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("omc_nil"), argString, kCFCompareCaseInsensitive) )
										*(id *)stackBuff = nil;
									else
										*(CFStringRef *)stackBuff = argString;
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
										*(id *)stackBuff = nil;
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
			controlID = (NSString *)controlIDRef;
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

				assert(sizeof(unsigned long) == sizeof(NSUInteger));
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
	
	if(mDialogOwnedItems == NULL)
		mDialogOwnedItems = [[NSMutableSet alloc] initWithCapacity:0];
	
	[mDialogOwnedItems addObject:inItem];
}


@end
