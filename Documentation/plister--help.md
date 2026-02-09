./pasteboard --help

```
Usage: plister command command_params path/to/plist/file plist/property/pseudopath
Available commands: get, set, remove|delete, add|append, insert, find, findall, iterate
"insert" command is for dict or array and must be followed by a key or index respectively
"set" command is for replacing existing value with new value
"add"|"append" command is for array only
"find", "findall" and "iterate" commands are for containers only (dict or array)
 "iterate" syntax: plister iterate [path/to/file.plist] /path/to/container command command_params subpath/to/item

Available params for "get": type, key, keys, value, string, count
Available parameter types for "find" and "findall": string, integer, real, bool
Available parameter types for "set", "add", "insert": string, integer, real, bool, date, data, dict, array, copy
Parameter types: string, integer, real, bool, date, data must be followed by an appropriate value
"data" must be followed by Base64 encoded string
"dict" and "array" are used for creating new empty containers and must not be followed any value
"copy" is a special directive which must be followed by source/file/path source/property/pseudopath

"find" and "findall" commands may use a sub-item pseudopath as the last parameter
to specify a container item-relative path which points to something inside that item for matching:
plister find string "Item" file.plist /path/to/container subpath/to/item
It is needed because item in searched container may be a container itself and we need a simple type as a match criteria.
When searching array, found item index is returned, for dictionary: found item key is returned
"find" returns only the first match while "findall" returns all matches. If no matching items are found, empty string is returned.

Examples:
Start by creating a new plist file with dictionary as a root container:
plister set dict example.plist /
plister insert "VERSION" integer 1 example.plist /
plister get value example.plist /VERSION
plister set integer 2 example.plist /VERSION
plister insert "NewArray" array example.plist /
plister add integer 10 example.plist /NewArray
plister append integer 20 example.plist /NewArray
plister get count example.plist /NewArray
plister get type example.plist /NewArray/0
plister get value example.plist /NewArray/1
plister remove example.plist /NewArray/1
plister insert "NewDict" dict example.plist /
plister insert "New Key" string "New Value" example.plist /NewDict
plister get keys example.plist /NewDict
Now create new.plist and copy "NewArray" from example.plist:
plister set dict new.plist /
plister insert "DuplicateArray" copy example.plist /NewArray new.plist /

Find a command named "Touch File" in COMMAND_LIST array in OMC plist:
plister find string "Touch File" Command.plist /COMMAND_LIST /NAME

plister iterate example.plist /NewArray get string /

```
