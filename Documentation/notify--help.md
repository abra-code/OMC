./notify --help

```
NAME
	notify - send user notification

SYNOPSIS
	notify [options] "Notification Message"

DESCRIPTION
	notify sends user notification
OPTIONS
	-h,--help
		Print this help and exit
	-t,--title
		Notification title string. "notify" is default if not specified
	-s,--subtitle
		Subtitle string
	-d,--sound
		Sound name. Use "default" or any system sound name:
		Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink
	-b,--button
		Button string
	-u,--user-info
		User info string
EXAMPLES
	notify -t "My Title" -s "My Subtitle" "My Notification"
```
