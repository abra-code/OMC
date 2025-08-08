//**************************************************************************************
// Filename:	OneObjProperties.cp
//
// Description:	Analyzing file properties
//
//**************************************************************************************


#include "OneObjProperties.h"
#include "CommandDescription.h"
#include "OMCStrings.h"
#include "ACFArr.h"
#include "ACFDict.h"
#include "DebugSettings.h"


// all objects must meet the condition checked by procedure: logical AND

Boolean
CheckAllObjects(std::vector<OneObjProperties> &objList, ObjCheckingProc inProcPtr, void *inProcData)
{
	if(inProcPtr == nullptr)
    {
        return false;
    }
    
    size_t elemCount = objList.size();
    if(elemCount == 0)
    {
        return false;
    }

	for(size_t i = 0; i < elemCount; i++)
	{
		if(false == (*inProcPtr)( &objList[i], inProcData ) )
			return false;
	}

	return true;
}

Boolean
CheckIfFile(OneObjProperties *inObj, void *)
{
	return inObj->isRegularFile;
}

Boolean
CheckIfFolder(OneObjProperties *inObj, void *)
{
	return inObj->isDirectory;
}

Boolean
CheckIfFileOrFolder(OneObjProperties *inObj, void *)
{
	return (inObj->isRegularFile || inObj->isDirectory);
}

Boolean
CheckIfPackage(OneObjProperties *inObj, void *)
{
	return inObj->isPackage;
}

Boolean
CheckFileType(OneObjProperties *inObj, void *inData)
{
	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;

	if( commDesc->activationTypes == NULL )
		return true;

	if( commDesc->activationTypeCount == 0)
		return true;
	
	/* we don't support file type match anymore
	for(UInt32 i = 0; i < commDesc->activationTypeCount; i++)
	{
		if( commDesc->activationTypes[i] == inObj->mType )
		{
			return true;//a match was found
		}
	}
	*/

	return false;
}

Boolean
CheckExtension(OneObjProperties *inObj, void *inData)
{
//	TRACE_CSTR("OnMyCommandCM. CheckExtension\n" );

	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;

	if(commDesc->activationExtensions == NULL)
		return true;//no extensions required - treat it as a match
	
	ACFArr extensions(commDesc->activationExtensions);
	CFIndex theCount = extensions.GetCount();
	
	if(theCount == 0)
		return true;//no extensions required - treat it as a match

	if(inObj->extension == NULL)
		return false;//no extension - it cannot be matched
	
	CFIndex	theLen = ::CFStringGetLength(inObj->extension);
	if(theLen == 0)
		return false;//no extension - it cannot be matched
	
	CFStringRef theExt;
	
	for(CFIndex i = 0; i < theCount; i++)
	{
		if( extensions.GetValueAtIndex(i, theExt) &&
			(kCFCompareEqualTo == ::CFStringCompare( inObj->extension, theExt, kCFCompareCaseInsensitive)) )
		{
			return true;//a match found
		}
	}
	return false;
}

Boolean
CheckFileTypeOrExtension(OneObjProperties *inObj, void *inData)
{
	return (CheckFileType(inObj, inData) || CheckExtension(inObj, inData));
}

Boolean
CheckFileNameMatch(OneObjProperties *inObj, void *inData)
{
	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;
	CFObj<CFStringRef> fileName( CreateObjName(inObj, NULL) );
	return DoStringsMatch(commDesc->contextMatchString, fileName, commDesc->matchMethod, (CFStringCompareFlags)commDesc->matchCompareOptions);
}

Boolean
CheckFilePathMatch(OneObjProperties *inObj, void *inData)
{
	if(inData == NULL) return false;
	CommandDescription *commDesc = (CommandDescription *)inData;
	CFObj<CFStringRef> filePath( CreateObjPath(inObj, NULL) );
	return DoStringsMatch(commDesc->contextMatchString, filePath, commDesc->matchMethod, (CFStringCompareFlags)commDesc->matchCompareOptions);
}

#pragma mark -

CFStringRef
CreateObjPath(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
 		return ::CFURLCopyFileSystemPath(inObj->url, kCFURLPOSIXPathStyle);

 	return nullptr;
}

CFStringRef
CreateObjPathNoExtension(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingPathExtension( kCFAllocatorDefault, inObj->url ) );
		if(newURL != nullptr)
 			return ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
	}
	return nullptr;
}


CFStringRef
CreateParentPath(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
 		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, inObj->url ) );
		if(newURL != nullptr)
 			return ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle);
	}
	return nullptr;
}


CFStringRef
CreateObjName(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
		return ::CFURLCopyLastPathComponent(inObj->url);

	return nullptr;
}

CFStringRef
CreateObjNameNoExtension(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
		CFObj<CFURLRef> newURL( ::CFURLCreateCopyDeletingPathExtension( kCFAllocatorDefault, inObj->url ) );
		if(newURL != nullptr)
			return ::CFURLCopyLastPathComponent(newURL);
	}
	return nullptr;
}


