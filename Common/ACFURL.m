#include "ACFURL.h"
#import <Foundation/Foundation.h>

bool DeleteFile(CFURLRef fileURL)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return (bool)[fileManager removeItemAtURL:(__bridge NSURL*)fileURL error:NULL];
 }

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
