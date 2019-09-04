#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>

void print_help(void);

int main (int argc, const char * argv[])
{
	CFTimeInterval timeout = 0.0; 
	CFOptionFlags optionFlags = kCFUserNotificationPlainAlertLevel;
	CFOptionFlags responseFlags = 0;
	CFStringRef alertTitle = CFSTR("Alert");
	CFStringRef alertMessage = CFSTR("");
	CFStringRef defaultButtonTitle = CFSTR("OK");
	CFStringRef alternateButtonTitle = NULL;//CFSTR("Cancel");
	CFStringRef otherButtonTitle = NULL;//CFSTR("Other");

	int paramIndex = 1;
	int messageStrIndex = argc-1;//the last one is supposed to be the message string, so check params first
	const char *param;
	
	if( (argc == 1) || ((argc > 1) && ((strcmp(argv[1], "--help") == 0) || (strcmp(argv[1], "-h") == 0)) ) )
	{
		print_help();
		return -1;
	}

	while(paramIndex < messageStrIndex )//read key+value pairs of params
	{
		param = argv[paramIndex++];
		if( (strcmp(param, "-t") == 0) || (strcmp(param, "--title") == 0) )
		{
			param = argv[paramIndex++];
			alertTitle = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
		}
		else if( (strcmp(param, "-b0") == 0) || (strcmp(param, "--ok") == 0) )
		{
			param = argv[paramIndex++];
			defaultButtonTitle = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
		}
		else if( (strcmp(param, "-b1") == 0) || (strcmp(param, "--cancel") == 0) )
		{
			param = argv[paramIndex++];
			alternateButtonTitle = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
		}
		else if( (strcmp(param, "-b2") == 0) || (strcmp(param, "--other") == 0) )
		{
			param = argv[paramIndex++];
			otherButtonTitle = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
		}
		else if( (strcmp(param, "-o") == 0) || (strcmp(param, "--timeout") == 0) )
		{
			param = argv[paramIndex++];
			timeout = strtod(param, NULL);
		}
		else if( (strcmp(param, "-l") == 0) || (strcmp(param, "--level") == 0) )
		{
			param = argv[paramIndex++];
			if( strcmp(param, "plain") == 0 )
				optionFlags = kCFUserNotificationPlainAlertLevel;
			else if( strcmp(param, "stop") == 0 )
				optionFlags = kCFUserNotificationStopAlertLevel;
			else if( strcmp(param, "note") == 0 )
				optionFlags = kCFUserNotificationNoteAlertLevel;
			else if( strcmp(param, "caution") == 0 )
				optionFlags = kCFUserNotificationCautionAlertLevel;
		}
		else
		{
			fprintf(stderr, "Usage: alert [params] \"Alert Message\"\nType alert --help for more information\n\n");
			return -1;
		}
	}

	if(paramIndex == messageStrIndex)
	{
		param = argv[paramIndex];
		alertMessage = CFStringCreateWithCString(kCFAllocatorDefault, param, kCFStringEncodingUTF8);
	}

	if(alertMessage == NULL)
	{
		fprintf(stderr, "Usage: alert [params] \"Alert Message\"\nType alert --help for more information\n\n");
		return -1;
	}

	/*SInt32 isSuccessfull = */(void)CFUserNotificationDisplayAlert (
										timeout, //timeout
										optionFlags, //CFOptionFlags
										NULL, //iconURL
										NULL, //soundURL
										NULL, //localizationURL
										alertTitle, //alertHeader
										alertMessage,
										defaultButtonTitle, //will produce kCFUserNotificationDefaultResponse
										alternateButtonTitle, //will produce kCFUserNotificationAlternateResponse
										otherButtonTitle, //will produce kCFUserNotificationOtherResponse
										&responseFlags );
	
	//who will give us kCFUserNotificationCancelResponse?

	return (responseFlags & 0x03);//OK button: kCFUserNotificationDefaultResponse = 0

}


void print_help(void)
{
	fprintf(stdout, "\nNAME\n");
	fprintf(stdout, "\talert - display GUI alert dialog\n\n");

	fprintf(stdout, "SYNOPSIS\n");
	fprintf(stdout, "\talert [options] \"Alert Message\"\n\n");

	fprintf(stdout, "DESCRIPTION\n");
	fprintf(stdout, "\talert presents a dialog for user to respond\n");
	fprintf(stdout, "\tIt waits until one of the buttons is hit or it times out\n\n");
	
	fprintf(stdout, "OPTIONS\n");

	fprintf(stdout, "\t-h,--help\n");
	fprintf(stdout, "\t\tPrint this help and exit\n");

	fprintf(stdout, "\t-t,--title\n");
	fprintf(stdout, "\t\tAlert title string. \"Alert\" is default if not specified\n");

	fprintf(stdout, "\t-b0,--ok\n");
	fprintf(stdout, "\t\tDefault button string. \"OK\" is default if not specified\n");

	fprintf(stdout, "\t-b1,--cancel\n");
	fprintf(stdout, "\t\tCancel button string. Cancel button is not shown if this string\n");
	fprintf(stdout, "\t\tis not specified\n");

	fprintf(stdout, "\t-b2,--other\n");
	fprintf(stdout, "\t\tOther button string. Other button is not shown if this string\n");
	fprintf(stdout, "\t\tis not specified\n");

	fprintf(stdout, "\t-o,--timeout\n");
	fprintf(stdout, "\t\tTimeout in seconds. The dialog will be dismissed after\n");
	fprintf(stdout, "\t\tspecified number of seconds.\n");
	fprintf(stdout, "\t\tBy default the dialog never times out (timeout = 0)\n");

	fprintf(stdout, "\t-l,--level\n");
	fprintf(stdout, "\t\tSpecify alert level. Each level uses different icon.\n");
	fprintf(stdout, "\t\tAllowed values are:\n");
	fprintf(stdout, "\t\tplain (default if not specified)\n");
	fprintf(stdout, "\t\tstop\n");
	fprintf(stdout, "\t\tnote\n");
	fprintf(stdout, "\t\tcaution\n\n");

	fprintf(stdout, "RETURN VALUES\n");
	fprintf(stdout, "The alert utility exits with one of the following values:\n");
	fprintf(stdout, "\t 0 - user pressed OK button\n");
	fprintf(stdout, "\t 1 - user pressed Cancel button\n");
	fprintf(stdout, "\t 2 - user pressed Other button\n");
	fprintf(stdout, "\t 3 - dialog timed out\n");
	fprintf(stdout, "\t-1 - an error occurred\n\n");

	fprintf(stdout, "EXAMPLES\n");
	fprintf(stdout, "\talert --level caution --timeout 10 --title \"Warning\" --ok \"Continue\" --cancel \"Cancel\" \"Do you wish to continue?\"\n");
	fprintf(stdout, "\tresult=$?\n");
	fprintf(stdout, "\tif test $result -ne 0; then echo \"Cancelled\"; exit 1; fi;\n");
}

