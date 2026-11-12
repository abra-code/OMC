#!/bin/bash
# AppletBuilder.app.will.launch - Set defaults for code editing
#
# AppKit's own text settings for AppletBuilder's text views, so they stay in the
# real preferences domain AppKit reads (/usr/bin/defaults, not the engine's
# defaults tool, which keeps them in a JSON file under a test runner). Linux's
# text views have no such settings.

case "${OSTYPE:-}" in
    darwin*)
        /usr/bin/defaults write com.abracode.applet-builder NSAutomaticQuoteSubstitutionEnabled -bool false
        /usr/bin/defaults write com.abracode.applet-builder NSAutomaticDashSubstitutionEnabled -bool false
        /usr/bin/defaults write com.abracode.applet-builder NSAutomaticTextReplacementEnabled -bool false
        /usr/bin/defaults write com.abracode.applet-builder SmartInsertDelete -bool false
        ;;
esac
