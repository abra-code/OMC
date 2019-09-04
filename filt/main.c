#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <regex.h>

void print_help(void);

typedef struct str_replace
{
	struct str_replace *next;
	char *str;
	size_t sub_index;//subexpression indexes start at 1
} str_replace;

str_replace *parse_replace_string(const char *inReplaceStr)
{
	str_replace *list_head = NULL;
	str_replace *curr_chunk = NULL;
	size_t curr_offset = 0;
	size_t curr_str_offset = 0;
	size_t curr_str_len = 0;
	while( inReplaceStr[curr_offset] != 0 )
	{
		switch(inReplaceStr[curr_offset])
		{
			case '\\':
			{
				if(curr_str_len > 0)
				{//flush previous chunk if any string accumulated
					str_replace *prev_chunk = curr_chunk;
					curr_chunk = (str_replace *)calloc(1, sizeof(str_replace) );
					if(prev_chunk != NULL)
						prev_chunk->next = curr_chunk;
					else
						list_head = curr_chunk;

					curr_chunk->str = malloc(curr_str_len+1);
					memcpy(curr_chunk->str, inReplaceStr+curr_str_offset, curr_str_len);
					curr_chunk->str[curr_str_len] = 0;

					curr_str_len = 0;
					curr_str_offset = curr_offset;
				}
				
				
				curr_offset++;
				char currChar = inReplaceStr[curr_offset];
				//see what is following the \ escape
				if( (currChar >= '0') && (currChar <= '9') )
				{
					str_replace *prev_chunk = curr_chunk;
					curr_chunk = (str_replace *)calloc(1, sizeof(str_replace) );
					if(prev_chunk != NULL)
						prev_chunk->next = curr_chunk;
					else
						list_head = curr_chunk;

					curr_chunk->sub_index = currChar - '0';

					curr_str_len = 0;
					curr_str_offset = curr_offset+1;
				}
				else if( (currChar == 't') || (currChar == 'n') || (currChar == 'r') || (currChar == '\\') )
				{
					switch(currChar)
					{
						case 't':
							currChar = '\t';
						break;
						
						case 'n':
							currChar = '\n';
						break;

						case 'r':
							currChar = '\r';
						break;
						
						case '\\':
							currChar = '\\';
						break;
					}
					
					str_replace *prev_chunk = curr_chunk;
					curr_chunk = (str_replace *)calloc(1, sizeof(str_replace) );
					if(prev_chunk != NULL)
						prev_chunk->next = curr_chunk;
					else
						list_head = curr_chunk;

					curr_chunk->str = malloc(2);
					curr_chunk->str[0] = currChar;
					curr_chunk->str[1] = 0;
					
					curr_str_len = 0;
					curr_str_offset = curr_offset+1;
				}
				else if( currChar == 0)
				{//the end of the string, put the stray \ in the last chunk
					str_replace *prev_chunk = curr_chunk;
					curr_chunk = (str_replace *)calloc(1, sizeof(str_replace) );
					if(prev_chunk != NULL)
						prev_chunk->next = curr_chunk;
					else
						list_head = curr_chunk;

					curr_chunk->str = malloc(2);
					curr_chunk->str[0] = '\\';
					curr_chunk->str[1] = 0;
					return list_head;
				}
				else
				{//not a valid escape - just add to new accumulated string
					curr_str_len += 2;
				}

			}
			break;
			
			default:
				curr_str_len++;//one more character to accumulate
			break;
		}
		
		curr_offset++;
	}

	if(curr_str_len > 0)
	{//fill the last chunk
		str_replace *prev_chunk = curr_chunk;
		curr_chunk = (str_replace *)calloc(1, sizeof(str_replace) );
		if(prev_chunk != NULL)
			prev_chunk->next = curr_chunk;
		else
			list_head = curr_chunk;

		curr_chunk->str = malloc(curr_str_len+1);
		memcpy(curr_chunk->str, inReplaceStr+curr_str_offset, curr_str_len);
		curr_chunk->str[curr_str_len] = 0;
	}

	return list_head;
}

