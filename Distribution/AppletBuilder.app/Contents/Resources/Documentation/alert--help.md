./alert --help

```
NAME
	alert - display GUI alert dialog

SYNOPSIS
	alert [options] "Alert Message"

DESCRIPTION
	alert presents a dialog for user to respond
	It waits until one of the buttons is hit or it times out

OPTIONS
	-h,--help
		Print this help and exit
	-t,--title
		Alert title string. "Alert" is default if not specified
	-b0,--ok
		Default button string. "OK" is default if not specified
	-b1,--cancel
		Cancel button string. Cancel button is not shown if this string
		is not specified
	-b2,--other
		Other button string. Other button is not shown if this string
		is not specified
	-o,--timeout
		Timeout in seconds. The dialog will be dismissed after
		specified number of seconds.
		By default the dialog never times out (timeout = 0)
	-l,--level
		Specify alert level. Each level uses different icon.
		Allowed values are:
		plain (default if not specified)
		stop
		note
		caution

RETURN VALUES
The alert utility exits with one of the following values:
	 0 - user pressed OK button
	 1 - user pressed Cancel button
	 2 - user pressed Other button
	 3 - dialog timed out
	-1 - an error occurred

EXAMPLES
	alert --level caution --timeout 10 --title "Warning" --ok "Continue" --cancel "Cancel" "Do you wish to continue?"
	result=$?
	if test $result -ne 0; then echo "Cancelled"; exit 1; fi;
```
