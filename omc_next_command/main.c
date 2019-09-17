#include <unistd.h>
#include <sys/stat.h>
#include <stdio.h>
#include <string.h>

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

	if( access("/tmp/OMC", F_OK|R_OK|W_OK|X_OK) != 0 )
	{
		mkdir("/tmp/OMC", S_IRWXU|S_IRWXG|S_IRWXO);
		//for some reason the mkdir does not set the writable flag for group and others so do it again with chmod
		chmod("/tmp/OMC", S_IRWXU|S_IRWXG|S_IRWXO);
	}

	snprintf(sFilePath, sizeof(sFilePath), "/tmp/OMC/%s.id", argv[1]);
	
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
