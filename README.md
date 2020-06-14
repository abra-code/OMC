# OMC
*OnMyCommand*

OnMyCommand has been available for macOS for over 15 years. See more information at:
http://www.abracode.com/free/cmworkshop/on_my_command.html

I would like to open the source code, remove legacy cruft & clean it up to make it easier to maintain.

## Temporary Open Source Release Installation Instructions
Until the process of open-sourcing all of OnMyCommand is complete, installing the latest open source release relies on some parts of the older closed source releases.
* Download and install the old OnMyCommand version 3.2 from <a href="http://www.abracode.com/free/cmworkshop/on_my_command.html">http://www.abracode.com/free/cmworkshop/on_my_command.html</a>.
* Optionally also download and install <a href="http://www.abracode.com/free/cmworkshop/shortcuts.html">Shortcuts</a> and/or <a href="http://www.abracode.com/free/cmworkshop/droplet.html">CommandDroplet</a>.
* Download the latest open source binary release from <a href="https://github.com/abra-code/OMC/releases">https://github.com/abra-code/OMC/releases</a>.
* Expand the zip file.
* This will create a partial file hierarchy headed by `Products`. Manually copy each file into the position indicated by its place in this hierarchy:
    * `Products/Library/Contextual Menu Items/OnMyCommandCM.plugin` to `/Library/Contextual Menu Items/`
    * `Products/Library/Frameworks/Abracode.framework` to `/Library/Frameworks/`
    * `Products/Library/Services/OMCService.service` to `~/Library/Services/`
    * `Products/Applications/OMCApplet.app` to `/Applications/`
    
    
## User-Visible Changes
* OnMyCommand’s `Services` menu item is now titled simply “Shortcut Items…”
* Items in the “In On My Command” location in OMCEdit are now merged into the “Top Level” location.