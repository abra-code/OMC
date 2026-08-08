#include <iostream>
#include <vector>
#include <string>
#include <unistd.h>
#include <sys/stat.h>//stat(), to tell a missing or empty file from an unreadable one
#include "CFObj.h"
#include "AUniquePtr.h"
#include "ABase64.h"
#include "ACFPropertyList.h"


typedef enum PlisterCommandID
{
	kPCmd_none,
	kPCmd_get,
	kPCmd_set,
	kPCmd_remove,
	kPCmd_insert,//for dict or array. add or append is a special case of insert
	kPCmd_append, //for array only. aka "add"
	kPCmd_find, //for dict or array only - returns only first found item
	kPCmd_findall, //for dict or array only - returns all found items
	kPCmd_iterate, //for dict or array only
	kPCmd_batch //TODO: accept standard input batch of commands
} PlisterCommandID;

typedef enum PropertyType
{
	kCFType_invalid,
	kCFType_string,
	kCFType_dict,
	kCFType_array,
	kCFType_integer,
	kCFType_real,
	kCFType_bool,
	kCFType_date,
	kCFType_data,
	kCFType_last = kCFType_data,

	//meta types
	kCFType_type, //for "get" command only
	kCFType_key, //for "get" command on dictionary only
	kCFType_keys, //for "get" command on dictionary only
	kCFType_value,//for "get" command only
	kCFType_count, //for "get" command on array or dict
	kCFType_copy //for set, add, append, insert commands when copying from other file property
} PropertyType;

//real types only, mostly for get type and set value
CFStringRef kCFTypesList[kCFType_last+1] = 
{
	CFSTR("invalid"),
	CFSTR("string"),
	CFSTR("dict"),
	CFSTR("array"),
	CFSTR("integer"),
	CFSTR("real"),
	CFSTR("bool"),
	CFSTR("date"),
	CFSTR("data")
};

//actual values filled in main()
CFTypeID kCFTypeIDs[kCFType_last+1] = 
{
	0,//invalid
	0,//string
	0,//dict
	0,//array
	0,//integer
	0,//real
	0,//bool
	0,//date
	0//data
};


typedef struct CFObjSpec
{
	CFObjSpec(CFObjSpec *inNextSpec)
		: index(-1), nextSpec(inNextSpec)
	{ }

	bool IsEmpty() { return ((key == nullptr) && (index == -1 ) && (nextSpec == nullptr)); }
	bool IsTopLevel() { return ((key == nullptr) && (index == -1 )); }

	CFObj<CFStringRef> key;
	CFIndex index;//if positive - it can be index

	AUniquePtr<CFObjSpec> nextSpec;
	
} CFObjSpec;

CFStringRef kNumber0Str = CFSTR("0");
CFStringRef kNumber1Str = CFSTR("1");
CFStringRef kTrueStr = CFSTR("true");
CFStringRef kFalseStr = CFSTR("false");

typedef struct ContainerOptions
{
	int indentLevel;
	CFStringRef arraySeparator;
	CFStringRef dictSeparator;
} ContainerOptions;

typedef OSStatus (*CreateCFItemInfoProc)( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions );
typedef OSStatus (*CreateCFDictItemInfoProc)( CFDictionaryRef inItem, CFIndex inIndex, CFStringRef *outResult );
typedef OSStatus (*ModifyCFItemProc)( CFTypeRef inContainer, CFObjSpec *inChildSpec, CFTypeRef inValue );


OSStatus CreateCFItemType( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions );
OSStatus CreateCFItemCount( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions );
OSStatus CreateCFItemString( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions );

OSStatus CreateCFDictItemKey( CFDictionaryRef inDict, CFIndex inIndex, CFStringRef *outResult );
OSStatus CreateCFItemKeys( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions );

OSStatus CreateChildProperty(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CreateCFItemInfoProc inProcPtr, ContainerOptions *containerOptions, CFStringRef *outResult);
OSStatus CreateDictChildProperty(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CreateCFDictItemInfoProc inProcPtr, CFStringRef *outResult);
OSStatus ProcessDeleteItem(CFTypeRef inCurrLevelRef, CFObjSpec *inSpec );
OSStatus ProcessGetItem(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CFTypeRef *outResult);
OSStatus ProcessGetLastItemContainerAndSpec(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CFTypeRef *outContainer, CFObjSpec **outLastSpec);

OSStatus ReadPlistFile(const char *srcPlistPath, CFObj<CFPropertyListRef> &outProperties,
						bool mutableContainers, CFURLRef *outPlistURL, ACFPropertyListFormat *outFormat );
bool SavePropertiesToPlistFile(CFURLRef inPlistFileURL, CFPropertyListRef inProperties);

CFObjSpec *CreatePropertySpecifier(const char *inPropertySpecifier);
CFObjSpec *AddObjSpec(CFURLRef inPath, CFObjSpec *oldHead);
PropertyType GetPropertyType(const char *inTypeStr);
CFIndex GetPositiveInteger(CFStringRef inString);
CFTypeRef CreateCFItemFromArgumentString(PropertyType inCFObjType, const char *valueStr);
void DisplayHelp();

typedef struct OnePlisterCommand
{
	OnePlisterCommand()
		: commandID(kPCmd_none), cfObjType(kCFType_invalid), insertIndex(-1),
			plistFormat(kACFPropertyListFormat_unknown), modifyAndSave(true)
	{
	}

	bool IsPlistModified()
	{
		return ( modifyAndSave || ((nextCommand != nullptr) && nextCommand->IsPlistModified()) );
	}

	PlisterCommandID			commandID;
	PropertyType				cfObjType;//depends on command. may be type of object to get, set or match
	CFObj<CFStringRef>			newKey; //for commands which operate on dictionaries
	CFObj<CFTypeRef>			newValue; //for commands passing some value
	CFIndex						insertIndex;
	CFObj<CFURLRef>				destPlistURL;//only for top level command
	CFObj<CFPropertyListRef>	propertyList;//only for top level command
	ACFPropertyListFormat		plistFormat;//format the file was read in, so we write it back the same way
	AUniquePtr<CFObjSpec>	specChain; //either absolute specifier for top level command or relative for child commands
	AUniquePtr<CFObjSpec>	subSpecChain; //some commands may take item-relative spec in addition to main spec. currently "find" only
	AUniquePtr<OnePlisterCommand> nextCommand;//nextCommand may be one subcommand (iterate command has one child) or it can be a chain like batch command
	bool						modifyAndSave; //command sets this flag if the property list is modified and needs to be saved
} OnePlisterCommand;

typedef struct PlisterCommandContext
{
	PlisterCommandContext(CFTypeRef inItemRef)
		: currItemRef(inItemRef)//, containerRef(NULL), key(NULL), index(-1)
	
	{
	}

	CFTypeRef	currItemRef;
//	CFTypeRef	containerRef;
//	CFTypeRef	key; //not null if containerRef is dict
//	CFIndex		index; //positive if container ref is array
} PlisterCommandContext;

OSStatus ReadCommandAndParameters(int argumentCount, char * const argv[], int &paramIndex, OnePlisterCommand &ioOneCommand, bool expectingPlistPath);

typedef OSStatus (*RunCommandProc)( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );

OSStatus RunCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );
OSStatus RunGetCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );
OSStatus RunRemoveCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );
OSStatus RunInsertCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );
OSStatus RunAppendCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );
OSStatus RunSetCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );
OSStatus RunFindCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );
OSStatus RunIterateCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand );

static bool sPrintErrorMessages = false;

#pragma mark -

int main (int argc, char * const argv[])
{
	int result = 0;
	int paramIndex = 1; 
	
	if(argc < 3)
	{
		DisplayHelp();
		return -1;
	}

	kCFTypeIDs[ kCFType_invalid] = 0;
	kCFTypeIDs[ kCFType_string] = ::CFStringGetTypeID();
	kCFTypeIDs[ kCFType_dict] = ::CFDictionaryGetTypeID();
	kCFTypeIDs[ kCFType_array] = ::CFArrayGetTypeID();
	kCFTypeIDs[ kCFType_integer] = ::CFNumberGetTypeID();
	kCFTypeIDs[ kCFType_real] = ::CFNumberGetTypeID();
	kCFTypeIDs[ kCFType_bool] = ::CFBooleanGetTypeID();
	kCFTypeIDs[ kCFType_date] = ::CFDateGetTypeID();
	kCFTypeIDs[ kCFType_data] = ::CFDataGetTypeID();

	OnePlisterCommand topCommand;
	result = ReadCommandAndParameters(argc, argv, paramIndex, topCommand, true);
	if(result != noErr)
		return result;

	bool runCommand = true;
	if( (topCommand.commandID == kPCmd_set) && (topCommand.newValue != NULL) )
	{//special case for creating new top level containers in empty plist files:
		CFTypeID newValueType = ::CFGetTypeID(topCommand.newValue);
		bool isContainer = ((newValueType == kCFTypeIDs[kCFType_dict]) || (newValueType == kCFTypeIDs[kCFType_array]));
		if( isContainer && topCommand.specChain->IsEmpty() )
		{//no properties read-in, new item is container and the spec points to root item - just replace the new properties
			topCommand.propertyList.Adopt( topCommand.newValue.Detach(), kCFObjDontRetain );
			runCommand = false;
		}
	}
	
	if(runCommand)
	{
		PlisterCommandContext context(topCommand.propertyList);
		result = RunCommand( context, topCommand );
	}

	if(topCommand.IsPlistModified() && (result == 0) )//save only on success
	{
        //write the file back in the format it was read in - see ReadPlistFile
        bool success = WritePropertyList(topCommand.propertyList, topCommand.destPlistURL, topCommand.plistFormat);
		if(!success)
		{
			std::cerr << "Plister error: could not save the result plist file." << std::endl;
			//A write that did not happen is not a success. Exiting 0 here told
			//every shell caller the value was stored when it was not, which for
			//an OMC handler means the window says saved and the disk disagrees.
			result = -1;
		}
	}
	
    return result;
}


#pragma mark -

//TODO: add new code for parsing text input with the same stuff


