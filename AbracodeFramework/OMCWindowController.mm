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
#include "ACFDict.h"
#include "OMCInvoke.h"
#include "OMCObjCInvoke.h"
#include "OMCDialogControlDispatch.h"
#include <string>
#include <vector>

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

// The window controller as the target of an omc_dialog_control message: each call goes to the
// controller's method that handled the same key before the dispatcher moved to C++
class OMCWindowControllerTarget final : public OMCDialogControlTarget
{
public:
	explicit OMCWindowControllerTarget(OMCWindowController *inController) : mController(inController) { }

	void RemoveAllListItems(CFStringRef inControlID) override { [mController removeAllListItemsForControlID:(__bridge NSString *)inControlID]; }
	void SetListItems(CFStringRef inControlID, CFArrayRef inItems) override { [mController setListItems:inItems forControlID:(__bridge NSString *)inControlID]; }
	void AppendListItems(CFStringRef inControlID, CFArrayRef inItems) override { [mController appendListItems:inItems forControlID:(__bridge NSString *)inControlID]; }
	void EmptyTable(CFStringRef inControlID) override { [mController emptyTableForControlID:(__bridge NSString *)inControlID]; }
	void RemoveTableRows(CFStringRef inControlID) override { [mController removeTableRowsForControlID:(__bridge NSString *)inControlID]; }
	void SetTableRows(CFStringRef inControlID, CFArrayRef inRows) override { [mController setTableRows:inRows forControlID:(__bridge NSString *)inControlID]; }
	void AddTableRows(CFStringRef inControlID, CFArrayRef inRows) override { [mController addTableRows:inRows forControlID:(__bridge NSString *)inControlID]; }
	void SetTableColumns(CFStringRef inControlID, CFArrayRef inColumns) override { [mController setTableColumns:inColumns forControlID:(__bridge NSString *)inControlID]; }
	void SetTableColumnWidths(CFStringRef inControlID, CFArrayRef inWidths) override { [mController setTableColumnWidths:inWidths forControlID:(__bridge NSString *)inControlID]; }
	void SelectRow(CFStringRef inControlID, CFIndex inRowIndex) override { [mController selectRow:inRowIndex forControlID:(__bridge NSString *)inControlID]; }
	void SelectRowWithContent(CFStringRef inControlID, CFStringRef inText, CFIndex inColumnNumber) override
		{ [mController selectRowWithContent:(__bridge NSString *)inText column:inColumnNumber forControlID:(__bridge NSString *)inControlID]; }
	void DeselectRow(CFStringRef inControlID) override { [mController deselectRowForControlID:(__bridge NSString *)inControlID]; }

	void SetProperty(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) override
		{ [mController setPropertyKey:(__bridge NSString *)inKey jsonValue:(__bridge NSString *)inValue forControlID:(__bridge NSString *)inControlID]; }
	void SetState(CFStringRef inControlID, CFStringRef inKey, CFStringRef inValue) override
		{ [mController setStateKey:(__bridge NSString *)inKey stringOrJsonValue:(__bridge NSString *)inValue forControlID:(__bridge NSString *)inControlID]; }

	void PresentModal(CFStringRef inResourceNameOrPath, CFStringRef inOnDismissActionID) override
		{ [mController presentModalWithResourceNameOrPath:(__bridge NSString *)inResourceNameOrPath onDismissActionID:(__bridge NSString *)inOnDismissActionID]; }
	void DismissModal() override { [mController dismissModal]; }
	void PresentToast(CFStringRef inMessage, double inDuration, CFStringRef inActionTitle, CFStringRef inActionID) override
		{ [mController presentToastWithMessage:(__bridge NSString *)inMessage duration:inDuration actionTitle:(__bridge NSString *)inActionTitle actionID:(__bridge NSString *)inActionID]; }
	void DismissToast() override { [mController dismissToast]; }
	void PresentAlert(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) override
		{ [mController presentAlertWithTitle:(__bridge NSString *)inTitle message:(__bridge NSString *)inMessage buttonSpecs:(__bridge NSArray *)inButtonSpecs]; }
	void PresentConfirmationDialog(CFStringRef inTitle, CFStringRef inMessage, CFArrayRef inButtonSpecs) override
		{ [mController presentConfirmationDialogWithTitle:(__bridge NSString *)inTitle message:(__bridge NSString *)inMessage buttonSpecs:(__bridge NSArray *)inButtonSpecs]; }
	void DismissDialog() override { [mController dismissDialog]; }

	void InsertElement(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) override
		{ [mController insertElementWithParentID:inParentID json:(__bridge NSString *)inJSON container:(__bridge NSString *)inContainer positionString:(__bridge NSString *)inPosition]; }
	void InsertElementRow(CFIndex inParentID, CFStringRef inJSON, CFStringRef inContainer, CFStringRef inPosition) override
		{ [mController insertElementRowWithParentID:inParentID json:(__bridge NSString *)inJSON container:(__bridge NSString *)inContainer positionString:(__bridge NSString *)inPosition]; }
	void RemoveElement(CFIndex inViewID) override { [mController removeElementWithViewID:inViewID]; }

