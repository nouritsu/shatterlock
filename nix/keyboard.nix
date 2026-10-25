# Shatterlock.Keyboard (plugin/): the QML module the lock screen reads Caps Lock from. Built
# against the same Qt as the Quickshell that loads it.
{
  lib,
  stdenv,
  cmake,
  pkg-config,
  qt6,
  wayland,
  libxkbcommon,
}:
stdenv.mkDerivation {
  pname = "shatterlock-keyboard";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../plugin;
    fileset = ../plugin;
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qtdeclarative
    wayland
    libxkbcommon
  ];

  # A library loaded by Quickshell, not an app.
  dontWrapQtApps = true;

  meta = {
    description = "QML module reading the compositor's Caps Lock state, for shatterlock";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
