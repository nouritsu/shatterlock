{
  description = "Shatterlock: tear the screen open into a rift session menu (niri + Quickshell)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

    devTools = pkgs: [
      pkgs.quickshell
      pkgs.qt6.qtshadertools # qsb
      pkgs.qt6.qtdeclarative # qmllint, qmlls, qmlformat
      pkgs.material-symbols
      pkgs.jq
    ];

    iconFontHook = pkgs: ''
      export SHATTERLOCK_ICON_FONT="$(find ${pkgs.material-symbols}/share/fonts -iname 'MaterialSymbolsRounded*' | head -n1)"
    '';
  in {
    packages = forAllSystems (pkgs: {
      default = pkgs.callPackage ./nix/package.nix {};
    });

    # The package build compiles every built-in shader; this also compiles the examples.
    checks = forAllSystems (pkgs: {
      package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      examples = pkgs.runCommand "shatterlock-examples" {nativeBuildInputs = [pkgs.qt6.qtshadertools];} ''
        cp -r ${./scripts} scripts
        mkdir -p src/shaders && cp ${./src/shaders/prelude.glsl} src/shaders/prelude.glsl
        chmod -R u+w scripts && patchShebangs scripts
        for f in ${./examples/shaders}/*.frag; do
          ./scripts/compile-shader "$f" "$out"
        done
      '';
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = devTools pkgs;
        shellHook =
          iconFontHook pkgs
          + ''
            export SHATTERLOCK_DEV=1
          '';
      };
    });

    # `nix run .#dev` — build shaders and run the working tree's config in the foreground.
    apps = forAllSystems (pkgs: {
      dev = {
        type = "app";
        program = toString (
          pkgs.writeShellScript "shatterlock-dev" (
            ''
              export PATH=${pkgs.lib.makeBinPath (devTools pkgs)}:$PATH
            ''
            + iconFontHook pkgs
            + ''
              export SHATTERLOCK_DEV=1
              export QSG_RENDER_LOOP="''${QSG_RENDER_LOOP:-threaded}"
              ./scripts/build-shaders
              exec quickshell -p "$PWD/src" "$@"
            ''
          )
        );
      };
    });

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
