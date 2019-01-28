//
//  OMCCommandExecutor.h
//  Abracode
//
//  Created by Tomasz Kukielka on 4/6/08.
//  Copyright 2008 Abracode. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface OMCCommandExecutor : NSObject
{
}

+ (OSStatus)runCommand:(NSString *)inCommandNameOrId forCommandFile:(NSString *)inFileName withContext:(id)inContext useNavDialog:(BOOL)useNavDialog delegate:(id)delegate;
+ (CFPropertyListRef)cachedPlistForCommandFile:(NSString *)inFileName;
+ (CFPropertyListRef)cachedPlistForURL:(NSURL *)inURL;

@end