	void SetWindowTitle(CFStringRef inTitle) override { [mController.window setTitle:(__bridge NSString *)inTitle]; }
	void SetControlValue(CFStringRef inControlID, CFStringRef inValue, CFStringRef inContentType) override
		{ [mController setControlStringValue:(__bridge NSString *)inValue forControlID:(__bridge NSString *)inControlID contentType:(__bridge NSString *)inContentType]; }
	void SetControlEnabled(CFStringRef inControlID, bool inEnabled) override { [mController setControlEnabled:inEnabled forControlID:(__bridge NSString *)inControlID]; }
	void SetControlVisible(CFStringRef inControlID, bool inVisible) override { [mController setControlVisible:inVisible forControlID:(__bridge NSString *)inControlID]; }
	void SetCommandID(CFStringRef inControlID, CFStringRef inCommandID) override { [mController setCommandID:(__bridge NSString *)inCommandID forControlID:(__bridge NSString *)inControlID]; }

	void BringWindowToFront() override { [mController.window makeKeyAndOrderFront:mController]; }
	void ActivateApplication() override { [[NSApplication sharedApplication] activateIgnoringOtherApps:YES]; }
	void SelectControl(CFStringRef inControlID) override { [mController selectControlWithID:(__bridge NSString *)inControlID]; }

	// The window closes as its OK or Cancel would: windowWillClose: runs the matching end subcommand
	void CloseWindow(bool inOK) override
	{
		if(inOK)
			mController.currentCommandID = mController.endOKSubcommandID ?: @"omc.dialog.ok";
		else
			mController.currentCommandID = mController.endCancelSubcommandID ?: @"omc.dialog.cancel";
		[mController.window close];
	}
	void QuitApplication() override { [[NSApplication sharedApplication] terminate:mController]; }

	void SetWindowTopLeftPosition(double inLeft, double inTop) override { [mController setWindowTopLeftPosition:NSMakePoint(inLeft, inTop)]; }
	void MoveControl(CFStringRef inControlID, double inLeft, double inTop) override
		{ [mController moveControlWithID:(__bridge NSString *)inControlID toPosition:NSMakePoint(inLeft, inTop)]; }
	void ScrollControl(CFStringRef inControlID, double inLeft, double inTop) override
		{ [mController scrollControlWithID:(__bridge NSString *)inControlID toPosition:NSMakePoint(inLeft, inTop)]; }
	void SetWindowLayoutSize(double inWidth, double inHeight) override { [mController setWindowContentSize:NSMakeSize(inWidth, inHeight)]; }
	void ResizeControl(CFStringRef inControlID, double inWidth, double inHeight) override
		{ [mController resizeControlWithID:(__bridge NSString *)inControlID toSize:NSMakeSize(inWidth, inHeight)]; }

	void InvokeMessages(OMCInvokeTarget inTarget, CFArrayRef inMessages) override { OMCInvokeMessages(inTarget, (__bridge void *)mController.window, inMessages); }
	void InvokeMessagesOnControl(CFStringRef inControlID, CFArrayRef inMessages) override
		{ [mController invokeMessagesForControlID:(__bridge NSString *)inControlID messages:inMessages]; }

private:
	OMCWindowController *mController; // for the length of one message
};

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

+ (instancetype)findControllerForKeyWindow
{
    NSWindow *keyWindow = [NSApp keyWindow];
    if(keyWindow == nil)
        return nil;

    for(OMCWindowController *controller in GetAllDialogControllers())
    {
        if(controller.window == keyWindow)
            return controller;
    }
    return nil;
}

- (id)initWithOmc:(OnMyCommand *)inOmc commandRuntimeData:(CommandRuntimeData *)inCommandRuntimeData
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
    self.currentCommandID = inCommandID;
    
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
	if(self.currentCommandID != nil)
	{
		if(self.endOKSubcommandID != nil)
        {
            return [self.currentCommandID isEqualToString:self.endOKSubcommandID];
        }

		return [self.currentCommandID isEqualToString:@"omc.dialog.ok"];
	}
	return false;
}

- (BOOL)isCanceled
{
	if(self.currentCommandID != nil)
	{
		if(self.endCancelSubcommandID != nil)
        {
            return [self.currentCommandID isEqualToString:self.endCancelSubcommandID];
        }

		return [self.currentCommandID isEqualToString:@"omc.dialog.cancel"];
	}
	return false;
}

- (BOOL)commandShouldCloseDialog
{
	return ([self isOkeyed] || [self isCanceled]);
}

