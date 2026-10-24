{
  description = "Shatterlock: tear the screen open into a rift session menu (niri + Quickshell)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Only for the niri patch: building the patched niri and checking that it still applies.
    niri = {
      url = "github:niri-wm/niri";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    niri,
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

    # Live halves: niri's `hide-from-own-capture` layer rule (docs/niri.md). The docs half of the
    # series (0002) is for upstream; niri's own package leaves docs/ out of its source.
    niriPatches = [./nix/niri/0001-Add-hide-from-own-capture-layer-rule.patch];

    iconFontHook = pkgs: ''
      export SHATTERLOCK_ICON_FONT="$(find ${pkgs.material-symbols}/share/fonts -iname 'MaterialSymbolsRounded*' | head -n1)"
    '';
  in {
    packages = forAllSystems (pkgs: {
      default = pkgs.callPackage ./nix/package.nix {};
      # niri with the patch, from this flake's niri input (for testing it nested).
      niri = niri.packages.${pkgs.stdenv.hostPlatform.system}.niri.overrideAttrs (old: {
        patches = (old.patches or []) ++ niriPatches;
        doCheck = false;
      });
    });

    # The package build compiles every built-in shader; this also compiles the examples.
    checks = forAllSystems (pkgs: {
      # Both patches still apply to the pinned niri.
      niri-patches = pkgs.runCommand "shatterlock-niri-patches" {} ''
        cp -r ${niri} niri && chmod -R u+w niri && cd niri
        for p in ${./nix/niri}/*.patch; do
          patch -p1 --batch < "$p"
        done
        touch $out
      '';
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

    # Adds the patch to whatever niri the package set has, e.g. after niri's own overlay.
    overlays.niri = _: prev: {
      niri = prev.niri.overrideAttrs (old: {
        patches = (old.patches or []) ++ niriPatches;
      });
    };

    formatter = forAllSystems (pkgs: pkgs.alejandra);
  };
}
