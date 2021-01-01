#include "ACFURL.h"
#import <Foundation/Foundation.h>

bool DeleteFile(CFURLRef fileURL)
{
    @autoreleasepool
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        return (bool)[fileManager removeItemAtURL:(NSURL*)fileURL error:NULL];
    }
}

CFURLRef CopyPreferencesDirURL(void)
{
    @autoreleasepool
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
        [prefsURL retain];
        return (CFURLRef)prefsURL;
    }
}

CFURLRef CopyApplicationSupportDirURL(void)
{
    @autoreleasepool
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *userAppSupportDirURL = [fileManager
                                    URLForDirectory:NSApplicationSupportDirectory
                                    inDomain:NSUserDomainMask
                                    appropriateForURL:NULL
                                    create:YES
                                    error:NULL];
        [userAppSupportDirURL retain];
        return (CFURLRef)userAppSupportDirURL;
    }
}