//returns the count of read-in parameters
OSStatus
ReadCommandAndParameters(int argumentCount, char * const argv[], int &paramIndex, OnePlisterCommand &ioOneCommand, bool expectingPlistPath)
{
	int effectiveArgCount = argumentCount - paramIndex;
	if(effectiveArgCount == 0)
	{
		std::cerr << "Plister error: invalid number of input paramters" << std::endl;
		return -1;
	}

	OSStatus result = noErr;

	int argAdj = 0;
	if( !expectingPlistPath )
		argAdj = 1;//if we don't expect plist path, the number of arguments will be less by 1

	const char *commandStr = argv[paramIndex++];//paramIndex = 1
	if(commandStr == NULL)
	{
		std::cerr << "Plister error: invalid command" << std::endl;
		return -1;
	}

	size_t commandStrLen = strlen(commandStr);//optimization

	if( (commandStrLen == 3) && (strcmp(commandStr, "get") == 0) )
	{//plister get type [path/to/file.plist] /path/to/item
	//plister get value [path/to/file.plist] /path/to/item
	//plister get count [path/to/file.plist] /path/to/container
	//plister get string [path/to/file.plist] /path/to/item
	
		ioOneCommand.commandID = kPCmd_get;
		ioOneCommand.modifyAndSave = false;

		if( effectiveArgCount != (4 - argAdj) )
		{
			std::cerr << "Plister error: invalid number of arguments" << std::endl;
			return -1;
		}

		const char *typeStr = argv[paramIndex++];
		ioOneCommand.cfObjType = GetPropertyType(typeStr);

		//Checked here rather than in RunGetCommand, which is reached once per item
		//under "iterate" and whose status that loop discards - so "iterate f.json
		///L get vlaue /" printed an error per item and still exited 0. A parameter
		//this command cannot act on is a usage mistake, and usage mistakes belong
		//to the parse.
		switch(ioOneCommand.cfObjType)
		{
			case kCFType_type:
			case kCFType_count:
			case kCFType_value:
			case kCFType_string:
			case kCFType_key:
			case kCFType_keys:
			break;

			default:
				std::cerr << "Plister error: unsupported parameter for \"get\" - use one of: type, key, keys, value, string, count" << std::endl;
				return -1;
		}
	}
	else if( (commandStrLen == 3) && (strcmp(commandStr, "set") == 0) )
	{//plister set string "My New Value" [path/to/file.plist] /path/to/item
		ioOneCommand.commandID = kPCmd_set;

		if(paramIndex >= argumentCount)
		{
			std::cerr << "Plister error: value type not specified" << std::endl;
			return -1;
		}
		const char *typeStr = argv[paramIndex++];
		ioOneCommand.cfObjType = GetPropertyType(typeStr);
		
		if(ioOneCommand.cfObjType == kCFType_copy)
		{
			const char *plistPath = NULL;
			const char *propSpecStr = NULL;
			
			if(paramIndex < argumentCount)
				plistPath = argv[paramIndex++];
			else
			{
				std::cerr << "Plister error: input plist path not specified" << std::endl;
				return -1;//invalid input path
			}

			if(paramIndex < argumentCount)
				propSpecStr = argv[paramIndex++];
			else
			{
				std::cerr << "Plister error: property access path not specified" << std::endl;
				return -1;
			}

			AUniquePtr<CFObjSpec> specChain( CreatePropertySpecifier(propSpecStr) );

			//Symmetry with the two sites below, which the round already guarded.
			//This one only fails safely because ProcessGetItem happens to
			//NULL-check its spec argument; safety that lives in a callee is
			//one refactor away from not existing.
			if(specChain == nullptr)
				return -1;

			CFObj<CFPropertyListRef> properties;
			result = ReadPlistFile(plistPath, properties, false, NULL, NULL);
			if(result == 0)
			{
				CFTypeRef itemRef = NULL;
				result = ProcessGetItem(specChain, properties, &itemRef);
				ioOneCommand.newValue.Adopt(itemRef, kCFObjRetain);
			}
		}
		else if( (ioOneCommand.cfObjType == kCFType_dict) || (ioOneCommand.cfObjType == kCFType_array) )
		{
			ioOneCommand.newValue.Adopt( CreateCFItemFromArgumentString(ioOneCommand.cfObjType, NULL) );
		}
		else
		{
			if(paramIndex >= argumentCount)
			{
				std::cerr << "Plister error: value not specified" << std::endl;
				return -1;
			}
			const char *valueStr = argv[paramIndex++];
			ioOneCommand.newValue.Adopt( CreateCFItemFromArgumentString(ioOneCommand.cfObjType, valueStr) );
		}
	}
	else if( ((commandStrLen == 6) && (strcmp(commandStr, "remove") == 0)) || ((commandStrLen == 6) && (strcmp(commandStr, "delete") == 0)) )
	{//plister remove [path/to/file.plist] /path/to/item
		ioOneCommand.commandID = kPCmd_remove;

		if( effectiveArgCount != (3-argAdj) )
		{
			std::cerr << "Plister error: invalid number of arguments" << std::endl;
			return -1;
		}
	}
	else if( ((commandStrLen == 6) && (strcmp(commandStr, "append") == 0)) || ((commandStrLen == 3) && (strcmp(commandStr, "add") == 0)) )
	{//plister append string "My New Array Value" [path/to/file.plist] /path/to/array (5 args)
	//plister append copy source/path /source/pseudpath [dest/path] dest/pseudopath (6 args)
	//plister append dict [path/to/file.plist] /path/to/array (4 args)
		ioOneCommand.commandID = kPCmd_append;

		//the expected argument count depends on the value type, so read the type first.
		//"dict" and "array" create an empty container and take no value argument at all.
		if(paramIndex >= argumentCount)
		{
			std::cerr << "Plister error: value type not specified" << std::endl;
			return -1;
		}

		const char *typeStr = argv[paramIndex++];
		ioOneCommand.cfObjType = GetPropertyType(typeStr);

		if(ioOneCommand.cfObjType == kCFType_copy)
		{
			if(effectiveArgCount != (6-argAdj))
			{
				std::cerr << "Plister error: invalid number of arguments" << std::endl;
				return -1;
			}

			const char *plistPath = argv[paramIndex++];
			const char *propSpecStr = argv[paramIndex++];

			AUniquePtr<CFObjSpec> specChain = CreatePropertySpecifier(propSpecStr);

			//Symmetry with the two sites below, which the round already guarded.
			//This one only fails safely because ProcessGetItem happens to
			//NULL-check its spec argument; safety that lives in a callee is
			//one refactor away from not existing.
			if(specChain == nullptr)
				return -1;

			CFObj<CFPropertyListRef> properties;
			result = ReadPlistFile(plistPath, properties, false, NULL, NULL);
			if(result == 0)
			{	
				CFTypeRef itemRef = NULL;
				result = ProcessGetItem(specChain, properties, &itemRef);
				ioOneCommand.newValue.Adopt(itemRef, kCFObjRetain);
			}
		}
		else if( (ioOneCommand.cfObjType == kCFType_dict) || (ioOneCommand.cfObjType == kCFType_array) )
		{
			if(effectiveArgCount != (4-argAdj))
			{
				std::cerr << "Plister error: invalid number of arguments" << std::endl;
				return -1;
			}
			ioOneCommand.newValue.Adopt( CreateCFItemFromArgumentString(ioOneCommand.cfObjType, NULL) );
		}
		else
		{
			if(effectiveArgCount != (5-argAdj))
			{
				std::cerr << "Plister error: invalid number of arguments" << std::endl;
				return -1;
			}
			const char *valueStr = argv[paramIndex++];
			ioOneCommand.newValue.Adopt( CreateCFItemFromArgumentString(ioOneCommand.cfObjType, valueStr) );
		}
	}
	else if( (commandStrLen == 6) && (strcmp(commandStr, "insert") == 0) )
	{//plister insert 0 string "My New Array Value" [path/to/file.plist] /path/to/array (6 args)
	//plister insert "My Key" string "My New Dict Value" [path/to/file.plist] /path/to/dict (6 args)
	//plister insert "Duplicate" copy source/path /source/pseudpath [dest/path] dest/pseudopath (7 args)
	//plister insert "NewArray" array [path/to/file.plist] /pseudopath (5 args)
		ioOneCommand.commandID = kPCmd_insert;

		//the key or index and the value type both come before the value, and the expected
		//argument count depends on that type, so validate it per type below rather than here
		if(paramIndex >= (argumentCount-1))
		{
			std::cerr << "Plister error: key or index and value type must both be specified" << std::endl;
			return -1;
		}

		const char *keyOrIndexStr = argv[paramIndex++];
		ioOneCommand.newKey.Adopt( ::CFStringCreateWithCString(kCFAllocatorDefault, keyOrIndexStr, kCFStringEncodingUTF8) );
		if(ioOneCommand.newKey == NULL)
		{
			//Not valid UTF-8. The dict branch downstream does NULL-check the key,
			//so this never crashed - it fell through and complained that a
			//perfectly good dictionary "is not a container", which sends the
			//reader looking in the wrong place entirely.
			std::cerr << "Plister error: the key is not valid UTF-8" << std::endl;
			return -1;
		}
		CFObj<CFStringRef> indexStrRef( ::CFStringCreateWithCString(kCFAllocatorDefault, keyOrIndexStr, kCFStringEncodingUTF8) );
		ioOneCommand.insertIndex = GetPositiveInteger(indexStrRef);

		const char *typeStr = argv[paramIndex++];
		ioOneCommand.cfObjType = GetPropertyType(typeStr);

		if(ioOneCommand.cfObjType == kCFType_copy)
		{
			if(effectiveArgCount != (7-argAdj))
			{
				std::cerr << "Plister error: invalid number of arguments" << std::endl;
				return -1;
			}
			const char *plistPath = NULL;
			const char *propSpecStr = NULL;

			plistPath = argv[paramIndex++];
			propSpecStr = argv[paramIndex++];
			
			AUniquePtr<CFObjSpec> specChain = CreatePropertySpecifier(propSpecStr);

			//Symmetry with the two sites below, which the round already guarded.
			//This one only fails safely because ProcessGetItem happens to
			//NULL-check its spec argument; safety that lives in a callee is
			//one refactor away from not existing.
			if(specChain == nullptr)
				return -1;

			CFObj<CFPropertyListRef> properties;
			result = ReadPlistFile(plistPath, properties, false, NULL, NULL);
			if(result == 0)
			{	
				CFTypeRef itemRef = NULL;
				result = ProcessGetItem(specChain, properties, &itemRef);
				ioOneCommand.newValue.Adopt(itemRef, kCFObjRetain);
			}
		}
		else if( (ioOneCommand.cfObjType == kCFType_dict) || (ioOneCommand.cfObjType == kCFType_array) )
		{
			if(effectiveArgCount != (5-argAdj))
			{
				std::cerr << "Plister error: invalid number of arguments" << std::endl;
				return -1;
			}
			ioOneCommand.newValue.Adopt( CreateCFItemFromArgumentString(ioOneCommand.cfObjType, NULL) );
		}
		else
		{
			if(effectiveArgCount != (6-argAdj))
			{
				std::cerr << "Plister error: invalid number of arguments" << std::endl;
				return -1;
			}
			const char *valueStr = argv[paramIndex++];
			ioOneCommand.newValue.Adopt( CreateCFItemFromArgumentString(ioOneCommand.cfObjType, valueStr) );
		}
	}
	else if( ((commandStrLen == 4) && (strcmp(commandStr, "find") == 0)) || ((commandStrLen == 7) && (strcmp(commandStr, "findall") == 0)) )
	{//plister find string "Item" [path/to/file.plist] /path/to/container [subpath/to/item] (5 or 6 args)

		ioOneCommand.commandID = (commandStrLen == 4) ? kPCmd_find : kPCmd_findall;
		ioOneCommand.modifyAndSave = false;

		if( (effectiveArgCount != (5-argAdj)) && (effectiveArgCount != (6-argAdj)) )
		{//6th arg is subpath, which is optional
			std::cerr << "Plister error: invalid number of arguments" << std::endl;
			return -1;
		}
		
		const char *typeStr = argv[paramIndex++];
		ioOneCommand.cfObjType = GetPropertyType(typeStr);

		if( (ioOneCommand.cfObjType != kCFType_string) &&
			(ioOneCommand.cfObjType != kCFType_integer) &&
			(ioOneCommand.cfObjType != kCFType_real) &&
			(ioOneCommand.cfObjType != kCFType_bool) )
		{
			std::cerr << "Plister error: unsupported item type for find command" << std::endl;
			return -1;
		}

		const char *valueStr = argv[paramIndex++];
		ioOneCommand.newValue.Adopt( CreateCFItemFromArgumentString(ioOneCommand.cfObjType, valueStr) );//newValue is actually our search item
	}
	else if( (commandStrLen == 7) && (strcmp(commandStr, "iterate") == 0) )
	{//plister iterate [path/to/file.plist] /path/to/container command command_params subpath/to/item
		ioOneCommand.commandID = kPCmd_iterate;
		//we don't know yet what subcommand is going to do, so make containers mutable just in case
		//therefore modifyAndSave remains true now
		//ioOneCommand.modifyAndSave = false;
	}
	else if( (commandStrLen == 5) && (strcmp(commandStr, "batch") == 0) )
	{//plister batch path/to/file.plist
		ioOneCommand.commandID = kPCmd_batch;

		//Nothing was parsed and nothing will be read, so there is nothing to write
		//back. Left at the default true, the save-failure fix elsewhere in this
		//commit turned this note into "could not save the result plist file" and
		//an exit of 255, which is a misleading way to say "unimplemented".
		ioOneCommand.modifyAndSave = false;
		std::cerr << "Plister note: not implemented yet" << std::endl;
		return 0;
	}
	else
	{
		std::cerr << "Plister error: unknown command" << std::endl;
		return -1;
	}

	if(result != 0)
		return result;

	//CreateCFItemFromArgumentString returns NULL for any value it cannot read as
	//the requested type - an empty or non-numeric "integer", a "bool" that is not
	//one of the six accepted words, a "data" that is not base64 - and every
	//consumer below hands that NULL straight to CoreFoundation. The result is a
	//signal death: SIGABRT out of CFDictionarySetValue ("object cannot be nil"),
	//or SIGSEGV out of CFEqual for find, which prints nothing at all.
	//
	//The reachable case is not a typo. "plister set integer "$count" f.json /N"
	//with $count unset is an ordinary shell slip, and it killed the process
	//instead of saying so.
	switch(ioOneCommand.commandID)
	{
		case kPCmd_set:
		case kPCmd_append:
		case kPCmd_insert:
		case kPCmd_find:
		case kPCmd_findall:
			if(ioOneCommand.newValue == NULL)
			{
				std::cerr << "Plister error: the value could not be read as the specified type" << std::endl;
				return -1;
			}
		break;

		default:
		break;
	}

	if(expectingPlistPath)
	{
		const char *plistPath = NULL;

		if(paramIndex < argumentCount)
			plistPath = argv[paramIndex++];
		else
		{
			std::cerr << "Plister error: input plist path not specified" << std::endl;
			return -1;//invalid input path
		}

		result = ReadPlistFile(plistPath, ioOneCommand.propertyList, ioOneCommand.modifyAndSave, &(ioOneCommand.destPlistURL),
								&(ioOneCommand.plistFormat) );
		if(result != noErr)
			return result;//a path this tool cannot use at all; ReadPlistFile said why

		//A file that is not there yet is deliberately not an error: creating one
		//with "plister set dict doc.json /" is a documented idiom, and every
		//other command reports the miss in its own words further down. A file
		//that IS on disk and did not parse is a different thing entirely. The
		//new-root special case in main() keys off a NULL property list, so
		//without this it replaced an unparsable file with an empty container,
		//printed the parser's complaint, and exited 0 - destroying the data and
		//calling it success.
		//The size test is the point, not the existence test. access(F_OK) answers
		//"is there a directory entry", and a zero-byte file has one - so testing
		//existence alone refused exactly the placeholder state the create idiom
		//exists to fill. "touch doc.json", ": > doc.json", mktemp and an
		//interrupted write all leave a file with no bytes in it, and a file with
		//no bytes has nothing to destroy. A whitespace-only file does have bytes
		//and stays refused.
		struct stat plistStat;
		if( (ioOneCommand.propertyList == NULL)
			&& (::stat(plistPath, &plistStat) == 0) && (plistStat.st_size > 0) )
		{
			//Only a command that would write is refusing to overwrite anything;
			//get and find reach here too, and telling their caller about a write
			//nobody attempted sends them looking in the wrong place.
			if(ioOneCommand.modifyAndSave)
			{
				std::cerr << "Plister error: " << plistPath
						  << " exists but could not be read - refusing to overwrite it" << std::endl;
			}
			else
			{
				std::cerr << "Plister error: " << plistPath
						  << " exists but could not be read" << std::endl;
			}
			return -1;
		}
		result = noErr;
	}

	const char *propSpecStr = NULL;
	if(paramIndex < argumentCount)
		propSpecStr = argv[paramIndex++];

	ioOneCommand.specChain.reset( CreatePropertySpecifier(propSpecStr) );
	//Every command needs a property path, and CreatePropertySpecifier returns NULL
	//(having said so) when there is none. Returning here rather than carrying the
	//NULL forward: main() dereferences specChain for the new-root special case and
	//segfaulted on "plister set dict file.plist" - a pseudopath away from correct,
	//which is an ordinary typo for a shell handler to make.
	if(ioOneCommand.specChain == nullptr)
		return -1;

	if( (ioOneCommand.commandID == kPCmd_find) ||
		(ioOneCommand.commandID == kPCmd_findall) )
	{
		//some additional parsing here.
		if(paramIndex < argumentCount)
		{
			const char *subPropSpec = argv[paramIndex++];
			ioOneCommand.subSpecChain.reset( CreatePropertySpecifier(subPropSpec) );
			//Same reasoning as the main spec chain above: CreatePropertySpecifier
			//has already said what is wrong, and carrying the NULL forward made
			//"find" print the complaint and then exit 0, which is the one thing a
			//shell caller cannot see.
			if(ioOneCommand.subSpecChain == nullptr)
				return -1;
		}
		else
		{
			ioOneCommand.subSpecChain.reset( new CFObjSpec(NULL) );//create empty chain just to have it
		}
	}
	else if(ioOneCommand.commandID == kPCmd_iterate)
	{
		ioOneCommand.modifyAndSave = false;//iterator itself does not carry information about modification. subcomamnd will do so though
		ioOneCommand.nextCommand.reset( new OnePlisterCommand() );
		OnePlisterCommand *oneCommand = ioOneCommand.nextCommand;
		result = ReadCommandAndParameters(argumentCount, argv, paramIndex, *oneCommand, false);
	}

	return result;
}

