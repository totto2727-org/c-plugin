# username/project

## Repository structure

```text
.github/workflows/  Validation and publishing workflows
flake.nix           Development shell and optional package outputs
moon.mod            Module metadata
package.nix         Optional Nix package definition
src/main.mbt        Command-line entry point
src/moon.pkg        Executable package configuration
README.mbt.md       Canonical end-user documentation
```

Replace the sample paths with the copied project's actual package layout.

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
- `moon run src` — Run the command-line application.
- `moon package --list` — Inspect the files included in the published package.
- `nix build .#project` — Build the optional Nix package independently.
- `nix run .` — Run the optional Nix package independently.

## Architecture

### Command-line application

- Replace this item with the command-line entry point and its responsibility.
- Document accepted arguments, output, exit status, and failures in `README.mbt.md`.

### Package boundaries

- Replace this item with the copied project's package ownership and dependency direction.
- Keep public declarations documented with caller-visible behavior, constraints, and errors.

### Nix packaging

- Keep `package.nix` minimal and delegate standard build behavior to `moonPlatform.buildMoonPackage`.
- Keep the package and overlay wiring for distributable CLI applications so every documented MoonBit and Nix path remains valid; remove it only when the project is no longer distributed as a CLI.

## Development tools

- **MoonBit**: Checks, tests, documents, and runs the project.
- **Nix flakes**: Pin the MoonBit toolchain and optionally build the command-line package.
- **GitHub Actions**: Validate and publish the repository.

## Package-specific rules

- Replace this section with repository-specific invariants and remove placeholder guidance before handoff.
- Keep README Usage centered on `moonx username/project` with no runner options when possible; add `--target native` only for a native-only package.
- Keep README Setup complete: present direct `moonx` and `nix run`, installed `moon install` and `nix profile install`, and a declarative `flake.nix` example using `overlays.default` as mutually exclusive choices; state that only one setup method is required.
- Keep publishing workflows disabled until every mutable `uses:` reference in each privileged publishing workflow is pinned to an audited full commit SHA.
- Store the base64-encoded Mooncakes credentials file in `MOONCAKES_TOKEN`. After pinning action references, validate with `moon publish --dry-run` in a protected environment, then enable publication by renaming `publish.yml.disabled` to `publish.yml`; otherwise delete the disabled file.
- Before enabling FlakeHub publication, verify the repository name, public visibility, trusted GitHub organization binding, and protected `main`, then enable the workflow only after action pinning; otherwise delete the disabled file.
- Run `nix flake update` whenever a package or Nix input is upgraded.
- Update `moon.mod` whenever module metadata or dependencies change.
- Run the MoonBit checks and package listing before handoff. When the optional Nix package remains, validate `nix build .#project` and `nix run .` separately.

_This AGENTS.md was generated from the [share-artifact skill](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/SKILL.md) and [AGENTS template](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/agents/template.md)._
