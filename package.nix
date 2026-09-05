{ moonPlatform, moonRegistryIndex }:
moonPlatform.buildMoonPackage {
  src = ./.;
  inherit moonRegistryIndex;
  moonMod = ./moon.mod;
  doCheck = false;
}
