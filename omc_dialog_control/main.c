
#include <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <sys/stat.h>
#include "ACFPropertyList.h"
#include "AppGroupIdentifier.h"

static char sFilePath[1024];

typedef enum InstructionID
{
	omc_set_control_value = 0,
	omc_set_value_from_stdin,
	omc_enable,
	omc_disable,
	omc_show,
	omc_hide,
	omc_list_remove_all,
	omc_list_append_items,
	omc_list_append_items_from_file,
	omc_list_append_items_from_stdin,
	omc_table_remove_all_rows,
	omc_table_prepare_empty, //like omc_table_remove_all_rows but without reload/refresh
	omc_table_add_rows,
	omc_table_add_rows_from_file,
	omc_table_add_rows_from_stdin,
	omc_table_set_columns,
	omc_table_set_column_widths,
	omc_set_command_id,
	omc_resize, //for window or control
	omc_move, //for window or control
	omc_scroll, //for NSScrollView or view within scroll view
	omc_select, //bring window to front, maybe for some controls too (tab control?)
	omc_terminate_ok, //for dialog
	omc_terminate_cancel, //for dialog
	omc_invoke
} InstructionID;


typedef struct InstructionWord
{
	size_t len;
	CFStringRef word;
	CFStringRef key;
	bool boolValue;//only used for boolean switches
	bool appendable;
	int32_t argumentCount;
} InstructionWord;

enum
{
	kArgumentCount_Variable = -1,
	kArgumentCount_FromFile = -2,
	kArgumentCount_FromStdin = -3,
};

static InstructionWord sInstructionWordList[] =
{
	{ 0,													CFSTR(""),										CFSTR("VALUES"),				true, false,	0 },
	{ sizeof("omc_set_value_from_stdin")-1,					CFSTR("omc_set_value_from_stdin"),				CFSTR("VALUES"),				true, false,	kArgumentCount_FromStdin },
	{ sizeof("omc_enable")-1,								CFSTR("omc_enable"),							CFSTR("ENABLE_DISABLE"),		true, false,	0 },
	{ sizeof("omc_disable")-1,								CFSTR("omc_disable"),							CFSTR("ENABLE_DISABLE"),		false, false,	0 },
	{ sizeof("omc_show")-1,									CFSTR("omc_show"),								CFSTR("SHOW_HIDE"),				true, false,	0 },
	{ sizeof("omc_hide")-1,									CFSTR("omc_hide"),								CFSTR("SHOW_HIDE"),				false, false,	0 },
	{ sizeof("omc_list_remove_all")-1,						CFSTR("omc_list_remove_all"),					CFSTR("REMOVE_LIST_ITEMS"),		true, false,	0 },
	{ sizeof("omc_list_append_items")-1,					CFSTR("omc_list_append_items"),					CFSTR("APPEND_LIST_ITEMS"),		true, true,		kArgumentCount_Variable },
	{ sizeof("omc_list_append_items_from_file")-1,			CFSTR("omc_list_append_items_from_file"),		CFSTR("APPEND_LIST_ITEMS"),		true, true,		kArgumentCount_FromFile },
	{ sizeof("omc_list_append_items_from_stdin")-1,			CFSTR("omc_list_append_items_from_stdin"),		CFSTR("APPEND_LIST_ITEMS"),		true, true,		kArgumentCount_FromStdin },
	{ sizeof("omc_table_remove_all_rows")-1,				CFSTR("omc_table_remove_all_rows"),				CFSTR("REMOVE_TABLE_ROWS"),		true, false,	0 },
	{ sizeof("omc_table_prepare_empty")-1,					CFSTR("omc_table_prepare_empty"),				CFSTR("PREPARE_TABLE_EMPTY"),	true, false,	0 },
	{ sizeof("omc_table_add_rows")-1,						CFSTR("omc_table_add_rows"),					CFSTR("ADD_TABLE_ROWS"),		true, true,		kArgumentCount_Variable },
	{ sizeof("omc_table_add_rows_from_file")-1,				CFSTR("omc_table_add_rows_from_file"),			CFSTR("ADD_TABLE_ROWS"),		true, true,		kArgumentCount_FromFile },
	{ sizeof("omc_table_add_rows_from_stdin")-1,			CFSTR("omc_table_add_rows_from_stdin"),			CFSTR("ADD_TABLE_ROWS"),		true, true,		kArgumentCount_FromStdin },
	{ sizeof("omc_table_set_columns")-1,					CFSTR("omc_table_set_columns"),					CFSTR("SET_TABLE_COLUMNS"),		true, false,	kArgumentCount_Variable },
	{ sizeof("omc_table_set_column_widths")-1,				CFSTR("omc_table_set_column_widths"),			CFSTR("SET_TABLE_WIDTHS"),		true, false,	kArgumentCount_Variable },
	{ sizeof("omc_set_command_id")-1,						CFSTR("omc_set_command_id"),					CFSTR("COMMAND_IDS"),			true, false,	1 },
	{ sizeof("omc_resize")-1,								CFSTR("omc_resize"),							CFSTR("RESIZE"),				true, false,	2 },
	{ sizeof("omc_move")-1,									CFSTR("omc_move"),								CFSTR("MOVE"),					true, false,	2 },
	{ sizeof("omc_scroll")-1,								CFSTR("omc_scroll"),							CFSTR("SCROLL"),				true, false,	2 },
	{ sizeof("omc_select")-1,								CFSTR("omc_select"),							CFSTR("SELECT"),				true, false,	0 },
	{ sizeof("omc_terminate_ok")-1,							CFSTR("omc_terminate_ok"),						CFSTR("TERMINATE"),				true, false,	0 },
	{ sizeof("omc_terminate_cancel")-1,						CFSTR("omc_terminate_cancel"),					CFSTR("TERMINATE"),				false, false,	0 },
	{ sizeof("omc_invoke")-1,								CFSTR("omc_invoke"),							CFSTR("INVOKE"),				true, true,		kArgumentCount_Variable }

};