int main (int argc, const char * argv[])
{
	regex_t regularExpression;
	memset( &regularExpression, 0, sizeof(regularExpression) );
	int regFlags = REG_EXTENDED;

	int currArgIndex = 1;
	
	if( (argc > currArgIndex) &&
		( (strncmp("-h", argv[currArgIndex], 3) == 0) ||
		  (strncmp("--help", argv[currArgIndex], 7) == 0) ) )
	{
		print_help();
		return 0;
	}
	
	if( (argc > currArgIndex) &&
		( (strncmp("-i", argv[currArgIndex], 3) == 0) ||
		  (strncmp("--ignore-case", argv[currArgIndex], 14) == 0) ) )
	{
		regFlags |= REG_ICASE;
		currArgIndex++;
	}

	int printNotMatching = 0;
	if( (argc > currArgIndex) &&
		( (strncmp("-n", argv[currArgIndex], 3) == 0) ||
		  (strncmp("--not-matching", argv[currArgIndex], 15) == 0) ) )
	{
		printNotMatching = 1;
		currArgIndex++;
	}
	
	size_t maxMatchCount = 0;
	regmatch_t *matches = NULL;

	if( argc > currArgIndex )//match string
	{
		const char *matchString = argv[currArgIndex];
		currArgIndex++;
		int regExprErr = regcomp( &(regularExpression), matchString, regFlags );
		if(regExprErr != 0)
		{
			char *err_str = malloc(1024);
			(void)regerror(regExprErr, &regularExpression, err_str, 1024);
			fprintf(stderr, "-filt: regular expression error: %s\n", err_str);
			return regExprErr;
		}
		maxMatchCount = regularExpression.re_nsub + 1;//+1 for the whole match
		matches = calloc( maxMatchCount, sizeof(regmatch_t) );
	}

	str_replace *replaces = NULL;
	//we ignore replace string if we are asked to print not matching lines
	if( (printNotMatching == 0) && argc > currArgIndex )
	{//replace string
		const char *replaceString = argv[currArgIndex];
		currArgIndex++;
		replaces = parse_replace_string(replaceString);
	}

	char *inputLine = NULL;
	size_t lineLen = 0;
	do
	{
		lineLen = 0;
		inputLine = fgetln(stdin, &lineLen);//string not terminated with null char
		if(inputLine != NULL)
		{
			if(matches != NULL)
			{
				//the use of REG_STARTEND allows us to pass non-null terminated string
				//so we don't need to alloacate a new buffer and copy the line
				matches[0].rm_so = 0;
				//don't include newline char
				matches[0].rm_eo = (inputLine[lineLen-1] == '\n') ? (lineLen-1) : lineLen;
				int matchErr = regexec( &regularExpression, inputLine, maxMatchCount, matches, REG_STARTEND );
				if(matchErr == 0)
				{//it is a match
					if(printNotMatching == 0)
					{
						if(replaces != NULL)
						{
							str_replace *nextReplace = replaces;
							while (nextReplace != NULL)
							{
								if(nextReplace->str != NULL)
								{
									fputs(nextReplace->str, stdout);
								}
								else if( nextReplace->sub_index < maxMatchCount )
								{
									//regex match
									size_t range_start = matches[nextReplace->sub_index].rm_so;
									size_t range_len = matches[nextReplace->sub_index].rm_eo - range_start;
									fwrite(inputLine+range_start, range_len, 1, stdout);
								}
								else
								{
									//silently output nothing if sub index out of range
									;//fprintf(stderr, "-filt: internal consitency error. report a bug\n");
								}
								nextReplace = nextReplace->next;
							}
							
							if(inputLine[lineLen-1] == '\n')//it had a newline - append one
								fwrite("\n", 1, 1, stdout);
						}
						else //mirror input line
						{
							fwrite(inputLine, lineLen, 1, stdout);
						}

						//DEBUG:
						//for(int i=0; i< maxMatchCount; i++)
						//	fprintf(stderr, "match[%d]:(%d, %d)\n", i, (int)matches[i].rm_so, (int)matches[i].rm_eo);
					}
					//else: output nothing we are asked to print the lines that don't match
				}
				else if(matchErr == REG_NOMATCH)
				{
					if( printNotMatching )
						fwrite(inputLine, lineLen, 1, stdout);
					//else: not a match - skip line output
				}
				else
				{//other error
					char *err_str = malloc(1024);
					(void)regerror(matchErr, &regularExpression, err_str, 1024);
					fprintf(stderr, "%s\n", err_str);
					return matchErr;
				}
			}
			else
			{//just mirror input line
				fwrite(inputLine, lineLen, 1, stdout);
			}
		}
	}
	while (inputLine != NULL);

//don't nother relasing anything - we are dying now
//	if(regExprErr == 0)
//		regfree(&regularExpression);

    return 0;
}


