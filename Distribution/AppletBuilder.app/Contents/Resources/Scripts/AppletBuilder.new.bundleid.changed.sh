#!/bin/bash
# AppletBuilder.new.bundleid.changed - Remember bundle ID prefix when user edits it

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

bundle_id="${OMC_ACTIONUI_VIEW_204_VALUE}"

if [ -n "$bundle_id" ]; then
    save_bundle_id_prefix "$bundle_id"
fi
