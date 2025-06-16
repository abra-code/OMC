//
//  main.m
//  pasteboard
//
//  Created by Tomasz Kukielka on 5/17/14.
//  Copyright (c) 2014 Abracode. All rights reserved.
//

//#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

typedef enum
{
	kOperationUnknown = 0,
	kOperationPut,
	kOperationGet
} PasteboardOperation;

void print_help(void)
{
	fprintf(stdout, "\nNAME\n");
	fprintf(stdout, "\tpasteboard - set or get Mac OS X pasteboard string\n\n");
	fprintf(stdout, "SYNOPSIS\n");
	fprintf(stdout, "\tpasteboard \"Pasteboard Name\" put[set]|get \"String To Set\"\n\n");
	fprintf(stdout, "DESCRIPTION\n");
	fprintf(stdout, "\tpasteboard allows you set or get a string in Mac OS X pasteboard\n");
	fprintf(stdout, "\tIt supports private (named) pasteboards as well as global \"general\" and \"find\" pasteboards\n");
	fprintf(stdout, "\tIt can be used for interprocess communication through private pasteboards\n");
	fprintf(stdout, "\tYou can use either \"put\" or \"set\" command for putting the string in the pasteboard\n");
	
	fprintf(stderr, "USAGE\n");
	fprintf(stderr, "\tpasteboard MyPasteboardName put \"String to put in MyPasteboardName pasteboard\"\n");
	fprintf(stderr, "\tpasteboard general set \"String to put in general pasteboard\"\n");
	fprintf(stderr, "\tpasteboard find put \"String to put in find pasteboard\"\n");
	fprintf(stderr, "\techo \"String to put from stdin\" | pasteboard MyPasteboardName put\n");
	fprintf(stderr, "\tpasteboard MyPasteboardName get\n");
}

//pasteboard "PBName" put "String To Put"
//pasteboard "PBName" get

char *
CreateCStringFromStdIn(void)
{
	char *inputData = NULL;
	unsigned long inputDataSize = 0;
	static char buff[1024];

	while( fgets(buff, sizeof(buff), stdin) != NULL )
	{
		buff[sizeof(buff)-1] = '\0';//force null terminator just in case
		unsigned long len = strlen(buff);
		if(inputData == NULL)
		{//first time allocation
			inputData = (char *)calloc(1, len+1);
			if(inputData != NULL)
			{
				memcpy(inputData, buff, len);
				inputDataSize = len;
				inputData[inputDataSize] = 0;
			}
			else
			{
				fprintf(stderr, "error: cannot allocate memory block for stdin text");
				return NULL;
			}
		}
		else
		{//increase block size and copy data
			void *newData = realloc(inputData, inputDataSize + len+1);
			if(newData != NULL)
			{	
				inputData = newData;
				memcpy(inputData+inputDataSize, buff, len);
				inputDataSize += len;
				inputData[inputDataSize] = 0;
			}
			else
			{
				fprintf(stderr, "error: cannot allocate memory block for stdin text");
				free(inputData);
				return NULL;
			}
		}
	}

	return inputData;
}

int main(int argc, const char * argv[])
{
	if(argc < 3)
	{
		print_help();
		return -1;
	}

	const char *pbNameStr = argv[1];
	
	PasteboardOperation pbOperation = kOperationUnknown;
	const char *operStr = argv[2];
	if( strncmp("put", operStr, 4) == 0 || strncmp("set", operStr, 4) == 0 )
	{
		pbOperation = kOperationPut;
	}
	else if( strncmp("get", operStr, 5) == 0 )
	{
		pbOperation = kOperationGet;
	}
	else
	{
		fprintf(stderr, "Unknown pasteboard operation. Allowed operations are 'put' and 'get'\n");
		return -1;
	}

	const char *strToPut = "";
	
	if( pbOperation == kOperationPut )
	{
		if(argc > 3)
		{
			strToPut = argv[3];
		}
		else
		{
			 //no need to free because it is a cmd line tool that exists soon
			strToPut = CreateCStringFromStdIn();
			if(strToPut == NULL)
				strToPut = "";
		}
	}

	@autoreleasepool
	{
		NSString *pasteboardName = NULL;
		if( strncmp("general", pbNameStr, 7) == 0)
			pasteboardName = NSPasteboardNameGeneral;
		else if( strncmp("find", pbNameStr, 4) == 0)
			pasteboardName = NSPasteboardNameFind;
		else
			pasteboardName = [NSString stringWithUTF8String:pbNameStr];
	    
		NSPasteboard *myPasteboard = [NSPasteboard pasteboardWithName:pasteboardName];
		
		if( pbOperation == kOperationPut )
		{
			[myPasteboard clearContents];
			if(strToPut[0] != 0)
			{
				NSString *stringToPut = [NSString stringWithUTF8String:strToPut];
				if(stringToPut != NULL)
					[myPasteboard writeObjects:@[stringToPut]];
			}
		}
		else if( pbOperation == kOperationGet )
		{
			NSArray *classesArray = [NSArray arrayWithObject:[NSString class]];
			NSDictionary *optionsDict = [NSDictionary dictionary];
			NSArray *stringObjects = [myPasteboard readObjectsForClasses:classesArray options:optionsDict];
			if(stringObjects.count > 0)
			{
				NSString *myOutStr = [stringObjects objectAtIndex:0];
				const char *cStr = [myOutStr cStringUsingEncoding:NSUTF8StringEncoding];
				fprintf(stdout, "%s", cStr);
			}
		}
	}
    return 0;
}

