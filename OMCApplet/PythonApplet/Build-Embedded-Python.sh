# Sourced by the "Build Embedded Python" phase of the OMCPythonApplet target.
# The build options are set here, not passed in by the phase.

PYTHON_EMBEDDING_DIR="${PROJECT_DIR}/../../Python-Embedding"
PYTHON_EMBEDDING_URL="https://github.com/abra-code/Python-Embedding.git"
BUILD_PYTHON_SCRIPT="${PYTHON_EMBEDDING_DIR}/build-embedded-python.sh"

# No checkout next to OMC: fetch one there, where update_appletbuilder.sh and
# make-release.sh look for it too. A directory that exists without the script
# is left alone - it is not ours to replace.
if [ ! -e "${PYTHON_EMBEDDING_DIR}" ]; then
    echo "Python-Embedding not found at: ${PYTHON_EMBEDDING_DIR}"
    echo "Cloning ${PYTHON_EMBEDDING_URL}..."
    /usr/bin/git clone --quiet "${PYTHON_EMBEDDING_URL}" "${PYTHON_EMBEDDING_DIR}"
    clone_result=$?
    if [ "${clone_result}" != 0 ]; then
        echo "warning: cloning Python-Embedding failed with result: ${clone_result}"
    fi
fi

if test -f "${BUILD_PYTHON_SCRIPT}"; then
	cd "${PROJECT_DIR}/.."
    /bin/bash "$BUILD_PYTHON_SCRIPT" --output="${BUILT_PRODUCTS_DIR}/Python" --lzma-version=auto
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
