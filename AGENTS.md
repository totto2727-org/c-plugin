# c-plugin maintenance

These instructions are for contributors and coding agents.
For consumer setup and usage, read [README.md](README.md).

## Repository structure

```text
README.md              Canonical consumer entrypoint, a physical file
AGENTS.md              Maintenance instructions
CLAUDE.md              Relative symlink to AGENTS.md
app/Main.hs            Iris CLI entrypoint
hs-src/CPlugin/        Types, Codec, Paths, Plugin, Reconcile, Commands
c-plugin.cabal         Cabal library, executable, and test definitions
cabal.project          Cabal project configuration
flake.nix, flake.lock  Pinned development environment and CLI package
Justfile               Shared task entrypoints
test/                  Haskell product tests
go/e2e/c-plugin/       Go/Testcontainers cases and sibling scenario documents
docs/                  CLI reference and English/Japanese design contract
.github/workflows/     Validation automation
```

## Development commands

Run commands from this repository root, not its parent workspace.
Enter the pinned environment with `nix develop`.
GHC 9.4.8 remains pinned because Iris 0.1 has a compatible published `base` bound.
Do not bypass dependency bounds with `allow-newer`.

```sh
just build     # Cabal product build
just check     # Static/package checks and Go checks
just test      # Haskell product tests, without Docker
just e2e       # Caller-owned image build and real Go/Testcontainers tests
just ci        # Combined development validation
```

Report native checks, Docker E2E, and Nix package validation separately.
Run `nix build .#c-plugin` independently of development-shell checks.
Docker E2E requires a working Docker daemon.
Inspect `Justfile`, `c-plugin.cabal`, the E2E Dockerfile, and flake outputs before changing task contracts.
A zero-test run or a `no work to do` result is not product coverage.

## Architecture constraints

Read [the design contract](docs/design/contract.md) before changing path validation, parsing, lock persistence, or reconciliation.
Keep CLI parsing in Iris and command policy in `CPlugin.Commands`.
Validate CLI, JSON, and filesystem input into domain values at their boundaries.
Keep the implementation small and use the existing Haskell modules rather than empty framework layers.

- Accept local standard Agent Plugins 1.0 skills only. Do not add marketplaces, vendor-format detection, GitHub lifecycle, MCP execution, or hooks without explicit scope approval.
- Preserve strict lock version `"3"`, canonical output, duplicate rejection, and isolated project/global scopes. No old lock conversion is provided.
- Preserve ownership version `"1"`, physical containment, exact literal symlink-target identity, and a checkpoint after each mutation.
- Missing or corrupt ownership records do not authorize deletion or adoption of existing paths.
- Explicit add force applies only to an exact eligible contained file or symlink. It never authorizes real-directory deletion, neighbor mutation, or scope escape.
- Record new ownership only after link creation, verification, and a successful checkpoint. Do not promise adoption across the mutation/checkpoint crash window.
- A successful lock mutation synchronizes the exact persisted candidate. Rejected candidates and semantic no-ops must not be silently rewritten.

## Tests and documentation

Test c-plugin behavior, not upstream library conformance.
Use temporary roots with synthetic `HOME`, working directory, plugin sources, targets, and ownership state.
Never use real user state in tests.
Keep dependency probes and temporary reports outside tracked artifacts.

For Go E2E, preserve each scenario, fixture, assertion, checksum, lint setting, and task dependency unless the requested behavior requires a change.
The caller builds `c-plugin-e2e:local` before Go tests.
Each registered scenario receives a separate disposable container.
The CLI under test is `/sandbox/.local/bin/c-plugin`.
Existing `/tmp/c-plugin-v2-*` paths are synthetic compatibility fixtures, not public product names.

When changing a Go `*Scenario` function, update its sibling `<stem>_test.md` section in source order.
Use the ordered headings `Scope`, `Commands under test`, `Arguments and options`, `Preconditions and fixtures`, `Execution flow`, `Expected results`, and `Notes`.
Command tables contain executable/subcommand paths only. Put options in their own table and full ordered argv in the execution flow.
Use relative sibling Go source links.
The shared init helper is not an additional registered case.
Run the validator from the installed `document-e2e-scenarios` skill against the real `go/e2e/c-plugin` directory, then run Go/Testcontainers separately.
A validator that discovers no Go sources is not coverage.

Write maintained artifacts in English and keep [the Japanese contract](docs/design/contract.ja.md) aligned with its English source.
Use Japanese for PR titles, descriptions, review discussions, and Linear collaboration.
Keep `README.md` physical and `CLAUDE.md -> AGENTS.md` as a relative alias.
Do not add publishing automation without explicit approval and verified licensing, authentication, package availability, and immutable action pins.