#pragma mark -


OSStatus
RunCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{
	OSStatus result = noErr;

	switch(inCommand.commandID)
	{
		case kPCmd_get:
			result = RunGetCommand( inContext, inCommand );
		break;
	
		case kPCmd_remove:
			result = RunRemoveCommand( inContext, inCommand );
		break;
		
		case kPCmd_insert:
			result = RunInsertCommand( inContext, inCommand );
		break;
		
		case kPCmd_append:
			result = RunAppendCommand( inContext, inCommand ); //for array only
		break;

		case kPCmd_set:
		//regular case of replacing value with another in some container
			result = RunSetCommand( inContext, inCommand );
		break;
		
		case kPCmd_find:
		case kPCmd_findall:
			result = RunFindCommand( inContext, inCommand );
		break;

		case kPCmd_iterate:
			result = RunIterateCommand( inContext, inCommand );
		break;
		
		case kPCmd_batch:
		break;
		
		default:
			std::cerr << "Plister error: unknown command" << std::endl;
		break;
	}

	return result;
}

std::string
CreateUTF8StringFromCFString(CFStringRef inStrRef)
{
    if(inStrRef == nullptr)
    return std::string();
    
    CFIndex uniCount = ::CFStringGetLength(inStrRef);
    if(uniCount > 0)
    {
        CFIndex maxCount = ::CFStringGetMaximumSizeForEncoding(uniCount, kCFStringEncodingUTF8 );
        std::string string(maxCount+1, '\0');//+ 1 for null char
        Boolean isOK = ::CFStringGetCString (inStrRef, &string[0], maxCount+1, kCFStringEncodingUTF8);
        if(isOK)
        {
            string.resize(strnlen(&string[0], maxCount));//shrink down to exact size
            return string;
        }
    }
    
    std::cerr << "Plister error: problem converting UTF-16 string to UTF-8" << std::endl;
    
    return std::string();
}

