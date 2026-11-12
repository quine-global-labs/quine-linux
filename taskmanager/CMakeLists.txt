# Builds only libtaskmanager (plasma-workspace's libtaskmanager/, the task
# manager's models) out of plasma-workspace's tree, as KDE's own build does,
# for the Containerfile's taskmanager-builder: PLASMA_SRC is plasma-workspace's
# source at the version the image ships, with startup-feedback.patch applied.
cmake_minimum_required(VERSION 3.16)
project(libtaskmanager-quine LANGUAGES C CXX)

if(NOT PLASMA_SRC OR NOT PLASMA_VERSION)
    message(FATAL_ERROR "Set PLASMA_SRC (plasma-workspace's source) and PLASMA_VERSION")
endif()
# libtaskmanager's own CMakeLists.txt versions the library from these.
set(PROJECT_VERSION "${PLASMA_VERSION}")
string(REPLACE "." ";" VERSION_LIST ${PROJECT_VERSION})
list(GET VERSION_LIST 0 PROJECT_VERSION_MAJOR)

# As plasma-workspace's top-level CMakeLists.txt sets them.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# ECM's Qt-version-dependent modules (ECMQmlModule) pick Qt 6 from this.
set(QT_MAJOR_VERSION 6)
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQtDeclareLoggingCategory)
include(ECMGenerateExportHeader)
include(ECMQmlModule)
include(GenerateExportHeader)
include(CMakePackageConfigHelpers)
include(ECMDeprecationSettings)

find_package(Qt6 CONFIG REQUIRED COMPONENTS Core Gui Quick DBus Concurrent WaylandClient)
find_package(Qt6GuiPrivate CONFIG QUIET)
find_package(KF6 REQUIRED COMPONENTS ItemModels Config I18n KIO JobWidgets Service WindowSystem)
find_package(PlasmaActivities REQUIRED)
find_package(PlasmaWaylandProtocols REQUIRED)
find_package(LibKWorkspace REQUIRED)

ecm_set_disabled_deprecation_versions(QT 5.15.2 KF 5.98.0)
set(BUILD_TESTING OFF)
add_definitions(-DQT_NO_URL_CAST_FROM_STRING)
configure_file(${PLASMA_SRC}/config-X11.h.cmake ${CMAKE_CURRENT_BINARY_DIR}/config-X11.h)
include_directories(${CMAKE_CURRENT_BINARY_DIR})

add_subdirectory(${PLASMA_SRC}/libtaskmanager libtaskmanager)
