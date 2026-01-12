BUILD_PYTHON_SCRIPT="${PROJECT_DIR}/../../Python-Embedding/build-embedded-python.sh"
if test -f "${BUILD_PYTHON_SCRIPT}"; then
	cd "${PROJECT_DIR}/.."
    /bin/bash "$BUILD_PYTHON_SCRIPT" --output="${BUILT_PRODUCTS_DIR}/Python"
    build_result=$?
    if [ "${build_result}" = 0 ]; then
        echo "Python build succeeded"
        echo "Copying to applets's Contents/Library/Python/..."
        cd "${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}/Contents"
        library_dir="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}/Contents/Library"
        applet_python_dir="${library_dir}/Python"
        if [ -d "${applet_python_dir}" ]; then
        	echo "Removing existing Python in applet's Contents/Library/Python/" 
        	/bin/rm -fR "${applet_python_dir}"
        fi
        /bin/mkdir -p "${library_dir}"
        /usr/bin/ditto --norsrc --noextattr --clone "${BUILT_PRODUCTS_DIR}/Python" "${applet_python_dir}"
    else
        echo "error: Python build failed with result: ${build_result}"
        exit ${build_result}
    fi
else
    echo "warning: The script to build embedded Python not found at: $BUILD_PYTHON_SCRIPT"
    echo "Download code or clone repository from: https://github.com/abra-code/Python-Embedding"
fi
