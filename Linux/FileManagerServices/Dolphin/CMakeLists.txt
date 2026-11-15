# Linux/FileManagerServices/Dolphin - the Dolphin (KDE Plasma) plug-in for Command applet services
# (command-services-dolphin.so, a KIO 6 file item action plug-in) and its test program.
#
# Needs CMake, a C and a C++ compiler, extra-cmake-modules, Qt 6 (Core, Widgets) and KIO 6
# development files (Debian: qt6-base-dev libkf6kio-dev extra-cmake-modules), and GLib's
# (libglib2.0-dev). Built by build.sh beside it.

cmake_minimum_required(VERSION 3.16)
project(command-services-dolphin C CXX)

find_package(ECM 6.0 REQUIRED NO_MODULE)
list(APPEND CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
include(KDEInstallDirs)

# kcoreaddons_add_plugin makes a static library unless shared ones are asked for (KDE's own
# KDECMakeSettings would set this; it also sets compiler flags this project does not want)
set(BUILD_SHARED_LIBS ON)
# and puts it in <library output folder>/kf6/kfileitemaction: in the build folder, not in /kf6
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/plugins)
set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

find_package(Qt6 REQUIRED COMPONENTS Core Widgets)
find_package(KF6 REQUIRED COMPONENTS KIO CoreAddons)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0 gio-2.0)

set(CORE_FOLDER ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_compile_options(-Wall -Wextra -Werror -Wno-unused-parameter)

kcoreaddons_add_plugin(command-services-dolphin
    SOURCES command-services-dolphin.cpp ${CORE_FOLDER}/command-services-core.c
    INSTALL_NAMESPACE "kf6/kfileitemaction")
target_compile_definitions(command-services-dolphin PRIVATE QT_NO_KEYWORDS)
target_include_directories(command-services-dolphin PRIVATE ${CORE_FOLDER})
target_link_libraries(command-services-dolphin PRIVATE KF6::KIOWidgets KF6::CoreAddons Qt6::Widgets PkgConfig::GLIB)
set_target_properties(command-services-dolphin PROPERTIES PREFIX "" C_VISIBILITY_PRESET hidden CXX_VISIBILITY_PRESET hidden)

# The plug-in loaded as Dolphin loads it (KPluginFactory) and asked for its actions with real
# KFileItems; QT_QPA_PLATFORM=offscreen runs it with no display
add_executable(command-services-dolphin-test command-services-dolphin-test.cpp)
target_compile_definitions(command-services-dolphin-test PRIVATE QT_NO_KEYWORDS)
target_link_libraries(command-services-dolphin-test PRIVATE KF6::KIOWidgets KF6::CoreAddons Qt6::Widgets PkgConfig::GLIB)
