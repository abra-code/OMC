#!/bin/bash
# AppletBuilder.uifiles.loaded - Populate UI Files table (nibs + ActionUI JSONs)

source "${OMC_APP_BUNDLE_PATH}/Contents/Resources/Scripts/lib.builder.sh"

project_path=$(load_project_path)
resources_dir="$project_path/Contents/Resources"
lproj_dir="$resources_dir/Base.lproj"

refresh_uifiles_table "$project_path"

# Populate the template picker with element names from Documentation/Elements
elements_dir="${OMC_APP_BUNDLE_PATH}/Contents/Resources/Documentation/Elements"
if [ -d "$elements_dir" ]; then
    # Build JSON array of options with sections
    options='[{"section":"Layout"},{"title":"HStack","tag":"HStack"},{"title":"VStack","tag":"VStack"},{"title":"ZStack","tag":"ZStack"},{"title":"HSplitView","tag":"HSplitView"},{"title":"VSplitView","tag":"VSplitView"},{"title":"Grid","tag":"Grid"},{"title":"LazyHGrid","tag":"LazyHGrid"},{"title":"LazyVGrid","tag":"LazyVGrid"},{"title":"LazyHStack","tag":"LazyHStack"},{"title":"LazyVStack","tag":"LazyVStack"},{"title":"Spacer","tag":"Spacer"},{"title":"Divider","tag":"Divider"},{"title":"GeometryReader","tag":"GeometryReader"},{"title":"Group","tag":"Group"},{"title":"GroupBox","tag":"GroupBox"},{"title":"Section","tag":"Section"},{"title":"Form","tag":"Form"},{"divider":true},{"section":"Controls"},{"title":"Button","tag":"Button"},{"title":"TextField","tag":"TextField"},{"title":"SecureField","tag":"SecureField"},{"title":"TextEditor","tag":"TextEditor"},{"title":"Toggle","tag":"Toggle"},{"title":"Picker","tag":"Picker"},{"title":"Slider","tag":"Slider"},{"title":"DatePicker","tag":"DatePicker"},{"title":"ColorPicker","tag":"ColorPicker"},{"title":"Menu","tag":"Menu"},{"title":"Link","tag":"Link"},{"title":"ShareLink","tag":"ShareLink"},{"divider":true},{"section":"Display"},{"title":"Text","tag":"Text"},{"title":"Label","tag":"Label"},{"title":"LabeledContent","tag":"LabeledContent"},{"title":"Image","tag":"Image"},{"title":"AsyncImage","tag":"AsyncImage"},{"title":"Table","tag":"Table"},{"title":"List","tag":"List"},{"title":"ProgressView","tag":"ProgressView"},{"title":"Gauge","tag":"Gauge"},{"title":"ContentUnavailableView","tag":"ContentUnavailableView"},{"divider":true},{"section":"Navigation"},{"title":"TabView","tag":"TabView"},{"title":"NavigationStack","tag":"NavigationStack"},{"title":"NavigationSplitView","tag":"NavigationSplitView"},{"title":"NavigationLink","tag":"NavigationLink"},{"title":"DisclosureGroup","tag":"DisclosureGroup"},{"divider":true},{"section":"Media"},{"title":"WebView","tag":"WebView"},{"title":"VideoPlayer","tag":"VideoPlayer"},{"title":"Map","tag":"Map"},{"title":"Canvas","tag":"Canvas"},{"divider":true},{"section":"Other"},{"title":"View","tag":"View"},{"title":"EmptyView","tag":"EmptyView"},{"title":"LoadableView","tag":"LoadableView"},{"title":"ScrollView","tag":"ScrollView"},{"title":"ScrollViewReader","tag":"ScrollViewReader"},{"title":"KeyframeAnimator","tag":"KeyframeAnimator"},{"title":"PhaseAnimator","tag":"PhaseAnimator"},{"title":"CommandMenu","tag":"CommandMenu"},{"title":"CommandGroup","tag":"CommandGroup"}]'
    "$dialog_tool" "$window_uuid" "$UI_TEMPLATE_PICKER_ID" omc_set_property options "$options"
fi
