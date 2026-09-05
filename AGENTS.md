# c-plugin

Migration snapshot: the standalone v2 source is placed under `src/`, its preserved design contract is at [docs/design/contract.md](./docs/design/contract.md), and Go/Testcontainers E2E sources and sibling documents are placed under `go/e2e/c-plugin/`. The inherited template guidance below is preserved in this raw snapshot and will be adapted in the documentation-first layer. This snapshot does not certify that all planned capabilities are implemented.

## Repository structure

```text
.github/workflows/          Validation and optional publishing workflows
AGENTS_TEMPLATE.md          AI and developer guidance for copied projects
README.md                   Relative symbolic link to README.mbt.md
README.mbt.md               Canonical template documentation
README_TEMPLATE.mbt.md      End-user documentation for copied projects
flake.nix                   Development shell, package, and overlay outputs
moon.mod                    Template module metadata
package.nix                 Minimal MoonBit package definition
src/main.mbt                Hello World command-line entry point
src/moon.pkg                Executable package configuration
```

## Development commands

### Execution rules

- Run commands from the repository root.
- Enter the environment with `nix develop` before running MoonBit commands.
- Read the `mbt-coding` skill before editing MoonBit production code, the `mbt-test` skill before editing MoonBit tests, and `docs-moonbit` when language-reference guidance is needed.
- Keep `README.md -> README.mbt.md` as a relative symbolic link; never replace it with an independently authored file.
- Keep Nix package commands separate from normal MoonBit validation.

### Standard tasks

- `nix develop` — Enter the pinned MoonBit development environment.
- `moon info` — Regenerate package interface information after public API changes.
- `moon check` — Type-check the project.
- `moon test` — Run the project tests.
- `moon run src` — Run the sample command-line application.
- `moon package --list` — Inspect the files included in the published package.
- `nix build .#project` — Build the optional Nix package independently.
- `nix run .` — Run the optional Nix package independently.

## Architecture

### Template documentation

- `README.mbt.md` and this `AGENTS.md` describe the template repository.
- `README_TEMPLATE.mbt.md` and `AGENTS_TEMPLATE.md` become the copied project's documentation after their placeholders are replaced.
- `README.md` is a relative symbolic link so GitHub and MoonBit use the same canonical document.

### Command-line sample

- `src/main.mbt` provides a dependency-free Hello World entry point.
- `src/moon.pkg` declares the package as an executable.
- Replace the sample directly rather than preserving a template-specific abstraction.

### Nix packaging

- `package.nix` delegates to `moonPlatform.buildMoonPackage` without duplicating build phases or package metadata.
- `flake.nix` exposes the package as `packages.project` and `packages.default` and exports it through `overlays.default`.
- The development shell remains usable when copied projects remove the optional package and overlay outputs.

### Automation

- CI validates the MoonBit project without adding Nix package builds to the normal source-validation flow.
- Mooncakes and FlakeHub publishing workflows remain disabled until a copied project explicitly enables them.

## Development tools

- **MoonBit**: Checks, tests, documents, and runs the command-line application.
- **Nix flakes**: Pin the toolchain and provide the optional package and overlay.
- **GitHub Actions**: Validate the repository and optionally publish releases.

## Package-specific rules

- When initializing a copied repository, replace `project`, `username/project`, and the repository URL in `moon.mod` and `flake.nix`, then update the module description, keywords, and version.
- Replace the Hello World implementation with the copied project's command-line behavior.
- Keep `package.nix` and the package and overlay outputs for distributable CLI applications so every README execution and installation path remains valid; remove them only when the copied project is no longer distributed as a CLI.
- Customize `README_TEMPLATE.mbt.md` and `AGENTS_TEMPLATE.md`, then replace the template-only canonical documents without changing the `README.md` symlink:

```bash
rm README.mbt.md AGENTS.md
mv README_TEMPLATE.mbt.md README.mbt.md
mv AGENTS_TEMPLATE.md AGENTS.md
```

- In the generated README, prefer `moonx username/project` with no runner options, and document direct `moonx`/`nix run`, installed `moon install`/`nix profile install`, and declarative overlay-based `flake.nix` setup as mutually exclusive choices; state that only one setup method is required.
- Keep publishing workflows disabled until every mutable `uses:` reference in each privileged publishing workflow is pinned to an audited full commit SHA.
- Store the base64-encoded Mooncakes credentials file in `MOONCAKES_TOKEN`. After pinning action references, validate with `moon publish --dry-run` in a protected environment, then enable publication by renaming `publish.yml.disabled` to `publish.yml`; otherwise delete the disabled file.
- Before enabling FlakeHub publication, use the official FlakeHub publishing wizard to verify the repository name, public visibility, and trusted GitHub organization binding. After those checks and action pinning, rename `flakehub-publish-rolling.yml.disabled` to `flakehub-publish-rolling.yml`; otherwise delete the disabled file.
- Run `nix flake update` whenever a package or Nix input is upgraded.
- Before handoff, run the MoonBit checks and package listing. When the optional Nix package remains, validate `nix build .#project` and `nix run .` separately.

_This AGENTS.md was generated from the [share-artifact skill](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/SKILL.md) and [AGENTS template](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/agents/template.md)._
