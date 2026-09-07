#!/bin/bash
# AppletBuilder.thin.python.changed - keep the thinning group coherent.
#
# Fires from the Write Thinning Plan and Apply Plan checkboxes - through their
# actionID, which is the property a Toggle reads on a change. (Slider, TextField,
# DatePicker and others fire valueChangeActionID; a Toggle does not, and ActionUI
# accepts the property on any view, so wiring one that way fires nothing at all.)
#
# Two rules, both about not letting the pane offer something it cannot do:
#
#   Dry Run previews a removal, so it follows Apply Plan. It is also cleared on
#   the way down - a Dry Run left ticked under a disabled box would come back the
#   moment Apply was ticked again, turning a real run into a preview without
#   anyone asking for one.
#
#   With neither box ticked there is no action for the button to take, so it goes
#   dead. The handler still refuses that combination if it is somehow reached;
#   this is what keeps the user from having to find out by clicking.

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.common.sh"

thin_apply="$OMC_ACTIONUI_VIEW_414_VALUE"    # BUILD_THIN_APPLY_ID

# Clearing the box, which only this handler does - the end of a run restores the
# rules but never changes what is ticked. "false", not 0: setElementValueFromString
# takes only "true"/"false" for a Bool view and logs a warning for anything else,
# so a 0 here would leave Dry Run ticked underneath its own disabled state - the
# exact thing this clear exists to prevent.
if ! is_on "$thin_apply"; then
    set_value "$BUILD_THIN_DRY_RUN_ID" false
fi

# The two enable rules live in ab_thin_boxes_release, because the end of a run
# has to restore the same two - and a second copy of them here is a second copy
# to get wrong.
ab_thin_boxes_release
