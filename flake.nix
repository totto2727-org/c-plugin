{
  description = "Haskell c-plugin skill manager using Iris and Cabal";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs { inherit system; };
      mkHaskell =
        pkgs:
        pkgs.haskell.packages.ghc94.override {
          overrides = final: previous: {
            # Iris 0.1's released bounds require these older dependency families.
            # No jailbreak or allow-newer: build with the published constraints.
            ansi-terminal-types = final.callHackage "ansi-terminal-types" "0.11.5" { };
            ansi-terminal = final.callHackage "ansi-terminal" "0.11.5" { };
            ansi-wl-pprint = final.callHackage "ansi-wl-pprint" "0.6.9" { };
            # The upstream parser's old test-only QuickCheck bound is incompatible
            # with this package set. Product tests remain enabled below.
            optparse-applicative = pkgs.haskell.lib.dontCheck (
              final.callHackage "optparse-applicative" "0.17.1.0" { }
            );
            # Iris's own test suite likewise requires Hspec < 2.11. The CLI
            # library's published bounds are unchanged, and our tests use 2.11.
            iris = pkgs.haskell.lib.dontCheck (pkgs.haskell.lib.markUnbroken previous.iris);
          };
        };
      mkProject = pkgs: (mkHaskell pkgs).callCabal2nix "c-plugin" (pkgs.lib.cleanSource ./.) { };
    in
    {
      overlays.default = _final: previous: {
        c-plugin = self.packages.${previous.stdenv.hostPlatform.system}.c-plugin;
      };
      packages = forEachSystem (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          c-plugin = mkProject pkgs;
          default = self.packages.${system}.c-plugin;
        }
      );
      devShells = forEachSystem (
        system:
        let
          pkgs = mkPkgs system;
          h = mkHaskell pkgs;
        in
        {
          # Docker builds the Haskell executable itself. The E2E host only
          # needs the Go harness and the shared task runner.
          e2e = pkgs.mkShell {
            packages = [
              pkgs.go
              pkgs.just
            ];
          };
          default = pkgs.mkShell {
            packages = [
              (h.ghcWithPackages (p: [
                p.aeson
                p.aeson-pretty
                p.iris
                p.optparse-applicative
                p.yaml
                p.hspec
                p.temporary
              ]))
              pkgs.cabal-install
              pkgs.haskellPackages.fourmolu
              pkgs.haskellPackages.hlint
              pkgs.go
              pkgs.golangci-lint
              pkgs.just
              pkgs.nixfmt
            ];
          };
        }
      );
      checks = forEachSystem (system: {
        package = self.packages.${system}.c-plugin;
      });
    };
}
