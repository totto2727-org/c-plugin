{
  description = "A native MoonBit plugin skill manager";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    moonbit-overlay = {
      url = "github:moonbit-community/moonbit-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    moon-nix = {
      url = "github:moonbit-community/moon-nix/026f5a4e9fc7bf78699d69fdb70318c26ac8f07c";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.moonbit-overlay.follows = "moonbit-overlay";
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
      moon-nix,
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
      toolchainFor = pkgs: pkgs.moonbit-bin.latest;
      mkProject =
        pkgs:
        pkgs.callPackage ./package.nix {
          moonNix = moon-nix;
          toolchain = toolchainFor pkgs;
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
              (toolchainFor pkgs)
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
