{
  pkgs,
  lib,
  moonNix,
  toolchain,
  moonRegistryIndex,
}:
let
  builders = moonNix.lib.mkMoonNix { inherit pkgs toolchain; };
  project = builders.parseManifest "module" (builtins.readFile ./moon.mod);
  pname = lib.last (lib.splitString "/" project.name);
  # moon-nix 026f5a4 predates format-stable pkgtype and rejects dependencies'
  # equivalent ./src paths. Preserve current manifests and remaining guards.
  upstreamManifest = import "${moonNix}/lib/pure/manifest.nix" { inherit lib; };
  manifest = upstreamManifest // {
    read =
      kind: root:
      let
        raw = upstreamManifest.read kind root;
      in
      raw
      // lib.optionalAttrs (kind == "module" && raw ? source) {
        source = lib.removePrefix "./" raw.source;
      }
      // lib.optionalAttrs (kind == "package" && (raw.pkgtype.kind or null) == "executable") {
        is-main = true;
      };
  };
  # Use builders.buildProject directly once upstream supports both spellings.
  buildProject = import "${moonNix}/lib/pure/buildProject.nix" {
    inherit
      pkgs
      toolchain
      manifest
      builders
      ;
    resolver = import "${moonNix}/lib/pure/resolve.nix" { inherit lib manifest; };
  };
in
(buildProject {
  src = ./.;
  mainPackage = project.name;
  target = "native";
  name = pname;
  registry = toString moonRegistryIndex;
}).overrideAttrs
  (_: {
    inherit pname;
    version = project.version;
    meta = {
      description = project.description;
      homepage = project.repository;
      license = lib.meta.getLicenseFromSpdxId project.license;
      mainProgram = pname;
    };
  })
