{
  description = "A simple MoonBit CLI template";

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
  };

  outputs =
    {
      self,
      nixpkgs,
      moonbit-overlay,
      moon-registry,
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
          overlays = [ moonbit-overlay.overlays.default ];
        };
      mkProject =
        pkgs:
        pkgs.callPackage ./package.nix {
          moonRegistryIndex = moon-registry;
        };
    in
    {
      overlays.default = _final: previous: {
        project = self.packages.${previous.stdenv.hostPlatform.system}.project;
      };

      packages = forEachSystem (
        system:
        let
          project = mkProject (mkPkgs system);
        in
        {
          inherit project;
          default = project;
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.moonbit-bin.moonbit.latest
            ];
          };
        }
      );
    };
}
