#pragma once

#include "CFObj.h"
#include <vector>

typedef struct OneObjProperties
{
	CFObj<CFURLRef> url;
	CFObj<CFStringRef> extension;
    CFObj<CFStringRef> refreshPath;//refresh path is associated with object. this is one-to-one relationship
    Boolean isRegularFile { false };
    Boolean isDirectory { false };
    Boolean isPackage { false };
    Boolean reserved { false };
} OneObjProperties;


//removed const from OneObjProperties becuase it allows lazy population of some fields
typedef Boolean (*ObjCheckingProc)( OneObjProperties *inObj, void *inProcData );

Boolean        CheckAllObjects(std::vector<OneObjProperties>& objList, ObjCheckingProc inProcPtr, void *inProcData);
Boolean        CheckIfFile(OneObjProperties *inObj, void *);
Boolean        CheckIfFolder(OneObjProperties *inObj, void *);
Boolean        CheckIfFileOrFolder(OneObjProperties *inObj, void *);
Boolean        CheckIfPackage(OneObjProperties *inObj, void *);
Boolean        CheckFileType(OneObjProperties *inObj, void *);
Boolean        CheckExtension(OneObjProperties *inObj, void *);
Boolean        CheckFileTypeOrExtension(OneObjProperties *inObj, void *inData);
Boolean        CheckFileNameMatch(OneObjProperties *inObj, void *inData);
Boolean        CheckFilePathMatch(OneObjProperties *inObj, void *inData);
Boolean        DoStringsMatch(CFStringRef inMatchString, CFStringRef inSearchedString, UInt8 matchMethod, CFStringCompareFlags compareOptions );

//removed const from OneObjProperties becuase it allows lazy population of some fields
typedef CFStringRef (*CreateObjProc)(OneObjProperties *inObj, void *ioParam) noexcept;

CFStringRef     CreateObjPath(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef     CreateObjPathNoExtension(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef     CreateParentPath(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef     CreateObjName(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef     CreateObjNameNoExtension(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef     CreateObjExtensionOnly(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef     CreateObjDisplayName(OneObjProperties *inObj, void *ioParam) noexcept;
CFStringRef     CreateObjPathRelativeToBase(OneObjProperties *inObj, void *ioParam)noexcept ;

CFStringRef     CreateCommonParentPath(OneObjProperties *inObjList, CFIndex inObjCount );


CFStringRef     CreateStringFromListOrSingleObject( OneObjProperties *inObjList,
                                                    CFIndex inObjCount, CFIndex inCurrIndex,
                                                    CreateObjProc inObjProc, void *ioParam,
                                                    CFStringRef inMultiSeparator, CFStringRef inPrefix,
                                                    CFStringRef inSuffix, UInt16 escSpecialCharsMode );

OSStatus       CFURLCheckFileOrFolder(CFURLRef inURLRef, size_t index, void *ioData);