- (BOOL)initializeDialog
{
	NSString *origCommand = self.currentCommandID;

	self.currentCommandID = @"omc.dialog.initialize";
	if(self.dialogInitSubcommandID != nil)
    {
        self.currentCommandID = self.dialogInitSubcommandID;
    }
    
	mOMCDialogProxy->StartListening();

    [self processCommandWithContext:NULL];

	self.currentCommandID = origCommand;

	if(mPlugin->GetError() != noErr)
		return NO;

	return YES;
}

- (BOOL)terminate
{
	BOOL wasOkeyed = [self isOkeyed];
	NSString *origCommand = self.currentCommandID;
	
	self.currentCommandID = wasOkeyed ? @"omc.dialog.terminate.ok" : @"omc.dialog.terminate.cancel";

	if( wasOkeyed && (self.endOKSubcommandID != nil) )
    {
        self.currentCommandID = self.endOKSubcommandID;
    }
	else if( !wasOkeyed && (self.endCancelSubcommandID != nil) )
    {
        self.currentCommandID = self.endCancelSubcommandID;
    }
    
	[self processCommandWithContext:NULL];

    self.currentCommandID = origCommand;

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

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    if(self.windowDidActivateSubcommandID != nil)
    {
        NSString *origCommand = self.currentCommandID;
        self.currentCommandID = self.windowDidActivateSubcommandID;
        [self processCommandWithContext:NULL];
        self.currentCommandID = origCommand;
    }
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    if(self.windowDidDeactivateSubcommandID != nil)
    {
        NSString *origCommand = self.currentCommandID;
        self.currentCommandID = self.windowDidDeactivateSubcommandID;
        [self processCommandWithContext:NULL];
        self.currentCommandID = origCommand;
    }
}

- (OSStatus)processCommandWithContext:(CFTypeRef)inContext
{
	if(mPlugin == nullptr)
    {
        return paramErr;
    }
    
	SInt32 cmdIndex = -1;
    if(OMCDialog::IsPredefinedDialogCommandID((__bridge CFStringRef)self.currentCommandID))
    {
        cmdIndex = mPlugin->FindSubcommandIndex(mCommandName, (__bridge CFStringRef)self.currentCommandID);
    }
	else
    {
        cmdIndex = mPlugin->FindCommandIndex(mCommandName, (__bridge CFStringRef)self.currentCommandID);
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

- (void)setControlContextViewID:(NSInteger)viewID viewPartID:(NSInteger)viewPartID contextString:(NSString *)contextString
{
    if(mCommandRuntimeData == nullptr)
        return;
    mCommandRuntimeData->controlContextViewID     = static_cast<CFIndex>(viewID);
    mCommandRuntimeData->controlContextViewPartID = static_cast<CFIndex>(viewPartID);
    if(contextString != nil)
        mCommandRuntimeData->controlContextJSON.Adopt((__bridge CFStringRef)contextString, kCFObjRetain);
    else
        mCommandRuntimeData->controlContextJSON = nullptr;
}

- (void)clearControlContext
{
    if(mCommandRuntimeData == nullptr)
        return;
    mCommandRuntimeData->controlContextViewID     = -1;
    mCommandRuntimeData->controlContextViewPartID = -1;
    mCommandRuntimeData->controlContextJSON       = nullptr;
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

#pragma mark - setControlValues: shared implementation

// The omc_dialog_control message, handled by the portable dispatcher (OMCDialogControlDispatch.h),
// which calls this controller's methods through OMCWindowControllerTarget
- (void)setControlValues:(CFDictionaryRef)inControlDict
{
    OMCWindowControllerTarget target(self);
    OMCDispatchDialogControlMessage(inControlDict, target);
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

// The size a script asks for is the area the dialog's content lays out in. Subclasses whose
// content view is larger than that (a full-size content view spans the titlebar) convert here.
- (void)setWindowContentSize:(NSSize)inContentSize
{
	[self.window setContentSize:inContentSize];
}


- (void)invokeMessages:(CFArrayRef)messages onTarget:(id)target
{
    OMCSendObjCMessages(target, messages);
}


#pragma mark - Abstract methods (no-op defaults)

- (void)setControlStringValue:(NSString *)inValue forControlID:(NSString *)inControlID contentType:(NSString *)contentType {
    NSLog(@"[OMCWindowController stub] setControlStringValue:forControlID: %@", inControlID);
}
- (void)setControlEnabled:(BOOL)enabled forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setControlEnabled:%d forControlID: %@", enabled, inControlID);
}
- (void)setControlVisible:(BOOL)visible forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setControlVisible:%d forControlID: %@", visible, inControlID);
}

- (void)removeAllListItemsForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] removeAllListItemsForControlID: %@", inControlID);
}
- (void)setListItems:(CFArrayRef)items forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setListItems:forControlID: %@", inControlID);
}
- (void)appendListItems:(CFArrayRef)items forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] appendListItems:forControlID: %@", inControlID);
}

