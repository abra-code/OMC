#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ABase64.h"

int main (int argc, const char * argv[])
{
	if(argc < 3)
	{
		fprintf(stderr, "usage: b64 encode|decode string|file|stdin path/to/file|string|stdin [output path/to/output/file]\n\n");
		return -1;
	}

	int doEncode = 0;
	int paramIndex = 1;
	const char *commandStr = argv[paramIndex++];
	if( strcmp(commandStr, "encode") == 0 )
		doEncode = 1;
	else if( strcmp(commandStr, "decode") == 0 )
		doEncode = 0;
	else
	{
		fprintf(stderr, "b64 example usage: b64 encode string \"Encode Me!\"");
		return -1;
	}

	unsigned char *inputData = NULL;
	unsigned long inputDataSize = 0;
	int freeInputBuff = 0;

	const char *dataTypeStr = argv[paramIndex++];
	if( strcmp(dataTypeStr, "string") == 0 )
	{
		inputData = (unsigned char *)argv[paramIndex++];
		inputDataSize = strlen((char*)inputData);
	}
	else if( strcmp(dataTypeStr, "file") == 0 )
	{
		const char *filePath = argv[paramIndex++];
		FILE *fp = fopen(filePath, "r");
		if(fp != NULL)
		{
			fseek(fp, 0, SEEK_END);
			inputDataSize = ftell(fp);
			if(inputDataSize != 0)
			{
				fseek(fp, 0, SEEK_SET);
				inputData = (unsigned char *)calloc(1, inputDataSize);
				if(inputData != NULL)
				{
					freeInputBuff = 1;
					fread(inputData, inputDataSize, 1, fp);
				}
			}
			fclose(fp);
		}
	}
	else if( strcmp(dataTypeStr, "stdin") == 0 )
	{
		static char buff[1024];
		FILE *fp = stdin;
		if(fp != NULL)
		{
			inputDataSize = 0;
			freeInputBuff = 1;

			while( fgets(buff, sizeof(buff), fp) != NULL )
			{
				buff[sizeof(buff)-1] = '\0';//force null terminator just in case
				int len = strlen(buff);
				if(inputData == NULL)
				{//first time allocation
					inputData = (unsigned char *)calloc(1, len);
					if(inputData != NULL)
					{
						inputDataSize = len;
						memcpy(inputData, buff, len);
					}
				}
				else
				{//increase block size and copy data
					void *newData = realloc(inputData, inputDataSize + len);
					if(newData != NULL)
					{	
						inputData = newData;
						memcpy(inputData+inputDataSize, buff, len);
						inputDataSize += len;
					}
					else
					{
						fprintf(stderr, "b64 error: cannot allocate memory block");
						free(inputData);
						return -1;
					}
				}
			}
		}
	}
	else
	{
		fprintf(stderr, "b64 example usage: b64 encode string \"Encode Me!\"");
		return -1;
	}

	if( (inputData == NULL) || (inputDataSize == 0) )
	{
		fprintf(stderr, "b64 error: cannot read input data");
		return -1;
	}

	const char *outPath = NULL;
	if( paramIndex < argc )
	{
		const char *optionStr = argv[paramIndex++];
		if( strcmp(optionStr, "output") == 0 )
		{
			if( paramIndex < argc )
				outPath = argv[paramIndex++];
		}
	}

	unsigned char *outputData = NULL;
	unsigned long outputDataLen = 0;

	if(doEncode)
	{
		unsigned long buffSize = CalculateEncodedBufferSize(inputDataSize);
		outputData = (unsigned char *)malloc(buffSize+1);
		if(outputData != NULL)
			outputDataLen = EncodeBase64(inputData, inputDataSize, outputData, buffSize);
	}
	else
	{
		unsigned long buffSize = CalculateDecodedBufferMaxSize(inputDataSize);
		outputData = (unsigned char *)malloc(buffSize+1);
		if(outputData != NULL)
			outputDataLen = DecodeBase64(inputData, inputDataSize, outputData, buffSize);
	}

	if(outputData != NULL)
	{
		if(outPath == NULL)
		{//print to stdout
			fwrite(outputData, outputDataLen, 1, stdout);
			//fprintf(stdout, (char*)outputData); //printf is a formatted output and may corrupt result. 
		}
		else
		{
			FILE *fp = fopen(outPath, "w+");
			if(fp != NULL)
			{
				fwrite(outputData, outputDataLen, 1, fp);
				fclose(fp);
			}
		}
		free(outputData);
	}
	else
	{
		fprintf(stderr, "b64 error: cannot allocate memory block");
	}

	if( freeInputBuff && (inputData != NULL) )
		free(inputData);

    return 0;
}