CFStringRef
CreateObjExtensionOnly(OneObjProperties *inObj, void *) noexcept
{//we already have the extension in our data
	if((inObj != nullptr) && (inObj->extension != nullptr))
		return ::CFStringCreateCopy(kCFAllocatorDefault, inObj->extension);

	return nullptr;
}


CFStringRef
CreateObjDisplayName(OneObjProperties *inObj, void *) noexcept
{
	if((inObj != nullptr) && (inObj->url != nullptr))
	{
		CFStringRef displayName = nullptr;
		Boolean isOK = CFURLCopyResourcePropertyForKey(inObj->url, kCFURLLocalizedNameKey, &displayName, nullptr);
		if(isOK)
			return displayName;
	}
	return nullptr;
}

CFStringRef
CreateObjPathRelativeToBase(OneObjProperties *inObj, void *ioParam) noexcept
{
	if(ioParam == nullptr)
	{//no base is provided, fall back to full path
		return CreateObjPath(inObj, nullptr);
	}

	CFStringRef commonParentPath = (CFStringRef)ioParam;

	if((inObj != nullptr) && (inObj->url != nullptr))
  	{
 		CFObj<CFStringRef> fullPath( ::CFURLCopyFileSystemPath(inObj->url, kCFURLPOSIXPathStyle) );
 		if(fullPath != nullptr)
 		{
 			//at this point we assume that fullPath starts with commonParentPath
 			//we do not check it
 			CFRange theRange;
 			theRange.location = 0;
			theRange.length = ::CFStringGetLength(commonParentPath);

			//relative path will not be longer than full path
			CFMutableStringRef	relPath = ::CFStringCreateMutableCopy(kCFAllocatorDefault, ::CFStringGetLength(fullPath), fullPath);
 			::CFStringDelete(relPath, theRange);//delete the first part of the path which we assume is the same as base path
 			return relPath;
 		}
 	}
 	return nullptr;
}


CFStringRef
CreateStringFromListOrSingleObject( OneObjProperties *inObjList, CFIndex inObjCount, CFIndex inCurrIndex,
									CreateObjProc inObjProc, void *ioParam,
									CFStringRef inMultiSeparator, CFStringRef inPrefix, CFStringRef inSuffix,
									UInt16 escSpecialCharsMode )
{
	if(inObjList == NULL)
		return NULL;

	OneObjProperties *oneObj;
	CFStringRef newStrRef = NULL;

	if(inCurrIndex == -1)//process all together
	{
		CFMutableStringRef mutableStr = ::CFStringCreateMutable(kCFAllocatorDefault, 0);
		for(CFIndex i = 0; i < inObjCount; i++)
		{
			oneObj = inObjList + i;
			newStrRef = (*inObjProc)( oneObj, ioParam );
			
			if(newStrRef != NULL)
			{
				CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
				if(cpyStrRef != NULL)
				{
					CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
					newStrRef = cpyStrRef;
				}
				
				CFObj<CFStringRef> newDel(newStrRef);

				if(inPrefix != NULL)
				{
					::CFStringAppend( mutableStr, inPrefix );
				}
				
				::CFStringAppend( mutableStr, newStrRef );
				
				if(inSuffix != NULL)
				{
					::CFStringAppend( mutableStr, inSuffix );
				}

				if( (inMultiSeparator != NULL) && i < (inObjCount-1) )
				{//add separator, but not after the last item
					::CFStringAppend( mutableStr, inMultiSeparator );
				}
			}
		}
		newStrRef = mutableStr;//assign new string to our main variable
	}
	else if(inCurrIndex < inObjCount)
	{//process just one
		oneObj = inObjList + inCurrIndex;
		newStrRef = (*inObjProc)( oneObj, ioParam );

		if( newStrRef != NULL )
  		{
  			CFStringRef  cpyStrRef = CreateEscapedStringCopy(newStrRef, escSpecialCharsMode);
			if(cpyStrRef != NULL)
			{
				CFObj<CFStringRef> strDel(newStrRef);//we have a copy, we may dispose of the original
				newStrRef = cpyStrRef;
			}
		}
	}

	return newStrRef;
}


CFStringRef
CreateCommonParentPath(OneObjProperties *inObjList, CFIndex inObjCount )
{
	if( (inObjList == nullptr) || (inObjCount == 0) )
		return nullptr;

	OneObjProperties *oneObj;
	std::vector<CFMutableArrayRef> arrayList(inObjCount);
	memset(arrayList.data(), 0, inObjCount*sizeof(CFMutableArrayRef));

//create parent paths starting from branches, going to the root,
//putting in reverse order, so it will be easier to iterate from the root later
	for (CFIndex i = 0; i < inObjCount; i++)
	{
		oneObj = inObjList + i;

		CFMutableArrayRef pathsArray = ::CFArrayCreateMutable( kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks );
		arrayList[i] = pathsArray;
		if(pathsArray != nullptr)
		{
			CFURLRef newURL = (oneObj->url != nullptr) ? CFURLCopyAbsoluteURL(oneObj->url) : nullptr;

			//we dispose of all these URLs, we leave only strings derived from them
 			while(newURL != nullptr)
 			{
 				CFObj<CFURLRef> urlDel(newURL);//delete previous when we are done
				newURL = ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, newURL );
				if(newURL != nullptr)
				{
					CFObj<CFStringRef> aPath( ::CFURLCopyFileSystemPath(newURL, kCFURLPOSIXPathStyle) );
					::CFArrayInsertValueAtIndex( pathsArray, 0, aPath.Get());//grand parent is inserted in front

					if( kCFCompareEqualTo == ::CFStringCompare( CFSTR("/"), aPath.Get(), 0) ) //we reached the top
					{	
						::CFRelease(newURL);//delete current URL and end the loop
						newURL = nullptr;
					}
				}
			}
		}
	}