OSStatus
RunGetCommand( PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{
	OSStatus result = noErr;
	CreateCFItemInfoProc getInfoProcPtr = NULL;
	CreateCFDictItemInfoProc getDictItemInfoProcPtr = NULL;

	ContainerOptions containerOptions;
	containerOptions.indentLevel = 0;
	containerOptions.arraySeparator = CFSTR("\n");
	containerOptions.dictSeparator = CFSTR("\n");

	//supported "get" types:
	switch(inCommand.cfObjType)
	{
		case kCFType_type:
			getInfoProcPtr = CreateCFItemType;
		break;

		case kCFType_count:
			getInfoProcPtr = CreateCFItemCount;
		break;
		
		case kCFType_value:
			getInfoProcPtr = CreateCFItemString;
		break;

		case kCFType_string:
			getInfoProcPtr = CreateCFItemString;
			containerOptions.arraySeparator = CFSTR("");
			containerOptions.dictSeparator = CFSTR(", ");//key1 = val1, key2 = val2
		break;
		
		case kCFType_key:
			getDictItemInfoProcPtr = CreateCFDictItemKey;
		break;

		case kCFType_keys:
			getInfoProcPtr = CreateCFItemKeys;
		break;

		default:
			//An unrecognized "get" parameter: "plister get vlaue file.plist /K".
			//This was an assert, which aborts the process in a build with them
			//enabled - a diagnostic for a typo should not be a signal death.
			std::cerr << "Plister error: unsupported parameter for \"get\" - use one of: type, key, keys, value, string, count" << std::endl;
			return -1;
	}
	
	CFObj<CFStringRef> resultStr;
	if(getInfoProcPtr != NULL)
	{
		result = CreateChildProperty(inCommand.specChain, inContext.currItemRef, getInfoProcPtr, &containerOptions, &resultStr);
	}
	else if(getDictItemInfoProcPtr != NULL)
	{
		result = CreateDictChildProperty(inCommand.specChain, inContext.currItemRef, getDictItemInfoProcPtr, &resultStr);
	}

	if(resultStr != NULL)
	{
        std::string str = CreateUTF8StringFromCFString(resultStr);
        std::cout << str << std::endl;
	}
	
	return result;
}


OSStatus
RunRemoveCommand(PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{
	return ProcessDeleteItem( inContext.currItemRef, inCommand.specChain );
}

OSStatus
RunInsertCommand(PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{
	CFIndex insertIndex = inCommand.insertIndex;
	CFTypeRef itemRef = NULL;
	OSStatus result = ProcessGetItem(inCommand.specChain, inContext.currItemRef, &itemRef);
	if(itemRef != NULL)
	{
		if( (::CFGetTypeID(itemRef) == kCFTypeIDs[kCFType_dict]) && (inCommand.newKey != NULL))
		{
			::CFDictionarySetValue( (CFMutableDictionaryRef)itemRef, (CFStringRef)inCommand.newKey, inCommand.newValue );
		}
		else if(::CFGetTypeID(itemRef) ==  kCFTypeIDs[kCFType_array])
		{
			if(insertIndex < 0)
			{
				::CFArrayAppendValue((CFMutableArrayRef)itemRef, inCommand.newValue);
			}
			else
			{
				CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)itemRef );
				if(insertIndex > itemCount)
					insertIndex = itemCount;
				::CFArrayInsertValueAtIndex((CFMutableArrayRef)itemRef, insertIndex, inCommand.newValue);
			}
		}
		else
		{
			std::cerr << "Plister error: specified item is not a container" << std::endl;
			result = -1;
		}
	}
	return result;
}

OSStatus
RunAppendCommand(PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{//for array only
	CFTypeRef itemRef = NULL;
	OSStatus result = ProcessGetItem(inCommand.specChain, inContext.currItemRef, &itemRef);
	if((result == noErr) && (itemRef != NULL) )
	{
		if(::CFGetTypeID(itemRef) ==  kCFTypeIDs[kCFType_array])
		{
			::CFArrayAppendValue((CFMutableArrayRef)itemRef, inCommand.newValue);
		}
		else
		{
			std::cerr << "Plister error: specified item is not an array" << std::endl;
			result = -1;
		}
	}
	return result;
}

OSStatus
RunSetCommand(PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{
	CFTypeRef lastContainer = NULL;
	CFObjSpec *lastItemSpec = NULL;
	OSStatus result = ProcessGetLastItemContainerAndSpec(inCommand.specChain, inContext.currItemRef, &lastContainer, &lastItemSpec);
	if( (result == noErr) && (lastContainer != NULL) && (lastItemSpec != NULL) )
	{	
		if( ::CFGetTypeID(lastContainer) == kCFTypeIDs[kCFType_dict] )
		{
			if(lastItemSpec->key != NULL)
			{
				::CFDictionarySetValue( (CFMutableDictionaryRef)lastContainer, (CFStringRef)lastItemSpec->key, inCommand.newValue );
			}
			else
			{
				std::cerr << "Plister error: last item key is invalid" << std::endl;
				result = -1;
			}
		}
		else if(::CFGetTypeID(lastContainer) ==  kCFTypeIDs[kCFType_array])
		{
			CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)lastContainer );
			if( (lastItemSpec->index >= 0) && (lastItemSpec->index < itemCount) )
			{
				::CFArraySetValueAtIndex( (CFMutableArrayRef)lastContainer, lastItemSpec->index, inCommand.newValue);
			}
			else
			{
				std::cerr << "Plister error: array index out of range" << std::endl;
				result = -1;
			}
		}
		else
		{
			std::cerr << "Plister error: could not get container for specified item" << std::endl;
			result = -1;
		}
	}
	return result;	
}

OSStatus
RunFindCommand(PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{	
	CFTypeRef containerRef = NULL;
	OSStatus result = ProcessGetItem(inCommand.specChain, inContext.currItemRef, &containerRef);
	if(containerRef != NULL)
	{
		ContainerOptions containerOptions;
		containerOptions.indentLevel = 0;
		containerOptions.arraySeparator = CFSTR("");
		containerOptions.dictSeparator = CFSTR(", ");

		if( ::CFGetTypeID(containerRef) == kCFTypeIDs[kCFType_dict] )
		{
			CFIndex itemCount = ::CFDictionaryGetCount( (CFDictionaryRef)containerRef );
			if( itemCount > 0 )
			{
                std::vector<void *> keys(itemCount);
                std::vector<void *> dictValues(itemCount);
				
				::CFDictionaryGetKeysAndValues( (CFDictionaryRef)containerRef, (const void **)keys.data(), (const void **)dictValues.data() );
					
				for( CFIndex index = 0; index < itemCount; index++ )
				{
					CFTypeRef currItemRef = dictValues[index];
					if(currItemRef == NULL)
						continue;

					CFTypeRef subItemRef = NULL;
					result = ProcessGetItem(inCommand.subSpecChain, currItemRef, &subItemRef);
					
					CFObj<CFStringRef> foundStr;
					if(inCommand.cfObjType == kCFType_string)
					{//we have "find string" command, than turn the result into string
						result = CreateCFItemString( subItemRef, &foundStr, &containerOptions );
						subItemRef = (CFStringRef)foundStr;
					}
					
					if( (subItemRef != NULL) && ::CFEqual( inCommand.newValue, subItemRef ) )
					{//print
						CFObj<CFStringRef> resultStr;
						result = CreateCFItemString( keys[index], &resultStr, NULL );

						std::string str = CreateUTF8StringFromCFString(resultStr);
                        std::cout << str << std::endl;
					
						if(inCommand.commandID == kPCmd_find)
							break;//break on first found item
					}
				}
			}
			result = 0;
		}
		else if( ::CFGetTypeID(containerRef) ==  kCFTypeIDs[kCFType_array] )
		{
			CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)containerRef );
			for( CFIndex index = 0; index < itemCount; index++ )
			{
				CFTypeRef currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)containerRef, index );
				if(currItemRef == NULL)
					continue;

				CFTypeRef subItemRef = NULL;
				result = ProcessGetItem(inCommand.subSpecChain, currItemRef, &subItemRef);

				CFObj<CFStringRef> foundStr;
				if(inCommand.cfObjType == kCFType_string)
				{//we have "find string" command, than turn the result into string
					result = CreateCFItemString( subItemRef, &foundStr, &containerOptions );
					subItemRef = (CFStringRef)foundStr;
				}

				if( (subItemRef != NULL) && ::CFEqual( inCommand.newValue, subItemRef ) )
				{//print
					CFObj<CFStringRef> resultStr( ::CFStringCreateWithFormat( kCFAllocatorDefault, NULL, CFSTR("%ld"), index ) );
					std::string str = CreateUTF8StringFromCFString(resultStr);
                    std::cout << str << std::endl;
					
					if(inCommand.commandID == kPCmd_find)
						break;//break on first found item
				}
			}
			result = 0;
		}
		else
		{
			std::cerr << "Plister error: specified item is not a container" << std::endl;
			result = -1;
		}
	}
	return result;
}

