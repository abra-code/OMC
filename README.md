# OMC
## OnMyCommand

OnMyCommand has been available for macOS for over 15 years. Some historical information and a lot of outdated documentation is available at:
http://www.abracode.com/free/cmworkshop/on_my_command.html

OnMyCommand is an engine to execute command line tools and shell scripts - but not by typing in some command line interface: the idea is to create GUI access points to the rich underlying Unix foundation of macOS.  
If the name of the engine may seem a bit strange, it is not random: it tries to convey the ease of accessibility to the command line environment.  
OMC started life as a contextual menu plug-in allowing users to add menu items to execute custom mini scripts by editing the preference plist. This functionality is still available but as Apple gradually made contextual menu plug-ins obsolete, the usage has decreased. With recent macOS versions you need to use a special host app to load CM plug-ins. For more information see Shortcuts.app: http://www.abracode.com/free/cmworkshop/shortcuts.html

Most of the OMC development effort nowadays is directed towards building apps based on Abracode.framework and OMCApplet.app.  
In contemporary terms you could describe OMC as low code or no code macOS app development environment.  
Example OMC applets using the latest features are:
\
https://github.com/abra-code/FindApp
\
https://github.com/abra-code/DeltaApp
\
https://github.com/abra-code/XattrApp
\
https://github.com/abra-code/AIChatApp
\

## Key Design Ideas
### (Basic concepts under 5 minutes)

### **UI Entry Points**
OMC engine handles the UI entry points. It could be a contextual menu item, could be an app start, a menu item in your applet, could be a button in a dialog. You provide a handler script (or command, if you will), which will be called by the engine when user initiates some action. Commands have assigned IDs (just unique strings) and you make the connection between UI element and the handler by command ID. In most cases the command ID can be assigned to a control or menu item in nibs/xibs in Xcode via "User Defined Runtime Attributes". That way a click on button can invoke an action in your script and say `echo "Hello World"`.

### **Environment Variables**
When your command handler is executed, the engine provides the relevant context information as environment variables, which your script can access and act upon.

It started with "touch" tool in the first revision of OnMyCommandCM contextual menu plug-in. How can we invoke the tool "touch" on selected file to bump its modification date?  
Well, the engine is providing the context information, in this case a path to the selected file:  
`touch "$OMC_OBJ_PATH"`

Similar with selected or clipboard text:  
`echo "$OMC_OBJ_TEXT"`

The same context information is available in applets, for example `$OMC_OBJ_PATH` holds the path for a file dropped on the app.

At some point OMC added support for nib-based windows with controls and your command handler can access control values from the parent dialog with:  
`$OMC_NIB_DIALOG_CONTROL_N_VALUE`  
or:  
`$OMC_NIB_TABLE_NNN_COLUMN_MMM_VALUE`  
or the newest:  
`$OMC_NIB_WEBVIEW_XXX_ELEMENT_YYY_VALUE`

Several other contextual or static environment variables are exported by the engine and the easiest way to find out what is available is to list them all in your script with:  
`env | grep "OMC" | sort`

### **Out Of Process**
OMC engine runs your handler scripts in separate child processes. This has several implications:
- you cannot crash the host app - the stability of parent process is unaffected even by misbehaving code,
- the execution is mostly asynchronous (depends on execution mode if you are curious to look into details),
- since it is an out of process execution, the communication back to the host app from your script must be handled in special way. OMC provides two command line tools to facilitate that: `omc_dialog_control` and `omc_next_command`,
- communication with other commands within the same app is limited but information can be shared through files or via private pasteboard. OMC provides a `pasteboard` tool to help with this.


## Documentation
Ready to learn more? Start here:  

[OnMyCommand (OMC) Command Reference](omc_command_reference.md)<br>
[OMC Runtime Context Reference](omc_runtime_context_reference.md)<br>
[OMC Services Reference](omc_services_reference.md)<br>


