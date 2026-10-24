{
  lib,
  stdenvNoCC,
  makeWrapper,
  quickshell,
  qt6,
  material-symbols,
  netcat-openbsd,
  coreutils,
  gnused,
  glib,
  procps,
  formats,
  # Baked-in configuration, layered between the built-in defaults and
  # ~/.config/shatterlock/config.json. Use `.override { settings = { ... }; }`; custom shaders
  # can be given as store paths, e.g. fx.background = "${./aurora.frag}".
  settings ? {},
}: let
  settingsFile = (formats.json {}).generate "shatterlock-settings.json" settings;
in
stdenvNoCC.mkDerivation {
  pname = "shatterlock";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../bin
      ../config
      ../docs
      ../examples
      ../scripts
      ../src
      ../LICENSE
    ];
  };

  # Quickshell comes wrapped already; Qt is only here for qsb at build time.
  dontWrapQtApps = true;

  nativeBuildInputs = [
    makeWrapper
    qt6.qtshadertools
  ];

  buildPhase = ''
    runHook preBuild
    patchShebangs bin scripts
    ./scripts/build-shaders
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/shatterlock $out/bin
    cp -r bin config docs examples scripts src LICENSE $out/share/shatterlock/
    makeWrapper $out/share/shatterlock/bin/shatterlock $out/bin/shatterlock \
      --prefix PATH : ${
      lib.makeBinPath [
        quickshell
        qt6.qtshadertools
        netcat-openbsd
        coreutils
        gnused
        glib # gdbus, to follow logind's Lock and PrepareForSleep
        procps # pgrep, to retire a daemon from an older build
      ]
    } \
      --set-default SHATTERLOCK_ICON_FONT "$(find ${material-symbols}/share/fonts -iname 'MaterialSymbolsRounded*' | head -n1)" \
      ${lib.optionalString (settings != {}) "--set SHATTERLOCK_SETTINGS ${settingsFile}"}
    runHook postInstall
  '';

  meta = {
    description = "Tear the screen open into a rift session menu (niri + Quickshell)";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "shatterlock";
  };
}