OSStatus
RunIterateCommand(PlisterCommandContext &inContext, OnePlisterCommand &inCommand )
{
	OnePlisterCommand *subCommand = inCommand.nextCommand;
	if(subCommand == NULL)
	{
		std::cerr << "Plister error: iteration subcommand not specified" << std::endl;
		return -1;
	}

	AUniquePtr<CFObjSpec> originalSpecChain( subCommand->specChain.release() );//we need to modify it so detach it now - we will put it back at the end
	CFObjSpec *specChain = originalSpecChain;
	if( (specChain != nullptr) && specChain->IsEmpty() )
		specChain = nullptr;
	
	while( (specChain != nullptr) && specChain->IsTopLevel() )
	{
		specChain = specChain->nextSpec;
	}

	//if subcommand spec does not point any deeper than just item in iteration we need to take care with delete and insert comamnds
	bool subcommandSpecIsRoot = (specChain == NULL);

	//A failing subcommand used to be forgotten: both loops below ended with an
	//unconditional "result = 0". For a read-only subcommand that is right - an
	//item that does not carry the subpath is an ordinary miss, not an error - but
	//for a modifying one it meant a half-applied iteration was saved and reported
	//as success, which is the same "the window says saved, the disk disagrees"
	//shape the save-failure fix exists to prevent, one level down. So a failure is
	//latched only when the subcommand modifies.
	OSStatus modifyingFailure = noErr;

	CFTypeRef containerRef = NULL;
	OSStatus result = ProcessGetItem(inCommand.specChain, inContext.currItemRef, &containerRef);
	if(containerRef != NULL)
	{
		//TODO: fix subcommands requiring container and it is missing becase it is this one that we are iterating!

		if( ::CFGetTypeID(containerRef) == kCFTypeIDs[kCFType_dict] )
		{
			CFIndex itemCount = ::CFDictionaryGetCount( (CFDictionaryRef)containerRef );
			if( itemCount > 0 )
			{
                std::vector<void *> keys(itemCount);
				std::vector<void *> dictValues(itemCount);
				
				::CFDictionaryGetKeysAndValues( (CFDictionaryRef)containerRef, (const void **)keys.data(), (const void **)dictValues.data() );
					
				for( CFIndex index = 0; index < itemCount; index++ )
				{
					CFTypeRef currItemRef = dictValues[index];
					if(currItemRef == NULL)
						continue;
					
					AUniquePtr<CFObjSpec> itemSubSpec = new CFObjSpec(specChain);
					itemSubSpec->key.Adopt((CFStringRef)keys[index], kCFObjRetain);
					subCommand->specChain.reset( itemSubSpec );//temporarily stick the new subChain
					PlisterCommandContext context(containerRef);
					result = RunCommand(context, *subCommand);
					if( (result != noErr) && subCommand->modifyAndSave )
						modifyingFailure = result;
					subCommand->specChain.detach();//detach temp chain from subCommand
					itemSubSpec->nextSpec.detach();//detach original subchain from temp chain
				}
			}
			result = modifyingFailure;
		}
		else if( ::CFGetTypeID(containerRef) ==  kCFTypeIDs[kCFType_array] )
		{
			CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)containerRef );
			
			if( (subCommand->commandID == kPCmd_remove) && subcommandSpecIsRoot )
			{//iteration with delete on this array must run from the end
				for( CFIndex index = (itemCount-1); index >=0 ; index-- )
				{
					CFTypeRef currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)containerRef, index );
					if(currItemRef == NULL)
						continue;

					AUniquePtr<CFObjSpec> itemSubSpec = new CFObjSpec(specChain);//add new head
					itemSubSpec->index = index;
					subCommand->specChain.reset( itemSubSpec );//temporarily stick the new subChain
					PlisterCommandContext context(containerRef);
					result = RunCommand(context, *subCommand);
					if( (result != noErr) && subCommand->modifyAndSave )
						modifyingFailure = result;
					subCommand->specChain.detach();//detach temp chain from subCommand
					itemSubSpec->nextSpec.detach();//detach original subchain from temp chain

				}
			}
			else if( (subCommand->commandID == kPCmd_insert) && subcommandSpecIsRoot )
			{
				std::cerr << "Plister error: you cannot insert items into array while iterating this array" << std::endl;
				//The refusal has to be latched like any other. Without it the
				//"result = modifyingFailure" below overwrote the status with
				//noErr, and because the subcommand is a modifying one the file
				//was then re-written and the run reported success - the same
				//"the window says saved, the disk disagrees" shape the rest of
				//this commit exists to remove, in the one branch the latching
				//did not reach.
				modifyingFailure = -1;
			}
			else
			{
				for( CFIndex index = 0; index < itemCount; index++ )
				{
					CFTypeRef currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)containerRef, index );
					if(currItemRef == NULL)
						continue;

					AUniquePtr<CFObjSpec> itemSubSpec = new CFObjSpec(specChain);//add new head
					itemSubSpec->index = index;
					subCommand->specChain.reset( itemSubSpec );//temporarily stick the new subChain
					PlisterCommandContext context(containerRef);
					result = RunCommand(context, *subCommand);
					if( (result != noErr) && subCommand->modifyAndSave )
						modifyingFailure = result;
					subCommand->specChain.detach();//detach temp chain from subCommand
					itemSubSpec->nextSpec.detach();//detach original subchain from temp chain					
				}
			}
			result = modifyingFailure;
		}
		else
		{
			std::cerr << "Plister error: specified item is not a container" << std::endl;
			result = -1;
		}
	}
	
	subCommand->specChain.reset( originalSpecChain.release() );
	
	return result;
}

#pragma mark -


//caller responsible for releasing *outPlistURL
OSStatus
ReadPlistFile(const char *plistPath, CFObj<CFPropertyListRef> &outProperties, bool mutableContainers, CFURLRef *outPlistURL,
				ACFPropertyListFormat *outFormat )
{
	if(plistPath == NULL)
	{
		std::cerr << "Plister error: invalid input plist path" << std::endl;
		return -1;//invalid input path
	}

	size_t pathLen = strlen(plistPath);
	if(pathLen < 1)
	{
		std::cerr << "Plister error: invalid input plist path" << std::endl;
		return -1;//invalid input path
	}

	CFObj<CFStringRef> pathStr( ::CFStringCreateWithCString(kCFAllocatorDefault, plistPath, kCFStringEncodingUTF8) );
	if(pathStr == NULL)
	{
		//Not valid UTF-8. A file name carrying Latin-1 bytes is an ordinary thing
		//for a shell handler to hand over, and unchecked this NULL reached
		//CFURLCreateWithFileSystemPath and killed the process without a word.
		std::cerr << "Plister error: the plist path is not valid UTF-8" << std::endl;
		return -1;
	}
	CFObj<CFURLRef> plistURL( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, pathStr, kCFURLPOSIXPathStyle, false) );

    outProperties.Adopt( CreatePropertyListAndFormat(plistURL, mutableContainers ? kCFPropertyListMutableContainers : kCFPropertyListImmutable, outFormat) );

//signal error ourside if you wish
//	if(outProperties == NULL)
//	{
//		std::cerr << "Plister error: could not read plist file" << std::endl;
//		return -1;
//	}
	
	if(outPlistURL != NULL)
		*outPlistURL = plistURL.Detach();
	return noErr;
}

PropertyType
GetPropertyType(const char *inTypeStr)
{
	if( strcmp(inTypeStr, "string") == 0 )
		return kCFType_string;
	else if( strcmp(inTypeStr, "integer") == 0 )
		return kCFType_integer;
	else if( strcmp(inTypeStr, "real") == 0 )
		return kCFType_real;
	else if( strcmp(inTypeStr, "bool") == 0 )
		return kCFType_bool;
	else if( strcmp(inTypeStr, "type") == 0 )
		return kCFType_type;//for "get" command only
	else if( strcmp(inTypeStr, "key") == 0 )
		return kCFType_key; //for "get" command on dictionary only
	else if( strcmp(inTypeStr, "keys") == 0 )
		return kCFType_keys; //for "get" command on dictionary only
	else if( strcmp(inTypeStr, "value") == 0 )
		return kCFType_value;//for "get" command only
	else if( strcmp(inTypeStr, "copy") == 0 )
		return kCFType_copy;//for set, add, append and insert commands only
	else if( strcmp(inTypeStr, "dict") == 0 )
		return kCFType_dict;
	else if( strcmp(inTypeStr, "array") == 0 )
		return kCFType_array;
	else if( strcmp(inTypeStr, "date") == 0 )
		return kCFType_date;
	else if( strcmp(inTypeStr, "data") == 0 )
		return kCFType_data;
	else if( strcmp(inTypeStr, "count") == 0 )
		return kCFType_count;//for "get" comamnd on array or dict
	return kCFType_invalid;
}

//path-like property specifier:
//		/COMMAND_LIST/0/COMMAND/
CFObjSpec *
CreatePropertySpecifier(const char *inPropertySpecifier)
{
	if(inPropertySpecifier == NULL)
	{
		std::cerr << "Plister error: invalid property access path: " << std::endl;
		return NULL;
	}
	
	CFObj<CFStringRef> specStr;

	if(inPropertySpecifier[0] != '/')
	{
		CFMutableStringRef newPath = ::CFStringCreateMutable( kCFAllocatorDefault, 0);
		if(newPath != NULL)
		{
			specStr.Adopt(newPath);
			::CFStringAppend( newPath, CFSTR("/") );

			CFObj<CFStringRef> mainStr(::CFStringCreateWithCString(kCFAllocatorDefault, inPropertySpecifier, kCFStringEncodingUTF8) );
			if(mainStr == NULL)
			{
				std::cerr << "Plister error: the property path is not valid UTF-8" << std::endl;
				return NULL;
			}
			::CFStringAppend( newPath, mainStr );
		}
		else
		{
			std::cerr << "Plister error: CFStringCreateMutable() failed" << std::endl;
			return NULL;
		}
	}
	else
	{
		specStr.Adopt( ::CFStringCreateWithCString(kCFAllocatorDefault, inPropertySpecifier, kCFStringEncodingUTF8) );
	}

	//Same trap as the value and the file path: not valid UTF-8 means NULL, and
	//unchecked it reached CFStringAppend or CFURLCreateWithFileSystemPath and
	//killed the process silently. Four call sites reach here - the main
	//pseudopath, a find subpath, and the copy source path.
	if(specStr == NULL)
	{
		std::cerr << "Plister error: the property path is not valid UTF-8" << std::endl;
		return NULL;
	}

	CFObj<CFURLRef> propPath( ::CFURLCreateWithFileSystemPath(kCFAllocatorDefault, specStr, kCFURLPOSIXPathStyle, false) );
	//needs to be a recursive digger to get the last element and then cut it and move on
	return AddObjSpec(propPath, NULL);
}

CFObjSpec *
AddObjSpec(CFURLRef propPath, CFObjSpec *oldHead)
{
	CFObjSpec *newHead = new CFObjSpec(oldHead);
	CFStringRef oneComponent = ::CFURLCopyLastPathComponent(propPath);
	
	if( (kCFCompareEqualTo == ::CFStringCompare(oneComponent, CFSTR("/"), 0)) ||
		(kCFCompareEqualTo == ::CFStringCompare(oneComponent, CFSTR(""), 0)) )
	{//reached the top. the key for root item is null
		return newHead;
	}
	
	newHead->key.Adopt( oneComponent );
	newHead->index = GetPositiveInteger(newHead->key);

	CFObj<CFURLRef> parentPath( ::CFURLCreateCopyDeletingLastPathComponent( kCFAllocatorDefault, propPath ) );
	//A "." or ".." component makes this walk grow instead of shrink:
	//CFURLCreateCopyDeletingLastPathComponent APPENDS for those, so the parent of
	//"/.." is "/../.." and the parent of "/." is "/./..". The only terminator
	//below is a last component of "/" or "", which then never arrives, and every
	//level allocates another CFObjSpec - "plister get value doc.json ." never
	//returned and reached 2.1 GB in four seconds. A hang is worse than a crash
	//for a handler, because nothing reports it at all. Stopping when the parent
	//is no shorter than the child ends it without changing any path that
	//genuinely shrinks.
	if(parentPath != NULL)
	{
		CFObj<CFStringRef> childStr( ::CFURLCopyFileSystemPath(propPath, kCFURLPOSIXPathStyle) );
		CFObj<CFStringRef> parentStr( ::CFURLCopyFileSystemPath(parentPath, kCFURLPOSIXPathStyle) );
		bool makesProgress = true;
		if( (childStr != NULL) && (parentStr != NULL) )
		{
			if( ::CFStringGetLength(parentStr) >= ::CFStringGetLength(childStr) )
				makesProgress = false;
		}
		if(makesProgress)
			newHead = AddObjSpec(parentPath, newHead);
	}
	return newHead;
}


//returns -1 if it's not integer or is not positive
CFIndex GetPositiveInteger(CFStringRef inString)
{
	if(inString == NULL)
		return -1;

	CFIndex uniCount = ::CFStringGetLength(inString);
	if(uniCount == 0)
		return -1;

    std::vector<UniChar> newString( uniCount );

	CFRange theRange;
	theRange.location = 0;
	theRange.length = uniCount;
	::CFStringGetCharacters( inString, theRange, newString.data());
	
	//only integer digits allowed in string - nothing else
	for(CFIndex i = 0; i < uniCount; i++)
	{
		if( (newString[i] < (UniChar)'0') || (newString[i] > (UniChar)'9') )
			return -1;
	}
	
	return ::CFStringGetIntValue(inString);
}

