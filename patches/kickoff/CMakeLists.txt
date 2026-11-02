# Builds Kickoff on its own, outside plasma-desktop's tree: the Containerfile's
# kickoff-builder stage puts plasma-desktop's applets/kickoff/ next to this
# file as kickoff/. The rest of plasma-desktop's top-level CMakeLists.txt
# isn't needed for this one applet.
cmake_minimum_required(VERSION 3.16)
project(kickoff)
# ECM's QML helpers otherwise pick their Qt5 variant.
set(QT_MAJOR_VERSION 6)
find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})
find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml)
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
# Plasma's CMake package needs these found first.
find_package(KF6 REQUIRED COMPONENTS Config CoreAddons Package I18n)
find_package(Plasma REQUIRED)
add_subdirectory(kickoff)
