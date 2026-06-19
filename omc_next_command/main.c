#include <unistd.h>
#include <sys/stat.h>
#include <stdio.h>
#include <string.h>
#include "OMCEngineTempDir.h"

static char sFilePath[1024];

int main (int argc, const char * argv[])
{
	int result = 0;

	if(argc != 3)
	{
		fprintf(stderr, "usage: omc_next_command __CURRENT_COMMAND_GUID__ <next_command_ID>\nFor example: omc_next_command __CURRENT_COMMAND_GUID__ \"NeXT\"\n\n");
		return -1;
	}

	const char *theNextID = argv[2];
	size_t theIDLen = strlen(theNextID);
	if(theIDLen == 0)
	{
		fprintf(stderr, "Invalid next command ID\n");
		return -1;
	}

	// Engine-internal IPC file in the per-user temp dir (see OMCEngineTempDir.h).
	char leafName[512];
	snprintf(leafName, sizeof(leafName), "%s.id", argv[1]);
	if( !OMCGetEngineTempFilePath(leafName, true /*create dir*/, sFilePath, sizeof(sFilePath)) )
	{
		fprintf(stderr, "could not resolve engine temp path for next command id\n");
		return -1;
	}

	FILE *fp = fopen(sFilePath, "w");
	if(fp != NULL)
	{
		size_t writtenObjects = fwrite(theNextID, theIDLen, 1, fp);
		if(writtenObjects != 1)
		{
			fprintf(stderr, "an error occurred while writing next command id to file: %s\n", sFilePath);
			result = -1;
		}
		fclose(fp);
	}

    return result;
}
