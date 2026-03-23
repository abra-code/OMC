./filt --help

```
NAME
	filt - lean and fast pipe filter, born out of frustration with sed

SYNOPSIS
	filt [options] 'match reg exp' ['replace str']

DESCRIPTION
	filt is a pipe filter using regular expressions.
	Input lines matching the regular expression pattern are printed to 
	output, transformed with replace string and taking options into account.
	filt works in pipe mode only: takes standard input and prints to
	standard output.
	Only modern (extended) regular expressions are allowed in match string.
	The replace string may refer to the whole matched string by \0 or
	to sub group matches by \1 thru \9. Only 9 sub groups are allowed.
	The replace string may contain white character escape sequences like
	\t, \n, \r, \\, which will be evaluated to appropriate characters in
	output string.

OPTIONS
	-h,--help
		Print this help and exit
	-i,--ignore-case
		Regular expression matches are case-insensitive
	-n,--not-matching
		Only lines not matching the regular expression pattern
		are copied to the output
		With this option the replace string is ignored

EXAMPLES
	echo "Hello World" | filt '(.+) (.+)' 'Goodbye\t\2'
	-> Goodbye	World

	echo "Hello World" | filt '(.+) (.+)' '\1 \2, \1!'
	-> Hello World, Hello!

	echo "Hello World" | filt -i '[a-z]+' '\0'
	-> Hello

	printf "Hello\nWorld\n" | ./filt -n 'W.+'
	-> Hello

SEE ALSO
	man re_format, man regex

```
