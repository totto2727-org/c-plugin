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
        let
          gitlibSource = pkgs.fetchFromGitHub {
            owner = "jwiegley";
            repo = "gitlib";
            rev = "25dcef2e4f09e571f71c795f5b32267038258cea";
            hash = "sha256-UD2r4r/s7osuz/c8+QXSPuNNtyim3Rgb4FQtbIk4Ryw=";
          };
        in
        pkgs.haskell.packages.ghc94.override {
          overrides = final: previous: {
            gitlib = final.callCabal2nix "gitlib" (gitlibSource + "/gitlib") { };
            gitlib-test = final.callCabal2nix "gitlib-test" (gitlibSource + "/gitlib-test") { };
            gitlib-cmdline = final.callCabal2nix "gitlib-cmdline" (gitlibSource + "/gitlib-cmdline") {
              git = pkgs.git;
            };
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
      mkProject =
        pkgs:
        pkgs.haskell.lib.overrideCabal
          ((mkHaskell pkgs).callCabal2nix "c-plugin" (pkgs.lib.cleanSource ./.) { })
          (old: {
            buildTools = (old.buildTools or [ ]) ++ [
              pkgs.git
              pkgs.makeWrapper
            ];
            postInstall = (old.postInstall or "") + ''
              wrapProgram "$out/bin/c-plugin" \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.git ]} \
                --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            '';
          });
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
          # Caseyard uses a newer base than Iris. Keep the host-side E2E
          # compiler separate from the GHC 9.4 product build in Docker.
          e2e = pkgs.mkShell {
            packages = [
              pkgs.ghc
              pkgs.cabal-install
              pkgs.haskellPackages.hpack
              pkgs.go
              pkgs.git
              pkgs.zlib
              pkgs.pkg-config
              pkgs.just
            ];
            shellHook = ''
              # Enable Git Hook
              vp config
            '';
          };
          default = pkgs.mkShell {
            packages = [
              (h.ghcWithPackages (p: [
                p.aeson
                p.aeson-pretty
                p.async
                p.brick
                p.vty
                p.vty-unix
                p.mtl
                p.iris
                p.optparse-applicative
                p.yaml
                p.hspec
                p.temporary
              ]))
              pkgs.cabal-install
              pkgs.haskellPackages.hpack
              pkgs.git
              pkgs.haskellPackages.fourmolu
              pkgs.haskellPackages.hlint
              pkgs.just
              pkgs.nixfmt
            ];
            shellHook = ''
              # Enable Git Hook
              vp config
            '';
          };
        }
      );
      checks = forEachSystem (system: {
        package = self.packages.${system}.c-plugin;
      });
    };
}
