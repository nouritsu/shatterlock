# Shatterlock.Keyboard: a small QML module that reads the compositor's keyboard lock state (Caps
# Lock) for the lock screen. Installs to lib/qt-6/qml; add that to QML_IMPORT_PATH.
cmake_minimum_required(VERSION 3.21)
project(shatterlock-keyboard LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Gui Qml)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(XKBCOMMON REQUIRED IMPORTED_TARGET xkbcommon)

qt_standard_project_setup(REQUIRES 6.5)
set(QT_QML_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml)

qt_add_qml_module(shatterlock_keyboard
    URI Shatterlock.Keyboard
    VERSION 1.0
    PLUGIN_TARGET shatterlock_keyboard
    SOURCES keyboardstate.h keyboardstate.cpp
)

target_link_libraries(shatterlock_keyboard PRIVATE
    Qt6::Gui
    Qt6::Qml
    PkgConfig::WAYLAND
    PkgConfig::XKBCOMMON
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/qml/ DESTINATION lib/qt-6/qml)
