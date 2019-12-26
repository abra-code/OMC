//
//  OMCSingleCommand.h
//  Abracode
//
//  Created by Tomasz Kukielka on 4/5/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>

IB_DESIGNABLE
@interface OMCSingleCommand : NSObject <NSCoding>
{
	NSString *	_commandFilePath;
}

@property (nonatomic, retain) IBInspectable NSString * commandID;
@property (nonatomic, retain) IBInspectable NSString * commandFilePath;

- (void)execute:(id)sender;

@end