- (void)emptyTableForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] emptyTableForControlID: %@", inControlID);
}
- (void)removeTableRowsForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] removeTableRowsForControlID: %@", inControlID);
}
- (void)setTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setTableRows:forControlID: %@", inControlID);
}
- (void)addTableRows:(CFArrayRef)rows forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] addTableRows:forControlID: %@", inControlID);
}
- (void)setTableColumns:(CFArrayRef)columns forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setTableColumns:forControlID: %@", inControlID);
}
- (void)setTableColumnWidths:(CFArrayRef)widths forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setTableColumnWidths:forControlID: %@", inControlID);
}

- (void)selectRow:(NSInteger)rowIndex forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] selectRow:%ld forControlID: %@", (long)rowIndex, inControlID);
}
- (void)selectRowWithContent:(NSString *)text column:(NSInteger)columnNumber forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] selectRowWithContent:%@ column:%ld forControlID: %@", text, (long)columnNumber, inControlID);
}
- (void)deselectRowForControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] deselectRowForControlID: %@", inControlID);
}

- (void)selectControlWithID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] selectControlWithID: %@", inControlID);
}
- (void)setCommandID:(NSString *)commandID forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setCommandID:%@ forControlID: %@", commandID, inControlID);
}
- (void)moveControlWithID:(NSString *)inControlID toPosition:(NSPoint)position {
    NSLog(@"[OMCWindowController stub] moveControlWithID: %@", inControlID);
}
- (void)resizeControlWithID:(NSString *)inControlID toSize:(NSSize)size {
    NSLog(@"[OMCWindowController stub] resizeControlWithID: %@", inControlID);
}
- (void)scrollControlWithID:(NSString *)inControlID toPosition:(NSPoint)position {
    NSLog(@"[OMCWindowController stub] scrollControlWithID: %@", inControlID);
}

- (void)invokeMessagesForControlID:(NSString *)inControlID messages:(CFArrayRef)messages {
    NSLog(@"[OMCWindowController stub] invokeMessagesForControlID: %@", inControlID);
}
- (void)setPropertyKey:(NSString *)propertyKey jsonValue:(NSString *)jsonValue forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setPropertyKey:%@ jsonValue:%@ forControlID: %@", propertyKey, jsonValue, inControlID);
}
- (void)setStateKey:(NSString *)stateKey stringOrJsonValue:(NSString *)value forControlID:(NSString *)inControlID {
    NSLog(@"[OMCWindowController stub] setStateKey:%@ value:%@ forControlID: %@", stateKey, value, inControlID);
}

- (void)presentModalWithResourceNameOrPath:(NSString *)resourceNameOrPath onDismissActionID:(NSString *)onDismissActionID {
    NSLog(@"[OMCWindowController stub] presentModalWithResourceNameOrPath: %@ — not supported by this window controller", resourceNameOrPath);
}
- (void)dismissModal {
    NSLog(@"[OMCWindowController stub] dismissModal — not supported by this window controller");
}
- (void)presentToastWithMessage:(NSString *)message duration:(NSTimeInterval)duration actionTitle:(NSString *)actionTitle actionID:(NSString *)actionID {
    NSLog(@"[OMCWindowController stub] presentToastWithMessage: %@ — not supported by this window controller", message);
}
- (void)dismissToast {
    NSLog(@"[OMCWindowController stub] dismissToast — not supported by this window controller");
}
- (void)presentAlertWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs {
    NSLog(@"[OMCWindowController stub] presentAlertWithTitle: %@ — not supported by this window controller", title);
}
- (void)presentConfirmationDialogWithTitle:(NSString *)title message:(NSString *)message buttonSpecs:(NSArray *)buttonSpecs {
    NSLog(@"[OMCWindowController stub] presentConfirmationDialogWithTitle: %@ — not supported by this window controller", title);
}
- (void)dismissDialog {
    NSLog(@"[OMCWindowController stub] dismissDialog — not supported by this window controller");
}
- (void)insertElementWithParentID:(NSInteger)parentID json:(NSString *)json container:(NSString *)container positionString:(NSString *)positionStr {
    NSLog(@"[OMCWindowController stub] insertElementWithParentID:%ld — not supported by this window controller", (long)parentID);
}
- (void)insertElementRowWithParentID:(NSInteger)parentID json:(NSString *)json container:(NSString *)container positionString:(NSString *)positionStr {
    NSLog(@"[OMCWindowController stub] insertElementRowWithParentID:%ld — not supported by this window controller", (long)parentID);
}
- (void)removeElementWithViewID:(NSInteger)viewID {
    NSLog(@"[OMCWindowController stub] removeElementWithViewID:%ld — not supported by this window controller", (long)viewID);
}

@end
