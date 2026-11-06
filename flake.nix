{
  description = "Ghostel, an Emacs terminal emulator powered by libghostty";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];

      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            }
          )
        );
    in
    {
      # Inject ghostel into every Emacs package set so it is available
      # regardless of which Emacs variant the consumer uses
      # (emacsWithPackages, home-manager's programs.emacs.extraPackages, ...).
      # Composes with other emacsPackagesFor overlays such as emacs-overlay.
      #
      # Injecting via the manualPackages *argument* (rather than a plain
      # overrideScope attr) matters: emacs-overlay's package overlay ends with
      # `esuper.override { ... }`, which rebuilds the scope through nixpkgs'
      # makeOverridable — stored args survive that rebuild, overrideScope
      # extensions do not (the rebuilt set shadows them with nixpkgs' own
      # ghostel). nix-doom-emacs-unstraightened triggers exactly that
      # rebuild. manualPackages is also merged into the scope after the MELPA
      # sets, so this keeps winning over MELPA's ghostel. Keeping the
      # `esuper.override` call *inside* an overrideScope extension preserves
      # makeScope's wrapper attrs (overrideScope, callPackage) for later
      # overlays.
      overlays.default = final: prev: {
        emacsPackagesFor =
          emacs:
          (prev.emacsPackagesFor emacs).overrideScope (
            eself: esuper:
            esuper.override (args: {
              # args is { } on a pristine scope, hence the esuper fallback.
              manualPackages = (args.manualPackages or esuper.manualPackages) // {
                ghostel = eself.callPackage ./nix/package.nix { };
              };
            })
          );
      };

      packages = forAllSystems (
        pkgs:
        let
          inherit (pkgs.emacsPackages) ghostel;
        in
        {
          inherit ghostel;
          default = ghostel;
          # The bare native module (ghostel-module.so/.dylib), useful for
          # debugging the Zig build without pulling in melpaBuild.
          ghostel-module = ghostel.module;
        }
      );

      checks = forAllSystems (
        pkgs:
        let
          inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) ghostel;
        in
        {
          inherit ghostel;
          # Guard the manualPackages arg injection: simulate the scope
          # rebuild unstraightened/emacs-overlay perform and fail unless this
          # flake's ghostel survives it. nixpkgs ships its own ghostel, so a
          # regression shows up as a different derivation rather than a
          # missing attribute; the derivations are compared rather than
          # versions because nixpkgs may package the same version.
          scope-rebuild-survival =
            let
              survived =
                ((pkgs.emacsPackagesFor pkgs.emacs).overrideScope (eself: esuper: esuper.override { })).ghostel
                  or null;
              got = if survived == null then "<missing>" else survived.drvPath;
            in
            assert lib.assertMsg (
              got == ghostel.drvPath
            ) "ghostel dropped by esuper.override scope rebuild: got ${got}, expected ${ghostel.drvPath}";
            pkgs.runCommand "ghostel-scope-rebuild-survival" { } "touch $out";
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
