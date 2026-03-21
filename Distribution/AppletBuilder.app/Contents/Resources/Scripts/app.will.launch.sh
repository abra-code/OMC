#!/bin/bash
# AppletBuilder.app.will.launch - Set defaults for code editing

/usr/bin/defaults write com.abracode.applet-builder NSAutomaticQuoteSubstitutionEnabled -bool false
/usr/bin/defaults write com.abracode.applet-builder NSAutomaticDashSubstitutionEnabled -bool false
/usr/bin/defaults write com.abracode.applet-builder NSAutomaticTextReplacementEnabled -bool false
/usr/bin/defaults write com.abracode.applet-builder SmartInsertDelete -bool false
