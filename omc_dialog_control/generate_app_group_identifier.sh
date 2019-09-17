#!/bin/sh

out_file="$BUILT_PRODUCTS_DIR/generated/AppGroupIdentifier.h"
echo "#pragma once\n" > "$out_file"

if test -z "$DEVELOPMENT_TEAM"; then
	DEVELOPMENT_TEAM="group"
fi

echo "#define GetAppGroupIdentifier() \"$DEVELOPMENT_TEAM\"\n" >> "$out_file"

