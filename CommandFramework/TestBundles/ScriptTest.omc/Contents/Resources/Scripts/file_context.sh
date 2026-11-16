#!/bin/bash
# Test script that uses OMC context variables
if [ -n "${OMC_OBJ_PATH}" ]; then
    echo "Processing file: ${OMC_OBJ_PATH}"
    echo "File name: ${OMC_OBJ_NAME}"
    echo "Parent dir: ${OMC_OBJ_PARENT_PATH}"
    ls -lh "${OMC_OBJ_PATH}"
else
    echo "No file context provided"
    exit 1
fi
exit 0