//min and max len defined for slight optimization in resolving instructions
//the shortest is omc_show
const size_t kMinInstructionWordLen = sizeof("omc_show") - 1;
//the longest is omc_list_append_items_from_stdin
const size_t kMaxInstructionWordLen = sizeof("omc_list_append_items_from_stdin") - 1;


static inline InstructionID
GetInstructionID(CFStringRef inStr)
{
	if(inStr == NULL)
		return omc_set_control_value;

  	size_t	strLen = (size_t)CFStringGetLength(inStr);
	if( (strLen < kMinInstructionWordLen) || (strLen > kMaxInstructionWordLen))
		return omc_set_control_value;

  	UniChar oneChar = CFStringGetCharacterAtIndex(inStr, 0);
	if(oneChar != 'o')
		return omc_set_control_value; //special word must start with omc

	size_t instructionCount = sizeof(sInstructionWordList)/sizeof(InstructionWord);
	for(size_t i = 0; i < instructionCount; i++)
	{
		if(sInstructionWordList[i].len == strLen)
		{
			if( kCFCompareEqualTo == CFStringCompare( inStr, sInstructionWordList[i].word, 0) )
			{
				return (InstructionID)i;
			}
		}
	}

	return omc_set_control_value;
}


int main (int argc, const char * argv[])
{
	int result = 0;
	CFStringRef key = NULL;
	CFStringRef controlIDStr = NULL;
	CFURLRef urlRef = NULL;
	CFTypeRef theResult = NULL;
	CFMutableDictionaryRef plistDict = NULL;
	CFMutableDictionaryRef appendListItemsDict = NULL;
	CFMessagePortRef remotePort = NULL;

	if(argc < 4)
	{
		fprintf(stdout, "\nUsage: omc_dialog_control __NIB_DLG_GUID__ <controlID> <value>\n\n");
		fprintf(stdout, "<controlID> is an integer for control tag or special values:\n");
		fprintf(stdout, "\t\"omc_window\" to specify that the target is dialog window\n");
		fprintf(stdout, "\t\"omc_application\" to specify that the target is host application\n");
		fprintf(stdout, "\t\"omc_workspace\" to specify that the target is shared NSWorkspace\n");
		fprintf(stdout, "Special values:\n\tomc_enable, omc_disable\n\tomc_show, omc_hide\n");
		fprintf(stdout, "\tomc_set_value_from_stdin (read from stdin or pipe)\n");
		fprintf(stdout, "\tomc_set_command_id [followed by command id string]\n");
		fprintf(stdout, "\tomc_list_remove_all\n");
		fprintf(stdout, "\tomc_list_append_items [followed by variable number of arguments]\n");
		fprintf(stdout, "\tomc_list_append_items_from_file [followed by file name]\n");
		fprintf(stdout, "\tomc_list_append_items_from_stdin (read from stdin or pipe)\n");
		fprintf(stdout, "\tomc_table_set_columns [followed by column names - variable num of args]\n");
		fprintf(stdout, "\tomc_table_set_column_widths [followed by column widths - variable num of args]\n");
		fprintf(stdout, "\tomc_table_remove_all_rows\n");
		fprintf(stdout, "\tomc_table_prepare_empty (like omc_table_remove_all_rows but without refresh)\n");
		fprintf(stdout, "\tomc_table_add_rows [followed by tab-separated row strings]\n");
		fprintf(stdout, "\tomc_table_add_rows_from_file [followed by file name - tab separated data]\n");
		fprintf(stdout, "\tomc_table_add_rows_from_stdin (read from stdin or pipe - tab separated data)\n");
		fprintf(stdout, "\tomc_select (brings dialog window or app to front, sets control focus)\n");
		fprintf(stdout, "\tomc_terminate_ok (close dialog with OK message)\n");
		fprintf(stdout, "\tomc_terminate_cancel (close dialog with Cancel message)\n");
		fprintf(stdout, "\tomc_resize [followed by 2 space separated numbers] (for dialog window or controls)\n");
		fprintf(stdout, "\tomc_move [followed by 2 space separated numbers] (for dialog window or controls)\n");
		fprintf(stdout, "\tomc_scroll [followed by 2 space separated numbers] (for view within NSScrollerView)\n");
		fprintf(stdout, "\tomc_invoke [followed by space separated ObjC message] (may be sent to control or window)\n\n");
		
		fprintf(stdout, "Examples:\nomc_dialog_control __NIB_DLG_GUID__ 4 \"hello world!\"\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 2 omc_disable\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 1 omc_set_command_id \"Exec\"\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_remove_all\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_append_items \"Item 1\" \"Item 2\"\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_append_items_from_file items.txt\n");
		fprintf(stdout, "ls | omc_dialog_control __NIB_DLG_GUID__ 3 omc_list_append_items_from_stdin\n\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_set_columns \"A\" omc_hidden_column \"B\" \"C\"\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_set_column_widths 90 0 50 80\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_remove_all_rows\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_add_rows \"11	Hidden1	12	13\" \"21	Hidden2	22	23\"\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_add_rows_from_file mydata.tsv\n");
		fprintf(stdout, "cat mydata.tsv | omc_dialog_control __NIB_DLG_GUID__ 5 omc_table_add_rows_from_stdin\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ omc_window omc_resize 600 200\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 2 omc_move 20 20\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 4 omc_scroll 0 0\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ omc_window omc_terminate_cancel\n");
		fprintf(stdout, "omc_dialog_control __NIB_DLG_GUID__ 2 omc_invoke setAlignment: 2\n");

		result = -1;
		goto error_exit;
	}

//read control_ID
	if(argv[2] != NULL)
	{
		controlIDStr = CFStringCreateWithCString(kCFAllocatorDefault, argv[2], kCFStringEncodingUTF8);
		if(controlIDStr != NULL)
		{
			if( (kCFCompareEqualTo == CFStringCompare( controlIDStr, CFSTR("omc_window"), 0)) ||
				(kCFCompareEqualTo == CFStringCompare( controlIDStr, CFSTR("omc_application"), 0)) ||
			    (kCFCompareEqualTo == CFStringCompare( controlIDStr, CFSTR("omc_workspace"), 0))
			   )
			{
				;//we are good, special id to target dialog window instead of control
			}
            /* a number or control id string (string supported starting with Mac OS 10.7)
			else
			{
				SInt32 controlID = CFStringGetIntValue(controlIDStr);
				if( (controlID <= 0) || (controlID > 9999))
				{
					controlIDStr = NULL;
				}
			}
            */
		}
	}
	
	if(controlIDStr == NULL)
	{
		//fprintf(stderr, "Invalid control ID number provided. It must be between 1 and 9999.\n");
		fprintf(stderr, "Invalid control ID provided\n");
		result = -1;
		goto error_exit;
	}

	CFStringRef valueStr = CFStringCreateWithCString(kCFAllocatorDefault, argv[3], kCFStringEncodingUTF8);
	InstructionID instruction = GetInstructionID(valueStr);//must return valid index
	key = sInstructionWordList[instruction].key;

	CFStringRef portName = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s.OMCDialogControlPort-%s"), GetAppGroupIdentifier(), argv[1]);
	if(portName != NULL)
	{
		remotePort = CFMessagePortCreateRemote(kCFAllocatorDefault, portName);//should return non-null if listener port created
	}

	if(remotePort == NULL)
	{//not communicating through port - write to file
		//fprintf(stderr, "Could not create a communication port with dialog. Saving params to plist file\n");

		if( access("/tmp/OMC", F_OK|R_OK|W_OK|X_OK) != 0 )
		{
			mkdir("/tmp/OMC", S_IRWXU|S_IRWXG|S_IRWXO);
			//for some reason the mkdir does not set the writable flag for group and others so do it again with chmod
			chmod("/tmp/OMC", S_IRWXU|S_IRWXG|S_IRWXO);
		}

		snprintf(sFilePath, sizeof(sFilePath), "/tmp/OMC/%s.plist", argv[1]);
		urlRef = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8*)sFilePath, strlen(sFilePath), false);
	}
	
	if(urlRef != NULL)
	{
        CFPropertyListRef thePlist = CreatePropertyList(urlRef, kCFPropertyListMutableContainers);
        if(thePlist != NULL)
        {
            if(CFDictionaryGetTypeID() == CFGetTypeID(thePlist) )
            {
                plistDict = (CFMutableDictionaryRef)thePlist;
            }
            else
            {
                CFRelease(thePlist);
            }
        }
	}
	
	if(plistDict == NULL)
	{//create new one
		plistDict = CFDictionaryCreateMutable( kCFAllocatorDefault, 0,
											&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
	}

	if(plistDict == NULL)
	{
		fprintf(stderr, "An error ocurred when creating new property list. Out of memory?!\n");
		result = -1;
		goto error_exit;
	}

	if(valueStr != NULL)
	{
		if( (instruction == omc_set_control_value) || (instruction == omc_set_value_from_stdin) )//regular control values
		{
			CFMutableDictionaryRef valuesDict = NULL;
			theResult = CFDictionaryGetValue(plistDict, (const void *)key);
			if( (theResult != NULL) && (CFDictionaryGetTypeID() == CFGetTypeID(theResult)) )
				valuesDict = (CFMutableDictionaryRef)theResult;
			
			if(valuesDict == NULL)
			{//create new one
				valuesDict = CFDictionaryCreateMutable( kCFAllocatorDefault, 0,
													   &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
				if(valuesDict != NULL)
				{
					CFDictionarySetValue(plistDict, key, valuesDict);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFDictionary. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}
			
			if(sInstructionWordList[instruction].argumentCount == kArgumentCount_FromStdin)
			{
				static UInt8 sStdinBuff[1024];
				CFMutableDataRef wholeStdinData = CFDataCreateMutable(kCFAllocatorDefault, 0);
				if(wholeStdinData != NULL)
				{
					size_t bytesRead = 0;
					while( (bytesRead = fread(sStdinBuff, sizeof(UInt8), sizeof(sStdinBuff), stdin)) > 0)
					{
						CFDataAppendBytes(wholeStdinData, sStdinBuff, bytesRead);
					}
					CFIndex wholeLen = CFDataGetLength(wholeStdinData);
					UInt8 *wholeBuff = CFDataGetMutableBytePtr(wholeStdinData);
					CFStringRef wholeStr = CFStringCreateWithBytes(kCFAllocatorDefault, wholeBuff, wholeLen, kCFStringEncodingUTF8, true);
					CFRelease(wholeStdinData);
					
					if(wholeStr != NULL)
					{
						//CFShow(wholeStr);
						CFDictionarySetValue(valuesDict, controlIDStr, wholeStr);
					}
				}
			}
			else
			{
				CFDictionarySetValue(valuesDict, controlIDStr, valueStr);
			}
		}
		//bool switches or 0 argument instructions for which we set bool but we don't care about the value
		else if( (instruction == omc_enable) || (instruction == omc_disable) || 
			(instruction == omc_show) || (instruction == omc_hide) ||
			(instruction == omc_select) ||
		    (instruction == omc_terminate_ok) || (instruction == omc_terminate_cancel) //ok=true, cancel=false
		   )
		{
			CFMutableDictionaryRef disableDict = NULL;
			theResult = CFDictionaryGetValue(plistDict, (const void *)key);
			if( (theResult != NULL) && (CFDictionaryGetTypeID() == CFGetTypeID(theResult)) )
				disableDict = (CFMutableDictionaryRef)theResult;

			if(disableDict == NULL)
			{//create new one
				disableDict = CFDictionaryCreateMutable( kCFAllocatorDefault, 0,
													&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
				
				if(disableDict != NULL)
				{
					CFDictionarySetValue(plistDict, key, disableDict);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFDictionary. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}
			CFDictionarySetValue(disableDict, controlIDStr, sInstructionWordList[instruction].boolValue ? kCFBooleanTrue : kCFBooleanFalse );
		}
		else if( (instruction == omc_list_remove_all) || 
				(instruction == omc_table_remove_all_rows) ||
				(instruction == omc_table_prepare_empty) )
		{//"remove" always gets processed before adding items in OMC so it works fine
			CFMutableDictionaryRef removeListItemsDict = NULL;
			theResult = CFDictionaryGetValue(plistDict, (const void *)key);
			if( (theResult != NULL) && (CFDictionaryGetTypeID() == CFGetTypeID(theResult)) )
				removeListItemsDict = (CFMutableDictionaryRef)theResult;

			if(removeListItemsDict == NULL)
			{//create new one
				removeListItemsDict = CFDictionaryCreateMutable( kCFAllocatorDefault, 0,
													&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
				
				if(removeListItemsDict != NULL)
				{
					CFDictionarySetValue(plistDict, key, removeListItemsDict);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFDictionary. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}
			CFDictionarySetValue(removeListItemsDict, controlIDStr, kCFBooleanTrue);

//now check if there were any pending "append" items for this control id and remove them as well
			CFStringRef arrayKey = NULL;
			if(instruction == omc_list_remove_all)
				arrayKey =  sInstructionWordList[omc_list_append_items].key;
			else // if((instruction == omc_table_remove_all_rows) || (instruction == omc_table_prepare_empty))
				arrayKey = sInstructionWordList[omc_table_add_rows].key;

			theResult = CFDictionaryGetValue(plistDict, (const void *)arrayKey);
			if( (theResult != NULL) && (CFDictionaryGetTypeID() == CFGetTypeID(theResult)) )
			{
				appendListItemsDict = (CFMutableDictionaryRef)theResult;
				if(appendListItemsDict != NULL)
					CFDictionaryRemoveValue(appendListItemsDict, (const void *)controlIDStr);
			}
		}
		else if(instruction == omc_invoke)
		{//omc_invoke is different because it contains an array of arrays (the lowest level array forming one ObjC message)
			theResult = CFDictionaryGetValue(plistDict, (const void *)key);
			if( (theResult != NULL) && (CFDictionaryGetTypeID() == CFGetTypeID(theResult)) )
				appendListItemsDict = (CFMutableDictionaryRef)theResult;
			
			if(appendListItemsDict == NULL)
			{//create new one
				appendListItemsDict = CFDictionaryCreateMutable( kCFAllocatorDefault, 0,
																&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
				
				if(appendListItemsDict != NULL)
				{
					CFDictionarySetValue(plistDict, key, appendListItemsDict);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFDictionary. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}
			
			CFMutableArrayRef itemArray = NULL;
			theResult = CFDictionaryGetValue(appendListItemsDict, (const void *)controlIDStr);
			if( (theResult != NULL) && (CFArrayGetTypeID() == CFGetTypeID(theResult)) )
				itemArray = (CFMutableArrayRef)theResult;
			
			if(itemArray == NULL)
			{
				itemArray = CFArrayCreateMutable( kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks );
				if(itemArray != NULL)
				{
					CFDictionarySetValue(appendListItemsDict, controlIDStr, itemArray);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFArray. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}
			//variable item count
			int itemCount = argc;
			if(itemCount > 4)
			{
				CFMutableArrayRef objCMessageArray = CFArrayCreateMutable( kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks );
				if(objCMessageArray != NULL)
				{
					for(int i = 4; i < itemCount; i++)
					{
						CFStringRef itemStr = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
						if(itemStr != NULL)
						{
							CFArrayAppendValue( objCMessageArray, itemStr );
						}
						else
						{
							fprintf(stderr, "An error ocurred when creating string with CFStringCreateWithCString. Not UTF-8?\n");
						}
					}
					CFArrayAppendValue( itemArray, objCMessageArray );
				}
			}
		}
		//multiple argument instructions, new values appended or replaced in subarray
		else if( (sInstructionWordList[instruction].argumentCount != 0) &&
				(sInstructionWordList[instruction].argumentCount != 1) )
		{//adding items after remove command was issued is ok. the recipient will remove first and add next
			theResult = CFDictionaryGetValue(plistDict, (const void *)key);
			if( (theResult != NULL) && (CFDictionaryGetTypeID() == CFGetTypeID(theResult)) )
				appendListItemsDict = (CFMutableDictionaryRef)theResult;

			if(appendListItemsDict == NULL)
			{//create new one
				appendListItemsDict = CFDictionaryCreateMutable( kCFAllocatorDefault, 0,
													&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
				
				if(appendListItemsDict != NULL)
				{
					CFDictionarySetValue(plistDict, key, appendListItemsDict);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFDictionary. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}
			
			CFMutableArrayRef itemArray = NULL;
			theResult = CFDictionaryGetValue(appendListItemsDict, (const void *)controlIDStr);
			if( (theResult != NULL) && (CFArrayGetTypeID() == CFGetTypeID(theResult)) )
				itemArray = (CFMutableArrayRef)theResult;
			
			if(itemArray == NULL)
			{
				itemArray = CFArrayCreateMutable( kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks );
				if(itemArray != NULL)
				{
					CFDictionarySetValue(appendListItemsDict, controlIDStr, itemArray);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFArray. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}
			
			//variable item count
			int itemCount = argc;

			if( (sInstructionWordList[instruction].argumentCount == kArgumentCount_Variable) ||
			    (sInstructionWordList[instruction].argumentCount > 0) )
			{
				if( !sInstructionWordList[instruction].appendable )
					CFArrayRemoveAllValues(itemArray);//those commands are not "appendable" 
					
				for(int i = 4; i < itemCount; i++)
				{
					CFStringRef itemStr = CFStringCreateWithCString(kCFAllocatorDefault, argv[i], kCFStringEncodingUTF8);
					if(itemStr != NULL)
					{
						CFArrayAppendValue( itemArray, itemStr );
					}
					else
					{
						fprintf(stderr, "An error ocurred when creating string with CFStringCreateWithCString. Not UTF-8?\n");
					}
				}
			}
			else if( (sInstructionWordList[instruction].argumentCount == kArgumentCount_FromFile) ||
					(sInstructionWordList[instruction].argumentCount == kArgumentCount_FromStdin) )
			{
				FILE *fp = NULL;
				int sizofBuff = 128*1024;//max buffer per one line because fgets() is a primitive method of reading the line
				char *buff = malloc(sizofBuff);

				if( (sInstructionWordList[instruction].argumentCount == kArgumentCount_FromFile) &&
				   (itemCount >= 5) )
				{
					fp = fopen(argv[4], "r");
				}
				else if( sInstructionWordList[instruction].argumentCount == kArgumentCount_FromStdin )
				{
					fp = stdin;
				}
				
				if( (fp != NULL) && (buff != NULL) )
				{
					buff[0] = 0;
					while( fgets(buff, sizofBuff, fp) != NULL )
					{
						buff[sizofBuff-1] = '\0';//force null terminator just in case
						size_t len = strlen(buff);
						if (len > 0 && buff[len-1] == '\n')
						{
							buff[len-1] = '\0';
							len--;
						}
						
						//if there is an empty line, we eat it and not add to the list
						if(len > 0)
						{
							CFStringRef itemStr = CFStringCreateWithBytes(kCFAllocatorDefault, (const UInt8 *)buff, len, kCFStringEncodingUTF8, true);
							if(itemStr != NULL)
							{
								CFArrayAppendValue( itemArray, itemStr );
							}
							else
							{
								fprintf(stderr, "An error ocurred when creating string with CFStringCreateWithBytes. Not UTF-8?\n");
							}
						}
					}
				
					if( sInstructionWordList[instruction].argumentCount == kArgumentCount_FromFile )
						fclose(fp);
				}
			}
		}
		//one argument instructions
		else if( sInstructionWordList[instruction].argumentCount == 1 )
		{
			CFMutableDictionaryRef oneArgIntructionDict = NULL;

			theResult = CFDictionaryGetValue(plistDict, (const void *)key);
			if( (theResult != NULL) && (CFDictionaryGetTypeID() == CFGetTypeID(theResult)) )
				oneArgIntructionDict = (CFMutableDictionaryRef)theResult;

			if(oneArgIntructionDict == NULL)
			{//create new one
				oneArgIntructionDict = CFDictionaryCreateMutable( kCFAllocatorDefault, 0,
													&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
				
				if(oneArgIntructionDict != NULL)
				{
					CFDictionarySetValue(plistDict, key, oneArgIntructionDict);
				}
				else
				{
					fprintf(stderr, "An error ocurred when creating new CFDictionary. Out of memory?!\n");
					result = -1;
					goto error_exit;
				}
			}

			int itemCount = argc;
			if(itemCount == 5)
			{
				CFStringRef argString = CFStringCreateWithCString(kCFAllocatorDefault, argv[4], kCFStringEncodingUTF8);
				if(argString != NULL)
				{
					CFDictionarySetValue(oneArgIntructionDict, controlIDStr, argString);
				}
			}
		}
		else
		{
			fprintf(stderr, "This should not happen: unknown instruction id. Aliens?\n");
		}
	}

    if(urlRef != NULL)
    {   //overwrites previous file content
        bool success = WritePropertyList(plistDict, urlRef, kCFPropertyListBinaryFormat_v1_0);
        if(!success)
            fprintf(stderr, "An error ocurred when writing property list to %s\n", sFilePath);
    }
    else if(remotePort != NULL)
    {
        CFDataRef plistData = CFPropertyListCreateData(kCFAllocatorDefault, plistDict, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
        if(plistData != NULL)
        {
            result = CFMessagePortSendRequest(remotePort, 0/*msgid*/, plistData, 5/*send timeout*/, 0/*rcv timout*/, NULL/*kCFRunLoopDefaultMode*/, NULL/*replyData*/);
            if(result != 0)
                fprintf(stderr, "An error ocurred when sending request to dialog port: %d\n", result);
        }
    }

error_exit:

	if(remotePort != NULL)
		CFRelease(remotePort);

    return result;
}

