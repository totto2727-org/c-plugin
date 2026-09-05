{
  description = "A native MoonBit plugin skill manager";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    moonbit-overlay = {
      url = "github:totto2727-org/moonbit-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    moon-registry = {
      url = "git+https://mooncakes.io/git/index";
      flake = false;
    };
    vite-plus-overlay = {
      url = "github:ryoppippi/nix-vite-plus";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      moonbit-overlay,
      moon-registry,
      vite-plus-overlay,
      ...
    }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs supportedSystems;
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            moonbit-overlay.overlays.default
            vite-plus-overlay.overlays.default
          ];
        };
      mkProject =
        pkgs:
        pkgs.callPackage ./package.nix {
          moonRegistryIndex = moon-registry;
        };
    in
    {
      overlays.default = _final: previous: {
        c-plugin = self.packages.${previous.stdenv.hostPlatform.system}.c-plugin;
      };

      packages = forEachSystem (
        system:
        let
          c-plugin = mkProject (mkPkgs system);
        in
        {
          inherit c-plugin;
          default = c-plugin;
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            env = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
              MOONBIT_OPENSSL_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.openssl ];
              MOONBIT_NEW_NATIVE = "1";
            };
            packages = [
              pkgs.moonbit-bin.moonbit.latest
              pkgs.go
              pkgs.golangci-lint
              pkgs.vite-plus
              pkgs.bun
              pkgs.nodejs_24
              pkgs.just
              pkgs.nixfmt
            ];
            shellHook = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
              export NIX_LDFLAGS="$NIX_LDFLAGS -no_compact_unwind"
            '';
          };
        }
      );
    };
}