//get minimum count of parent folders in all our paths
	CFIndex minCount = 0x7FFFFFFF;
	for(CFIndex i = 0; i < inObjCount; i++)
	{
		if(arrayList[i] != nullptr)
		{
			CFIndex theCount = ::CFArrayGetCount(arrayList[i]);
			if(theCount < minCount)
				minCount = theCount;
		}
		else
		{
			minCount = 0;
			break;
		}
	}

	CFStringRef commonParentPath = nullptr;

//find common parent
	if( (minCount > 0) && (minCount < 0x7FFFFFFF) )
	{//if minimum count is valid
	//at this point, all items in arrayList are non-NULL
        CFIndex commonPathLevel = 0;
		for( CFIndex pathLevel = 0; pathLevel < minCount; pathLevel++ )
		{
			//check given path level for each object
			CFTypeRef theItem = ::CFArrayGetValueAtIndex( arrayList[0], pathLevel);
			CFStringRef firstPath = ACFType<CFStringRef>::DynamicCast(theItem);
			Boolean allEqual = true;
			for(CFIndex i = 1; i < inObjCount; i++)
			{
				theItem = ::CFArrayGetValueAtIndex( arrayList[i], pathLevel);
				CFStringRef anotherPath = ACFType<CFStringRef>::DynamicCast(theItem);
				if( (firstPath != NULL) && (anotherPath != NULL) &&
					kCFCompareEqualTo != ::CFStringCompare( firstPath, anotherPath, 0 ) )
				{
					allEqual = false;
					break;
				}
			}
			
			if(allEqual == true)
			{//all paths are equal at this level
				commonPathLevel = pathLevel;
			}
			else
			{//we went too far, do not check any further
				break;
			}
		}

		CFTypeRef commonLevelItem = ::CFArrayGetValueAtIndex( arrayList[0], commonPathLevel);
		commonParentPath = ACFType<CFStringRef>::DynamicCast(commonLevelItem);
		//Assert(commonParentPath != NULL);
		
		if(commonParentPath != nullptr)
		{
			//add slash at the end of parent path unless it is a root folder which has it already
			if( kCFCompareEqualTo == ::CFStringCompare( commonParentPath, CFSTR("/"), 0 ) )
			{
				::CFRetain(commonParentPath);//prevent from deleting, we return this string
			}
			else
			{//we are adding just one character
				CFMutableStringRef	modifStr = ::CFStringCreateMutableCopy( kCFAllocatorDefault,
																		::CFStringGetLength(commonParentPath)+1,
																		commonParentPath );
				if(modifStr != nullptr)
				{
					::CFStringAppend( modifStr, CFSTR("/") );
					commonParentPath = modifStr;
				}
				else
					commonParentPath = nullptr;//failed
			}

			DEBUG_CFSTR( commonParentPath );
		}
	}

//dispose of path arrays
	for(CFIndex i = 0; i < inObjCount; i++)
	{
		if(arrayList[i] != nullptr)
		{
			::CFRelease( arrayList[i] );
			arrayList[i] = nullptr;
		}
	}
	
	return commonParentPath;
}


OSStatus
CFURLCheckFileOrFolder(CFURLRef inURLRef, size_t index, void *ioData)
{
    if( (inURLRef == nullptr) || (ioData == nullptr) )
        return paramErr;

    std::vector<OneObjProperties> &objectList = *(std::vector<OneObjProperties> *)ioData;

    if(index < objectList.size())
    {
        OneObjProperties& objProperties = objectList[index];
        objProperties.url.Adopt(inURLRef, kCFObjRetain);
        objProperties.extension.Adopt(CFURLCopyPathExtension(inURLRef));
        
        const void* keys[] = { kCFURLIsRegularFileKey, kCFURLIsDirectoryKey, kCFURLIsPackageKey };
        CFObj<CFArrayRef> propertyKeys(CFArrayCreate(kCFAllocatorDefault, keys, sizeof(keys)/sizeof(const void*), &kCFTypeArrayCallBacks));
        CFObj<CFDictionaryRef> fileProperties(CFURLCopyResourcePropertiesForKeys(inURLRef, propertyKeys, nullptr));

        ACFDict propertyDict(fileProperties);
        propertyDict.GetValue(kCFURLIsRegularFileKey, objProperties.isRegularFile);
        propertyDict.GetValue(kCFURLIsDirectoryKey, objProperties.isDirectory);
        propertyDict.GetValue(kCFURLIsPackageKey, objProperties.isPackage);

        return noErr;
    }
    return fnfErr;
}