OSStatus CreateCFItemType( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions )
{
	OSStatus err = -1;
	if(inItem == NULL)
		return err;

	CFTypeID itemType = ::CFGetTypeID(inItem);
	CFIndex i = 0;
	for(i = 0; i <= kCFType_last; i++)
	{
		if(itemType == kCFTypeIDs[i])
		{
			err = noErr;
			break;
		}
	}
	
	if(err == noErr)
	{
		if( (i == kCFType_integer) || (i == kCFType_real) )
		{
			Boolean isFloat = ::CFNumberIsFloatType( (CFNumberRef)inItem );
			if(isFloat)
				i = kCFType_real;
			else
				i = kCFType_integer;
		}
		
		if(outResult != NULL)
		{
			*outResult = kCFTypesList[i];
			::CFRetain( *outResult );
		}
	}
	return noErr;
}

OSStatus CreateCFItemCount( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions )
{
	if(inItem == NULL)
		return -1;

	CFIndex theCount = 0;
	CFTypeID itemType = ::CFGetTypeID(inItem);

	if(itemType == kCFTypeIDs[kCFType_dict])
		theCount = ::CFDictionaryGetCount( (CFDictionaryRef)inItem );
	else if(itemType  == kCFTypeIDs[kCFType_array] )
		theCount = ::CFArrayGetCount( (CFArrayRef)inItem );

	if(outResult != NULL)
		*outResult = CFStringCreateWithFormat( kCFAllocatorDefault, NULL, CFSTR("%ld"), theCount );
	
	return noErr;
}

OSStatus CreateCFItemString( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions )
{
	if(inItem == NULL)
		return -1;
	if(outResult == NULL)
		return 0;

	OSStatus result = noErr;
	CFTypeID itemType = ::CFGetTypeID(inItem);

	if( itemType == kCFTypeIDs[kCFType_string] )
	{
		*outResult = (CFStringRef)inItem;
		::CFRetain( *outResult );
	}
	else if( itemType == kCFTypeIDs[kCFType_integer] )
	{
		// kCFType_integer and kCFType_real share CFNumberGetTypeID(), so this branch handles both.
		// Distinguish them via CFNumberIsFloatType to preserve the decimal representation for reals.
		Boolean isFloat = ::CFNumberIsFloatType( (CFNumberRef)inItem );
		if(isFloat)
		{
			double doubleValue = 0.0;
			::CFNumberGetValue( (CFNumberRef)inItem, kCFNumberDoubleType, &doubleValue );
			*outResult = ::CFStringCreateWithFormat( kCFAllocatorDefault, NULL, CFSTR("%f"), doubleValue );
		}
		else
		{
			long long intValue = 0LL;
			::CFNumberGetValue( (CFNumberRef)inItem, kCFNumberLongLongType, &intValue );
			*outResult = CFStringCreateWithFormat( kCFAllocatorDefault, NULL, CFSTR("%lld"), intValue );
		}
	}
	else if( itemType == kCFTypeIDs[kCFType_bool] )
	{
		*outResult = (::CFBooleanGetValue((CFBooleanRef)inItem) ? kTrueStr : kFalseStr);
		::CFRetain(*outResult);
	}
	else if( itemType == kCFTypeIDs[kCFType_date] )
	{	//use system locale for date representation. available in OS >= 10.3
		CFObj<CFDateFormatterRef> dateFormatter( ::CFDateFormatterCreate(kCFAllocatorDefault, NULL, kCFDateFormatterShortStyle, kCFDateFormatterShortStyle) );
		*outResult = ::CFDateFormatterCreateStringWithDate(kCFAllocatorDefault, dateFormatter, (CFDateRef)inItem);
	}
	else if( itemType == kCFTypeIDs[kCFType_data] )
	{
		result = -1;
		const UInt8 *rawData = ::CFDataGetBytePtr( (CFDataRef)inItem );
		CFIndex dataSize = ::CFDataGetLength ( (CFDataRef)inItem );
		if( (rawData != NULL) && (dataSize > 0) )
		{
			unsigned long buffSize = CalculateEncodedBufferSize(dataSize);
            std::vector<char> buff(buffSize+1);
            unsigned long encodedSize = EncodeBase64(rawData, dataSize, (unsigned char *)buff.data(), buffSize);
            buff[encodedSize] = 0;
            // Use CFStringCreateWithCString (copies the buffer) rather than the NoCopy variant,
            // which would require the buffer to outlive the CFString and be freed by CFAllocatorMalloc.
            *outResult = ::CFStringCreateWithCString(kCFAllocatorDefault, buff.data(), kCFStringEncodingASCII);
            if(*outResult != NULL)
            {
                result = noErr;
            }
		}
	}
	else if( itemType == kCFTypeIDs[kCFType_dict] )
	{
		result = noErr;
		if(containerOptions == NULL)
		{
			*outResult = (CFStringRef)::CFRetain(CFSTR("<dict>"));
		}
		else
		{
			CFObj<CFMutableStringRef> combinedString( ::CFStringCreateMutable(kCFAllocatorDefault, 0) );

			CFIndex itemCount = ::CFDictionaryGetCount( (CFDictionaryRef)inItem );
			if( itemCount > 0 )
			{
                std::vector<void *> keys(itemCount);
				std::vector<void *> dictValues(itemCount);
				
				::CFDictionaryGetKeysAndValues( (CFDictionaryRef)inItem, (const void **)keys.data(), (const void **)dictValues.data() );
					
				for( CFIndex index = 0; index < itemCount; index++ )
				{
					CFObj<CFStringRef> resultStr;
					result = CreateCFItemString( keys[index], &resultStr, NULL );
					if(resultStr != NULL)
						::CFStringAppend( combinedString, resultStr );
					
					::CFStringAppend( combinedString, CFSTR(" = ") );
					
					resultStr.Release();
					result = CreateCFItemString( dictValues[index], &resultStr, NULL );
					if(resultStr != NULL)
						::CFStringAppend( combinedString, resultStr );
					
					if( (containerOptions->dictSeparator != NULL) && (index < (itemCount - 1)) )
						::CFStringAppend( combinedString, containerOptions->dictSeparator );
				}
			}
			*outResult = combinedString.Detach();
		}
	}
	else if( itemType == kCFTypeIDs[kCFType_array] )
	{
		result = noErr;
		if(containerOptions == NULL)
		{
			*outResult = (CFStringRef)::CFRetain(CFSTR("<array>"));
		}
		else
		{
			CFObj<CFMutableStringRef> combinedString( ::CFStringCreateMutable( kCFAllocatorDefault, 0) );
			CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)inItem );
			for( CFIndex index = 0; index < itemCount; index++ )
			{
				CFTypeRef currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)inItem, index );
				CFObj<CFStringRef> resultStr;
				result = CreateCFItemString( currItemRef, &resultStr, NULL );
				if(resultStr != NULL)
					::CFStringAppend( combinedString, resultStr );
				if( (containerOptions->arraySeparator != NULL) && (index < (itemCount - 1)) )
					::CFStringAppend( combinedString, containerOptions->arraySeparator );
			}
			*outResult = combinedString.Detach();
		}
	}
	else //kCFTypeIDs[kCFType_invalid]
	{
		result = -2;
	}

	return result;
}

OSStatus
CreateChildProperty(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CreateCFItemInfoProc inProcPtr, ContainerOptions *containerOptions, CFStringRef *outResult)
{
	OSStatus err = noErr;
	if( (inSpec == NULL) || (inCurrLevelRef == NULL) || (inProcPtr == NULL) )
		return -1;

	CFTypeRef currItemRef = NULL;
	CFTypeID itemType = ::CFGetTypeID(inCurrLevelRef);

	if( inSpec->IsTopLevel() )//top level, root item requested
	{
		currItemRef = inCurrLevelRef;
	}
	else if(itemType ==  kCFTypeIDs[kCFType_dict])
	{
		if(inSpec->key != NULL)
		{
			//Boolean keyExists =
			::CFDictionaryGetValueIfPresent (
								(CFDictionaryRef)inCurrLevelRef,
								(CFStringRef)inSpec->key,
								&currItemRef);
		}
/*
// not really sure if it's a desired behavior
// and if getting dictionary item by index should be enabled 								
		if( !keyExists && (inSpec->index >= 0) )
		{//if key was not found and it looks like positive integer, try getting by index
			CFIndex itemCount = ::CFDictionaryGetCount( (CFDictionaryRef)inCurrLevelRef );
			if( (inSpec->index >= 0) && (inSpec->index < itemCount) )
			{
				const void *dictValues[itemCount];
				::CFDictionaryGetKeysAndValues(
					(CFDictionaryRef)inCurrLevelRef,
					NULL, //keys,
					dictValues);
				currItemRef = dictValues[inSpec->index];
			}
		}
*/
	}
	else if(itemType  == kCFTypeIDs[kCFType_array] )
	{
		CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)inCurrLevelRef );
		if( (inSpec->index >= 0) && (inSpec->index < itemCount) )
			currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)inCurrLevelRef, inSpec->index );
	}

	if(currItemRef == NULL)
	{
		if(sPrintErrorMessages)
		{
            std::string itemStr = CreateUTF8StringFromCFString(inSpec->key);
			std::cerr << "Plister error: item \"" << itemStr << "\" not found in plist file." << std::endl;
		}
		return -1;
	}

	if( inSpec->nextSpec == nullptr )
	{//we reached the end of spec chain - this is the item requested
		err = (*inProcPtr)( currItemRef, outResult, containerOptions );
	}
	else
	{//recursively dig deeper down the chain
		err = CreateChildProperty(inSpec->nextSpec, currItemRef, inProcPtr, containerOptions, outResult);
	}
	
	return err;
}

#pragma mark -

//this one is different. it needs to be called on the dictionary before the item by index is fetched
OSStatus CreateCFDictItemKey( CFDictionaryRef inDict, CFIndex inIndex, CFStringRef *outResult )
{
	if(inDict == NULL)
		return -1;

	CFIndex itemCount = ::CFDictionaryGetCount( inDict );
	if( (inIndex >= 0) && (inIndex < itemCount) )
	{
		std::vector<const void *> dictKeys(itemCount);
		::CFDictionaryGetKeysAndValues(
			(CFDictionaryRef)inDict,
			dictKeys.data(), //keys,
			NULL);
		
		if(outResult != NULL)
		{
			*outResult = (CFStringRef)dictKeys[inIndex];
			if(*outResult != NULL)
				::CFRetain( *outResult );
		}
		return noErr;
	}
	return -1;
}


