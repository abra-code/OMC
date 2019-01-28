//
//  OMCInputDialogController.h
//  Abracode
//
//  Created by Tomasz Kukielka on 8/25/09.
//  Copyright 2009-2010 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface OMCInputDialogController : NSWindowController
{
	IBOutlet NSTextField *mMessageText;
	IBOutlet NSButton *mOKButton;
	IBOutlet NSButton *mCancelButton;

//only one of those connected:	
	IBOutlet NSTextField *mEditField;
	IBOutlet NSSecureTextField *mPasswordField;
	IBOutlet NSPopUpButton *mPopupButton;
	IBOutlet NSComboBox *mComboBox;
	BOOL	mIsCanceled;
	NSArray *mMenuItems;//for popup or combo - may include mappings
}

//setup
- (void)setMenuItems:(NSArray*)inMenuItems;//array of NAME & VALUE mappings
- (void)setWindowTitle:(NSString*)inTitle;
- (void)setMessageText:(NSString*)inText;
- (void)setOKButtonTitle:(NSString *)inTitle;
- (void)setCancelButtonTitle:(NSString *)inTitle;

- (BOOL)runModalDialog;
- (IBAction)closeWindow:(id)sender;

- (void)layoutControls;

- (NSString *)getChoiceString;
- (void)setDefaultChoiceString:(NSString *)inString;

@end
