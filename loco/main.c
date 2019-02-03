#include <CoreFoundation/CoreFoundation.h>
#include <unistd.h>

//objects allocated in this code are not released because everything will go away together when it quits.

//loco [-bundle path/to/bundle] [-table Localizable] "My String"
int main (int argc, const char * argv[])
{
	CFStringRef localizedString = NULL;
	CFStringRef keyString = NULL;
	CFStringRef tableName = NULL;
	CFStringRef bundlePath = NULL;
	CFURLRef bundleURL = NULL;

	int paramIndex = 1;
	int stringIndex = argc-1;//the last one is supposed to be the string, so check params first
	const char *param;

	while(paramIndex < stringIndex )//read key+value pairs of params
	{
		param = argv[paramIndex++];
		if( strcmp(param, "-bundle") == 0 )
		{
			param = argv[paramIndex++];
			bundlePath = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
		}
		else if( strcmp(param, "-table") == 0 )
		{
			param = argv[paramIndex++];
			tableName = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
		}
		else
		{
			fprintf(stderr, "Usage: loco [-bundle path/to/bundle] [-table \"Localizable\"] \"My String\"\n\n");
			return -1;
		}
	}
	
	if(paramIndex == stringIndex)
	{
		param = argv[paramIndex];
		keyString = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
	}

	if(keyString == NULL)
	{
		fprintf(stderr, "Usage: loco [-bundle path/to/bundle] [-table \"Localizable\"] \"My String\"\n\n");
		return -1;
	}

	if(tableName == NULL)
		tableName = CFSTR("Localizable");

	if(bundlePath == NULL)
	{
		char *currWorkingDir = getcwd(NULL, 0);
		if (currWorkingDir != NULL)
		{
			//fprintf(stdout, currWorkingDir);
			bundlePath = CFStringCreateWithCString(kCFAllocatorDefault, currWorkingDir, kCFStringEncodingUTF8);
			free(currWorkingDir);
			if(bundlePath != NULL)
			{	//try to find if current working dir is somewhere in some bundle
				//for example /Applications/MyDroplet.app/Contents/Resources/
				
				//this algorithm takes into acccount that there might a bundle within a bundle.
				//we try to find the deepest one where we currently are
				CFIndex longestPath = 0;
				CFIndex origPathLength = CFStringGetLength(bundlePath);

				if( CFStringHasSuffix(bundlePath, CFSTR(".app")) ||
					CFStringHasSuffix(bundlePath, CFSTR(".omc")) ||
					CFStringHasSuffix(bundlePath, CFSTR(".plugin")) || 
					CFStringHasSuffix(bundlePath, CFSTR(".bundle")) ||
					CFStringHasSuffix(bundlePath, CFSTR(".framework")) )
				{
					longestPath = origPathLength;
				}
				else if( CFStringHasSuffix(bundlePath, CFSTR("/Contents")) )
				{//if we are right in "Contents" subfolder and there is no trailing slash in the path
					const CFIndex kContentsWithSlashLenth = 1 + 8;
					CFIndex pathLength = origPathLength;
					if(pathLength > kContentsWithSlashLenth )
					{
						pathLength -= kContentsWithSlashLenth;
						longestPath = (pathLength > longestPath) ? pathLength : longestPath;
					}
				}

				if(longestPath < origPathLength)
				{
					CFRange contentsRange = CFStringFind(bundlePath, CFSTR("/Contents/"), kCFCompareBackwards);
					
					if( (contentsRange.length > 0) && (contentsRange.location > 0) )
					{
						longestPath = contentsRange.location;
					}
				}

				if(longestPath < origPathLength)
				{
					//check if we are inside a framework
					CFRange contentsRange = CFStringFind(bundlePath, CFSTR(".framework/Versions/"), kCFCompareBackwards);
					if( (contentsRange.length > 0) && (contentsRange.location > 0) )//found
					{
						//we found the location of ".framework". Move it forward to include this extension
						const CFIndex kCFFrameworkAndDotLength = 1 + 9;
						CFIndex pathLength = contentsRange.location + kCFFrameworkAndDotLength;
						longestPath = (pathLength > longestPath) ? pathLength : longestPath;
					}
				}
				
				if(longestPath > 0)
				{
					bundlePath = CFStringCreateWithSubstring(kCFAllocatorDefault, bundlePath, CFRangeMake(0, longestPath) );
				}
			}
		}
	}

	if(bundlePath != NULL)
	{
		bundleURL = CFURLCreateWithFileSystemPath (
								kCFAllocatorDefault,
								bundlePath,
								kCFURLPOSIXPathStyle,
								true //isDirectory
								);

		if(bundleURL != NULL)
		{
			CFBundleRef myBundle = CFBundleCreate(kCFAllocatorDefault, bundleURL);
			if(myBundle != NULL)
				localizedString = CFBundleCopyLocalizedString(myBundle, keyString, keyString, tableName);
		}
	}

	if(localizedString == NULL)
		localizedString = keyString;
	
	
	CFIndex uniCount = CFStringGetLength(localizedString);
	CFIndex maxCount = CFStringGetMaximumSizeForEncoding( uniCount, kCFStringEncodingUTF8 );
	char *buff = malloc(maxCount + 1);
	buff[0] = 0;
	Boolean success = CFStringGetCString (localizedString, buff, maxCount+1, kCFStringEncodingUTF8);
	if(success)
	{
		fprintf(stdout, buff);
		fprintf(stdout, "\n");
	}
	else
	{
		fprintf(stderr, "ERROR: CFStringGetCString() unexpectedly failed\n\n");
		return -1;
	}
	
    return 0;
}