OSStatus CreateCFItemKeys( CFTypeRef inItem, CFStringRef *outResult, ContainerOptions *containerOptions )
{
	if(inItem == NULL)
		return -1;

	if(outResult == NULL)
		return 0;

	OSStatus result = noErr;
	CFTypeID itemType = ::CFGetTypeID(inItem);

	if( itemType == kCFTypeIDs[kCFType_dict] )
	{
		result = noErr;
		if(containerOptions == NULL)
		{
			*outResult = (CFStringRef)::CFRetain(CFSTR(""));
		}
		else
		{
			CFObj<CFMutableStringRef> combinedString( ::CFStringCreateMutable(kCFAllocatorDefault, 0) );

			CFIndex itemCount = ::CFDictionaryGetCount( (CFDictionaryRef)inItem );
			if( itemCount > 0 )
			{
                std::vector<void *> keys(itemCount);
				
				::CFDictionaryGetKeysAndValues( (CFDictionaryRef)inItem, (const void **)keys.data(), NULL );
					
				for( CFIndex index = 0; index < itemCount; index++ )
				{
					CFObj<CFStringRef> resultStr;
					result = CreateCFItemString( keys[index], &resultStr, NULL );
					if(resultStr != NULL)
						::CFStringAppend( combinedString, resultStr );

					if( (containerOptions->dictSeparator != NULL) && (index < (itemCount - 1)) )
						::CFStringAppend( combinedString, containerOptions->dictSeparator );
				}
			}
			*outResult = combinedString.Detach();
		}
	}
	else //kCFTypeIDs[kCFType_invalid]
	{
		result = -2;
	}

	return result;
}

OSStatus
CreateDictChildProperty(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CreateCFDictItemInfoProc inProcPtr, CFStringRef *outResult)
{
	OSStatus err = noErr;
	if( (inSpec == NULL) || (inCurrLevelRef == NULL) || (inProcPtr == NULL) )
		return -1;

	CFTypeRef currItemRef = NULL;
	CFTypeID itemType = ::CFGetTypeID(inCurrLevelRef);

	CFObjSpec *nextSpec = inSpec->nextSpec;

	if( inSpec->IsTopLevel() )//top level, root item requested
	{
		currItemRef = inCurrLevelRef;
	}
	else if(itemType ==  kCFTypeIDs[kCFType_dict])
	{
		if(inSpec->key != NULL) 
		{
			//Boolean keyExists =
			::CFDictionaryGetValueIfPresent (
								(CFDictionaryRef)inCurrLevelRef,
								(CFStringRef)inSpec->key,
								&currItemRef);
		}
/*
// not really sure if it's a desired behavior
// and if getting dictionary item by index should be enabled 								
		if( !keyExists && (inSpec->index >= 0) )
		{//if key was not found and it looks like positive integer, try getting by index
			CFIndex itemCount = ::CFDictionaryGetCount( (CFDictionaryRef)inCurrLevelRef );
			if( (inSpec->index >= 0) && (inSpec->index < itemCount) )
			{
				const void *dictValues[itemCount];
				::CFDictionaryGetKeysAndValues(
					(CFDictionaryRef)inCurrLevelRef,
					NULL, //keys,
					dictValues);
				currItemRef = dictValues[inSpec->index];
			}
		}
*/
	}
	else if(itemType  == kCFTypeIDs[kCFType_array] )
	{
		CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)inCurrLevelRef );
		if( (inSpec->index >= 0) && (inSpec->index < itemCount) )
			currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)inCurrLevelRef, inSpec->index );
	}

	if(currItemRef == NULL)
	{
		if(sPrintErrorMessages)
		{
            std::string itemStr = CreateUTF8StringFromCFString(inSpec->key);
			std::cerr << "Plister error: item \"" << itemStr << "\" not found in plist file." << std::endl;
		}
		return -1;
	}

	itemType = ::CFGetTypeID(currItemRef);

	if( nextSpec == NULL )
	{
		//the key is requested but we don't have the next specifier so it is about the key for current item
		if( (itemType == kCFTypeIDs[kCFType_dict]) && (inSpec->key != NULL) && (inProcPtr == CreateCFDictItemKey) )
		{
			*outResult = (CFStringRef)CFRetain((CFStringRef)inSpec->key);
			err = noErr;
		}
		else
			err = -1;
	}
	else
	{
		if( (nextSpec->nextSpec == nullptr) && (itemType == kCFTypeIDs[kCFType_dict]) && (nextSpec->index >= 0) )//next item will be the end
		{//dict before the last item and the last one is index
			err = (*inProcPtr)( (CFDictionaryRef)currItemRef, nextSpec->index, outResult );
		}
		else
		{//recursively dig deeper down the chain
			err = CreateDictChildProperty(nextSpec, currItemRef, inProcPtr, outResult);
		}
	}
	
	return err;
}

#pragma mark -


OSStatus
ProcessGetItem(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CFTypeRef *outResult)
{
	OSStatus err = noErr;
	if( (inSpec == NULL) || (inCurrLevelRef == NULL) || (outResult == NULL) )
		return -1;

	CFTypeRef currItemRef = NULL;
	CFTypeID itemType = ::CFGetTypeID(inCurrLevelRef);

	if( inSpec->IsTopLevel() )//top level, root item requested
	{
		currItemRef = inCurrLevelRef;
	}
	else if(itemType ==  kCFTypeIDs[kCFType_dict])
	{
		if(inSpec->key != NULL)
			::CFDictionaryGetValueIfPresent (
								(CFDictionaryRef)inCurrLevelRef,
								(CFStringRef)inSpec->key,
								&currItemRef);
	}
	else if(itemType  == kCFTypeIDs[kCFType_array] )
	{
		CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)inCurrLevelRef );
		if( (inSpec->index >= 0) && (inSpec->index < itemCount) )
			currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)inCurrLevelRef, inSpec->index );
	}

	if(currItemRef == NULL)
	{
		if(sPrintErrorMessages)
		{
			std::string itemStr = CreateUTF8StringFromCFString(inSpec->key);
			std::cerr << "Plister error: item \"" << itemStr << "\" not found in plist file." << std::endl;
		}
		return -1;
	}

	if( inSpec->nextSpec == nullptr )
	{//we reached the end of spec chain - this is the item requested
		*outResult = currItemRef;
	}
	else
	{//recursively dig deeper down the chain
		err = ProcessGetItem(inSpec->nextSpec, currItemRef, outResult);
	}
	
	return err;
}

//this call digs deep until it finds the container for the deepest item
//and returns this container and last item spec
OSStatus
ProcessGetLastItemContainerAndSpec(CFObjSpec *inSpec, CFTypeRef inCurrLevelRef, CFTypeRef *outContainer, CFObjSpec **outLastSpec)
{
	if( (inSpec == NULL) || (inCurrLevelRef == NULL) || (outContainer == NULL) || (outLastSpec == NULL) )
		return -1;

	if( inSpec->nextSpec == nullptr )
	{//next spec reaches the end of spec chain - this is the container requested
		*outContainer = inCurrLevelRef;
		*outLastSpec = inSpec;
		return 0;
	}

	CFTypeRef currItemRef = NULL;
	CFTypeID itemType = ::CFGetTypeID(inCurrLevelRef);

	if( inSpec->IsTopLevel() )//top level, root item requested
	{
		currItemRef = inCurrLevelRef;
	}
	else if(itemType ==  kCFTypeIDs[kCFType_dict])
	{
		if(inSpec->key != NULL)
			::CFDictionaryGetValueIfPresent (
								(CFDictionaryRef)inCurrLevelRef,
								(CFStringRef)inSpec->key,
								&currItemRef);
	}
	else if(itemType  == kCFTypeIDs[kCFType_array] )
	{
		CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)inCurrLevelRef );
		if( (inSpec->index >= 0) && (inSpec->index < itemCount) )
			currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)inCurrLevelRef, inSpec->index );
	}

	if(currItemRef == NULL)
	{
		if(sPrintErrorMessages)
		{
			std::string itemStr = CreateUTF8StringFromCFString(inSpec->key);
			std::cerr << "Plister error: item \"" << itemStr << "\" not found in plist file." << std::endl;
		}
		return -1;
	}

	return ProcessGetLastItemContainerAndSpec(inSpec->nextSpec, currItemRef, outContainer, outLastSpec);
}

OSStatus
ProcessDeleteItem(CFTypeRef inCurrLevelRef, CFObjSpec *inSpec )
{
	OSStatus err = noErr;
	if( (inSpec == NULL) || (inCurrLevelRef == NULL) )
		return -1;

	CFTypeID itemType = ::CFGetTypeID(inCurrLevelRef);
	CFTypeRef currItemRef = NULL;

	CFObjSpec *nextSpec = inSpec->nextSpec;
	if( nextSpec == nullptr )
	{//this is the container we are looking for
		if( inSpec->IsTopLevel() )//top level, root item requested. 
		{
			//cannot remove top container, just remove everything in it
			if( itemType ==  kCFTypeIDs[kCFType_dict] )
			{
				::CFDictionaryRemoveAllValues( (CFMutableDictionaryRef)inCurrLevelRef);
			}
			else if( itemType  == kCFTypeIDs[kCFType_array] )
			{
				::CFArrayRemoveAllValues((CFMutableArrayRef)inCurrLevelRef);
			}
			else
			{
				std::cerr << "Plister error: cannot modify non-container item." << std::endl;
				err = -1;
			}
		}
		else if( itemType == kCFTypeIDs[kCFType_dict] )
		{
			if(inSpec->key != NULL)
				::CFDictionaryRemoveValue( (CFMutableDictionaryRef)inCurrLevelRef, (CFStringRef)inSpec->key );
		}
		else if( itemType  == kCFTypeIDs[kCFType_array] )
		{
			if( (inSpec->index >=0) && (inSpec->index < ::CFArrayGetCount((CFArrayRef)inCurrLevelRef)) )
				::CFArrayRemoveValueAtIndex((CFMutableArrayRef)inCurrLevelRef, inSpec->index);
		}
		else
		{
			std::cerr << "Plister error: cannot modify non-container item." << std::endl;
			err = -1;
		}
		return err;
	}
	
	if( inSpec->IsTopLevel() )//top level
	{
		currItemRef = inCurrLevelRef;
	}
	else if( itemType ==  kCFTypeIDs[kCFType_dict] )
	{
		if(inSpec->key != NULL)
			::CFDictionaryGetValueIfPresent( (CFDictionaryRef)inCurrLevelRef, (CFStringRef)inSpec->key, &currItemRef);
	}
	else if( itemType  == kCFTypeIDs[kCFType_array] )
	{
		CFIndex itemCount = ::CFArrayGetCount( (CFArrayRef)inCurrLevelRef );
		if( (inSpec->index >= 0) && (inSpec->index < itemCount) )
			currItemRef = ::CFArrayGetValueAtIndex( (CFArrayRef)inCurrLevelRef, inSpec->index );
	}
	else
	{
		std::cerr << "Plister error: cannot modify non-container item." << std::endl;
		return -1;
	}
	
	if(currItemRef == NULL)
	{
		if(sPrintErrorMessages)
		{
			std::string itemStr = CreateUTF8StringFromCFString(inSpec->key);
			std::cerr << "Plister error: container \"" << itemStr << "\" not found in plist file." << std::endl;
		}
		return -1;
	}

	return ProcessDeleteItem( currItemRef, nextSpec );	
}


