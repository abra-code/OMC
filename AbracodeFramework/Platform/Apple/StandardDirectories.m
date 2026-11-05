//
//  StandardDirectories.m
//  Abracode
//
//  macOS implementation of Platform/StandardDirectories.h, over NSFileManager.
//  The per-user folders live in ~/Library here; a Linux implementation uses the XDG folders.
//

#include "StandardDirectories.h"
#import <Foundation/Foundation.h>

CFURLRef CopyPreferencesDirURL(void)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *userLibraryDirURL = [fileManager
                                URLForDirectory:NSLibraryDirectory
                                inDomain:NSUserDomainMask
                                appropriateForURL:NULL
                                create:YES
                                error:NULL];
    if(userLibraryDirURL == NULL)
        return NULL;

    NSURL *prefsURL = [userLibraryDirURL URLByAppendingPathComponent:@"Preferences" isDirectory:YES];
    return (CFURLRef)CFBridgingRetain(prefsURL);
}

CFURLRef CopyApplicationSupportDirURL(void)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *userAppSupportDirURL = [fileManager
                                URLForDirectory:NSApplicationSupportDirectory
                                inDomain:NSUserDomainMask
                                appropriateForURL:NULL
                                create:YES
                                error:NULL];
    return (CFURLRef)CFBridgingRetain(userAppSupportDirURL);
}