void print_help(void)
{
	fprintf(stdout, "\nNAME\n");
	fprintf(stdout, "\tfilt - lean and fast pipe filter, born out of frustration with sed\n\n");

	fprintf(stdout, "SYNOPSIS\n");
	fprintf(stdout, "\tfilt [options] 'match reg exp' ['replace str']\n\n");

	fprintf(stdout, "DESCRIPTION\n");
	fprintf(stdout, "\tfilt is a pipe filter using regular expressions.\n");
	fprintf(stdout, "\tInput lines matching the regular expression pattern are printed to \n");
	fprintf(stdout, "\toutput, transformed with replace string and taking options into account.\n");
	fprintf(stdout, "\tfilt works in pipe mode only: takes standard input and prints to\n");
	fprintf(stdout, "\tstandard output.\n");
	fprintf(stdout, "\tOnly modern (extended) regular expressions are allowed in match string.\n");
	fprintf(stdout, "\tThe replace string may refer to the whole matched string by \\0 or\n");
	fprintf(stdout, "\tto sub group matches by \\1 thru \\9. Only 9 sub groups are allowed.\n");
	fprintf(stdout, "\tThe replace string may contain white character escape sequences like\n");
	fprintf(stdout, "\t\\t, \\n, \\r, \\\\, which will be evaluated to appropriate characters in\n");
	fprintf(stdout, "\toutput string.\n\n");
	
	fprintf(stdout, "OPTIONS\n");
	fprintf(stdout, "\t-h,--help\n");
	fprintf(stdout, "\t\tPrint this help and exit\n");
	fprintf(stdout, "\t-i,--ignore-case\n");
	fprintf(stdout, "\t\tRegular expression matches are case-insensitive\n");
	fprintf(stdout, "\t-n,--not-matching\n");
	fprintf(stdout, "\t\tOnly lines not matching the regular expression pattern\n");
	fprintf(stdout, "\t\tare copied to the output\n");
	fprintf(stdout, "\t\tWith this option the replace string is ignored\n\n");

	fprintf(stdout, "EXAMPLES\n");
	fprintf(stdout, "\techo \"Hello World\" | filt '(.+) (.+)' 'Goodbye\\t\\2'\n");
	fprintf(stdout, "\t-> Goodbye\tWorld\n\n");
	fprintf(stdout, "\techo \"Hello World\" | filt '(.+) (.+)' '\\1 \\2, \\1!'\n");
	fprintf(stdout, "\t-> Hello World, Hello!\n\n");
	fprintf(stdout, "\techo \"Hello World\" | filt -i '[a-z]+' '\\0'\n");
	fprintf(stdout, "\t-> Hello\n\n");
	fprintf(stdout, "\tprintf \"Hello\\nWorld\\n\" | ./filt -n 'W.+'\n");
	fprintf(stdout, "\t-> Hello\n\n");

	fprintf(stdout, "SEE ALSO\n");
	fprintf(stdout, "\tman re_format, man regex\n\n");
}