#pragma mark -

CFTypeRef
CreateCFItemFromArgumentString(PropertyType inCFObjType, const char *valueStr)
{
	if( (inCFObjType == kCFType_data) && (valueStr != NULL) )
	{
		unsigned long encodedLen = strlen(valueStr);
		if(encodedLen != 0)
		{
			unsigned long buffSize = CalculateDecodedBufferMaxSize(encodedLen);
			char* buff = (char* )malloc(buffSize);
			if(buff != NULL)
			{
				unsigned long decodedSize = DecodeBase64( (const unsigned char *)valueStr, encodedLen, (unsigned char *)buff, buffSize );
				if(decodedSize != 0)
					return ::CFDataCreateWithBytesNoCopy( kCFAllocatorDefault, (const UInt8*)buff, decodedSize, kCFAllocatorMalloc );
			}
		}
		return NULL;
	}
	else if(inCFObjType == kCFType_dict)
	{
		return ::CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks );
	}
	else if(inCFObjType == kCFType_array)
	{
		return ::CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
	}

	if( valueStr == NULL )
		return NULL;

	CFObj<CFStringRef> valueStrRef( ::CFStringCreateWithCString(kCFAllocatorDefault, valueStr, kCFStringEncodingUTF8) );
	if(valueStrRef == NULL)
	{
		//CFStringCreateWithCString returns NULL for any byte sequence that is not
		//valid UTF-8. Unchecked, that NULL went straight into
		//CFNumberFormatterCreateNumberFromString, CFStringCompare and
		//CFDateFormatterCreateDateFromString below - a SIGSEGV for every type but
		//string and data. Returning NULL here is what lets the caller's
		//"could not be read as the specified type" guard do its job: the guard
		//tests the return value, so it never ran for the types that died inside.
		return NULL;
	}

	switch(inCFObjType)
	{
		case kCFType_string:
		{
			return valueStrRef.Detach();
		}
		break;
		
		case kCFType_integer:
		{
			CFObj<CFNumberFormatterRef> formatter( ::CFNumberFormatterCreate( kCFAllocatorDefault, NULL, kCFNumberFormatterNoStyle) );
			return ::CFNumberFormatterCreateNumberFromString(kCFAllocatorDefault, formatter, valueStrRef, NULL, kCFNumberFormatterParseIntegersOnly);
		}
		break;
		
		case kCFType_real:
		{
			CFObj<CFNumberFormatterRef> formatter( ::CFNumberFormatterCreate( kCFAllocatorDefault, NULL, kCFNumberFormatterNoStyle) );
			return ::CFNumberFormatterCreateNumberFromString(kCFAllocatorDefault, formatter, valueStrRef, NULL, 0);
		}
		break;

		case kCFType_bool:
		{
			if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("true"), valueStrRef, kCFCompareCaseInsensitive)) ||
				(kCFCompareEqualTo == ::CFStringCompare( CFSTR("yes"), valueStrRef, kCFCompareCaseInsensitive)) ||
				(kCFCompareEqualTo == ::CFStringCompare( CFSTR("1"), valueStrRef, 0)) )
				return ::CFRetain(kCFBooleanTrue);
			else if( (kCFCompareEqualTo == ::CFStringCompare( CFSTR("false"), valueStrRef, kCFCompareCaseInsensitive)) ||
				(kCFCompareEqualTo == ::CFStringCompare( CFSTR("no"), valueStrRef, kCFCompareCaseInsensitive)) ||
				(kCFCompareEqualTo == ::CFStringCompare( CFSTR("0"), valueStrRef, 0)) )
				return ::CFRetain(kCFBooleanFalse);
		}
		break;
		
		case kCFType_date:
		{
			CFObj<CFDateFormatterRef> formatter( ::CFDateFormatterCreate( kCFAllocatorDefault, NULL,
																		kCFDateFormatterNoStyle, kCFDateFormatterNoStyle) );
			return ::CFDateFormatterCreateDateFromString(kCFAllocatorDefault, formatter, valueStrRef, NULL);
		}
		break;

		default:
		{
			std::cerr << "Plister: invalid property type" << std::endl;
		}
		break;
	}

	return NULL;
}

#pragma mark -

void
DisplayHelp()
{
	std::cerr << "Usage: plister command command_params path/to/plist/file plist/property/pseudopath" << std::endl;
	std::cerr << "File format is auto-detected by extension: use .json for JSON, .plist for XML/binary plist" << std::endl;
	std::cerr << "For any other extension the file's own content decides, so a JSON document may be named anything" << std::endl;
	std::cerr << "All commands work identically for both JSON and plist formats. Output format matches input format:" << std::endl;
	std::cerr << "a binary plist stays binary, a JSON file stays JSON. A file being created has no content to go on," << std::endl;
	std::cerr << "so an extension other than .json means XML." << std::endl << std::endl;
	std::cerr << "Available commands: get, set, remove|delete, add|append, insert, find, findall, iterate" << std::endl;
	std::cerr << "\"insert\" command is for dict or array and must be followed by a key or index respectively" << std::endl;
	std::cerr << "\"set\" command is for replacing existing value with new value" << std::endl;
	std::cerr << "\"add\"|\"append\" command is for array only"  << std::endl;
	std::cerr << "\"find\", \"findall\" and \"iterate\" commands are for containers only (dict or array)"  << std::endl;
	std::cerr << " \"iterate\" syntax: plister iterate [path/to/file.plist] /path/to/container command command_params subpath/to/item"  << std::endl << std::endl;
	std::cerr << "Available params for \"get\": type, key, keys, value, string, count" << std::endl;
	std::cerr << "Available parameter types for \"find\" and \"findall\": string, integer, real, bool" << std::endl;
	std::cerr << "Available parameter types for \"set\", \"add\", \"insert\": string, integer, real, bool, date, data, dict, array, copy" << std::endl;
	std::cerr << "Parameter types: string, integer, real, bool, date, data must be followed by an appropriate value" << std::endl;
	std::cerr << "\"data\" must be followed by Base64 encoded string" << std::endl;
	std::cerr << "\"dict\" and \"array\" are used for creating new empty containers and must not be followed by any value" << std::endl;
	std::cerr << "(they therefore take one argument less than every other type - see the \"append dict\" example below)" << std::endl;
	std::cerr << "\"copy\" is a special directive which must be followed by source/file/path source/property/pseudopath" << std::endl << std::endl;
	std::cerr << "\"find\" and \"findall\" commands may use a sub-item pseudopath as the last parameter"  << std::endl;
	std::cerr << "to specify a container item-relative path which points to something inside that item for matching:"  << std::endl;
	std::cerr << "plister find string \"Item\" file.plist /path/to/container subpath/to/item"  << std::endl;
	std::cerr << "It is needed because item in searched container may be a container itself and we need a simple type as a match criteria."  << std::endl;
	std::cerr << "When searching array, found item index is returned, for dictionary: found item key is returned"  << std::endl;
	std::cerr << "\"find\" returns only the first match while \"findall\" returns all matches. If no matching items are found, empty string is returned."  << std::endl << std::endl;
	std::cerr << "Examples:" << std::endl;
	std::cerr << "Start by creating a new plist file with dictionary as a root container:" << std::endl;
	std::cerr << "plister set dict example.plist /" << std::endl;
	std::cerr << "plister insert \"VERSION\" integer 1 example.plist /" << std::endl;
	std::cerr << "plister get value example.plist /VERSION" << std::endl;
	std::cerr << "plister set integer 2 example.plist /VERSION" << std::endl;
	std::cerr << "plister insert \"NewArray\" array example.plist /"  << std::endl;
	std::cerr << "plister add integer 10 example.plist /NewArray"  << std::endl;
	std::cerr << "plister append integer 20 example.plist /NewArray"  << std::endl;
	std::cerr << "plister get count example.plist /NewArray" << std::endl;
	std::cerr << "plister get type example.plist /NewArray/0" << std::endl;
	std::cerr << "plister get value example.plist /NewArray/1" << std::endl;
	std::cerr << "plister remove example.plist /NewArray/1" << std::endl;
	std::cerr << "plister insert \"NewDict\" dict example.plist /" << std::endl;
	std::cerr << "plister insert \"New Key\" string \"New Value\" example.plist /NewDict" << std::endl;
	std::cerr << "plister get keys example.plist /NewDict" << std::endl << std::endl;

	std::cerr << "Append a whole dictionary to an array and then fill it in (\"dict\" takes no value argument):" << std::endl;
	std::cerr << "plister append dict example.plist /NewArray" << std::endl;
	std::cerr << "plister insert \"Name\" string \"Widget\" example.plist /NewArray/2" << std::endl << std::endl;

	std::cerr << "Now create new.plist and copy \"NewArray\" from example.plist:" << std::endl;
	std::cerr << "plister set dict new.plist /" << std::endl;
	std::cerr << "plister insert \"DuplicateArray\" copy example.plist /NewArray new.plist /" << std::endl << std::endl;
	std::cerr << "Find a command named \"Touch File\" in COMMAND_LIST array in OMC plist:" << std::endl;
	std::cerr << "plister find string \"Touch File\" Command.plist /COMMAND_LIST /NAME" << std::endl << std::endl;
	std::cerr << "plister iterate example.plist /NewArray get string /" << std::endl << std::endl;
	std::cerr << "JSON examples (same commands work on .json files):" << std::endl;
	std::cerr << "plister set dict config.json /" << std::endl;
	std::cerr << "plister insert \"host\" string \"localhost\" config.json /" << std::endl;
	std::cerr << "plister insert \"port\" integer 8080 config.json /" << std::endl;
	std::cerr << "plister get value config.json /host" << std::endl;
	std::cerr << "plister set string \"192.168.1.1\" config.json /host" << std::endl << std::endl;
}
