//
//  OMCWindowController.m
//  Abracode
//
//  Created by Tomasz Kukielka on 1/20/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import "OMCWindowController.h"
#import "OMCDialog.h"
#include "OnMyCommand.h"
#include "CommandRuntimeData.h"

static NSMutableSet<OMCWindowController *> *
GetAllDialogControllers()
{
    static NSMutableSet<OMCWindowController *> *sAllDialogControllers = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sAllDialogControllers = [[NSMutableSet alloc] init];
    });

    return sAllDialogControllers;
}

@implementation OMCWindowController

+ (instancetype)findControllerByUUID:(NSString *)uuid
{
    for(OMCWindowController *controller in GetAllDialogControllers())
    {
        CFStringRef controllerUUID = controller->mOMCDialogProxy->GetDialogUUID();
        if(controllerUUID != NULL && [uuid isEqualToString:(__bridge NSString *)controllerUUID])
            return controller;
    }
    return nil;
}

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

	mExternBundleRef.Adopt(inOmc->GetCurrentCommandExternBundle(), kCFObjRetain);

	CommandDescription &currCommand = mPlugin->GetCurrentCommand();
	mCommandName.Adopt(currCommand.name, kCFObjRetain);

    NSMutableSet<OMCWindowController *> *allDialogControllers = GetAllDialogControllers();
    [allDialogControllers addObject:self];

    return self;
}

- (void)dispatchCommand:(NSString *)inCommandID withContext:(CFTypeRef)inContext
{
    self.lastCommandID = inCommandID;
    
    if( [self commandShouldCloseDialog] )
    {
        // our windowWillClose will be called, which calls "terminate", which executes the proper termination command
        [self.window close];
    }
    else
    {
        [self processCommandWithContext:inContext];
    }
}

- (OMCDialog *)getOMCDialog
{
	return mOMCDialogProxy;
}

- (Boolean)isModal
{
	return mIsModal;
}

- (void)run
{
#if DEBUG
	NSLog(@"[OMCWindowController run] self.window=%@", (id)self.window);
#endif
	
	if( mIsModal )
	{
		if( [self initializeDialog] )
		{
			[NSApp runModalForWindow:self.window];
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
		return NO;

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

- (void)windowWillClose:(NSNotification *)notification
{
	if( mIsModal )
	{
		[NSApp stopModal];
	}

	[self terminate];

    NSMutableSet<OMCWindowController *> *allDialogControllers = GetAllDialogControllers();
    [allDialogControllers removeObject:self];
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
        cmdIndex = mPlugin->FindSubcommandIndex(mCommandName, (__bridge CFStringRef)self.lastCommandID);
    }
	else
    {
        cmdIndex = mPlugin->FindCommandIndex(mCommandName, (__bridge CFStringRef)self.lastCommandID);
    }
    
	if(cmdIndex < 0)
    {
        return errAEEventNotHandled;
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
		status = mPlugin->ExecuteSubcommand( cmdIndex, mCommandRuntimeData, inContext );
	}
	while( (currentSelectionIterator != nullptr) && SelectionIterator_Next(currentSelectionIterator) );

	mOMCDialogProxy->SetSelectionIterator(oldIterator);

	SelectionIterator_Release(currentSelectionIterator);
	
	return status;
}

-(void)keepItem:(id)inItem
{
	if(inItem == NULL)
		return;
	
	if(self.dialogOwnedItems == NULL)
        self.dialogOwnedItems = [[NSMutableSet alloc] init];
	
	[self.dialogOwnedItems addObject:inItem];
}

// Stub in base class, concrete sublass implements appropriate logic
- (SelectionIterator *)createSelectionIterator:(CFDictionaryRef)inIteratorParams
{
    return nil;
}

@end
