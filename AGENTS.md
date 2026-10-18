# c-plugin maintenance

These instructions are for contributors and coding agents.
For consumer setup and usage, read [README.md](README.md).

## Repository structure

```text
README.md               Canonical consumer entrypoint, a physical file
AGENTS.md               Maintenance instructions
app/Main.hs             Iris CLI entrypoint
lib/CPlugin/            Command policy, discovery, paths, reconciliation, state IO
lib/CPlugin/Commands/   Per-command handlers and shared command support
lib/CPlugin/Reconcile/  Planning, session state, mutations, and reporting
lib/CPlugin/Types/      Type definitions with their validation and wire codecs
package.yaml           hpack source of truth for the product package
c-plugin.cabal          Checked-in generated Cabal definitions
cabal.project           Cabal project configuration
flake.nix, flake.lock   Pinned development environment and CLI package
Justfile                Shared task entrypoints
test/Spec.hs            Hspec suite entrypoint
test/CPlugin/           Domain, codec, plugin, reconciliation, and command specs
e2e/                    Hspec/Caseyard Docker tests and sibling scenario documents
docs/                   CLI reference and English/Japanese design contract
.github/workflows/      Validation automation
```

## Development commands

Run commands from this repository root, not its parent workspace.
Enter the pinned environment with `nix develop`.
GHC 9.4.8 remains pinned because Iris 0.1 has a compatible published `base` bound.
Do not bypass dependency bounds with `allow-newer`.
Maintain root `package.yaml` and `e2e/package.yaml`, then run `just generate` to regenerate the checked-in `.cabal` files.
Let hpack discover module lists automatically rather than maintaining them by hand.
The product shell supplies libgit2 1.9.7, pkg-config, and native dependencies.
Non-Nix Cabal builds require libgit2 `>= 1.9 && < 1.10` development headers and pkg-config, not Git for runtime transport.

```sh
just build     # Cabal product build
just build-nix # Independent Nix package build
just check     # Cabal, Fourmolu, and HLint checks
just fix       # Apply Fourmolu and check HLint suggestions
just test      # Haskell product tests, without Docker
just e2e       # Caller-owned image build and real Hspec/Caseyard tests
just e2e-check # Compile acceptance tests from the E2E shell without Docker
just ci        # Checks, Cabal build, and native tests
```

Validate the ordinary Cabal build and native tests, with real Docker E2E as a separate local task.
Independent Nix package validation is optional and is not part of `just ci`.
CI runs `nix develop --command just ci` and does not require Docker.
Docker E2E is an explicit local task and is not part of `just ci`.
Use `just build-nix` to run the independent package build alone.
Docker E2E requires a working Docker daemon.
Use `nix develop .#e2e --command just e2e` to run Docker E2E with the host-side Haskell toolchain.
The E2E shell provides GHC 9.10, Cabal, Git, and Just.
`e2e` is a separate Cabal project because Caseyard requires `base >=4.18`, while Iris keeps the product on GHC 9.4.
Its `cabal.project` pins the public Caseyard Git source to an immutable revision; it does not use a workspace-relative dependency.
Run `just e2e-check` in that shell to compile the acceptance suite without Docker.
The Docker sandbox-base builder runs an ordinary Cabal build inside `nix develop`, not `nix build`.
The Ubuntu 26.04 runtime copies only the actually linked Nix library closure, not the development toolchain.
Git and Python in that runtime support test fixtures and probes, not product transport.
The former Cabal `static` flag is removed.
Inspect `Justfile`, `c-plugin.cabal`, the E2E Dockerfile, and flake outputs before changing task contracts.
A zero-test run or a `no work to do` result is not product coverage.

## Architecture constraints

Read [the design contract](docs/design/contract.md) before changing path validation, parsing, lock persistence, or reconciliation.
Keep CLI parsing in Iris and command policy in `CPlugin.Commands.*`.
`CPlugin.Commands` owns only the command values and dispatch.
Keep each public operation in its own handler module, including list, plugin/skill removal, and registered-plugin skill enable/disable operations.
Use small shared helpers for rendering and related mutations instead of duplicating their safety policy.
`CPlugin.Commands.Common` owns shared lock loading, candidate persistence, and completion reporting.
Keep each domain type, its pure validation, and its serialization or deserialization in the same `CPlugin.Types.*` module.
`CPlugin.Types` is only a re-export entrypoint, not a second implementation.
Keep filesystem persistence in `CPlugin.StateStore`, separate from wire-format rules.
Keep `syncLoadedLock` as orchestration, with planning, session state, mutation steps, and reporting in `CPlugin.Reconcile.*`.
Use named mutation helpers instead of deeply nested local closures.
Preserve the exception scopes and the mutation/checkpoint order when decomposing these steps.
Do not add orphan JSON instances in unrelated modules.
Validate CLI, JSON, and filesystem input into domain values at their boundaries.
Keep the implementation small and use the existing Haskell modules rather than empty framework layers.

- Accept one explicit local or GitHub standard Agent Plugins 1.0 root or one explicit standalone Agent Skill directory. Do not scan plugin collections or infer the source kind. Do not add marketplaces, vendor-format detection, non-GitHub remotes, MCP execution, or hooks without explicit scope approval.
- Top-level `sync` reconciles both plugins and standalone skills offline from pinned sources. `update` refreshes both source kinds, validates a complete per-lock candidate, then reconciles even when the lock is unchanged. Keep `-r` compatible with the original Admiral 0.6.2 discovery rules, except documented `.git` and snapshot-cache safety exclusions.
- Keep `target` at the top level. Plugin and skill removal have separate selector domains. Disabling the final plugin skill must keep its plugin registration.
- Lists are read-only lock views, not source refreshes or reconciliation commands. Registered-plugin enable/disable must preserve source identity and use pinned GitHub caches without fetching.
- Keep GitHub value validation/codecs in `CPlugin.Types.GitHub` and cache/transport orchestration in `CPlugin.Source.GitHub`. Default commands use `CPlugin.Source.Libgit2` and its small direct C FFI, with no production Git subprocess fallback. Keep exported `runGit` only for injected tests and fixtures.
- Restrict public fetches to fixed HTTPS GitHub URLs at depth one. Isolate repository-local plus memory configuration, disable hooks and submodules, and preserve immutable-cache validation. Installed credential helpers and private authentication are unsupported. Cancellation can wait during DNS/TLS between callbacks. The internal adapter omits dangling-object `fsck` stdout and rejects conflict status, rather than implementing a general Git CLI. Never delete an existing cache entry. See [Git transport](docs/design/git-transport.md).
- Use stock Aeson-derived JSON instances for internal records and newtypes. Do not customize field names, constructor tags, or optional-field encoding. Validate decoded values at the persistence/cache boundary, including identities, duplicate selections, and map-key relationships. No legacy wire conversion is provided.
- Preserve canonical output, isolated project/global scopes, physical containment, exact literal symlink-target identity, and a checkpoint after each mutation.
- Missing or corrupt ownership records do not authorize deletion or adoption of existing paths.
- Explicit add force applies only to an exact eligible contained file or symlink. It never authorizes real-directory deletion, neighbor mutation, or scope escape.
- Record new ownership only after link creation, verification, and a successful checkpoint. Do not promise adoption across the mutation/checkpoint crash window.
- A successful lock mutation synchronizes the exact persisted candidate. Rejected candidates and semantic no-ops must not be silently rewritten.

## Tests and documentation

Test c-plugin behavior, not upstream library conformance.
Use Iris interactive mode and `--no-input`; keep typed selection parsing with its type and prompt effects in `CPlugin.Interaction`.
Exercise CLI terminal detection, retry, cancellation, interruption, and explicit non-terminal options through real pseudo-terminals in the Hspec/Caseyard suite.
Use temporary roots with synthetic `HOME`, working directory, plugin sources, targets, and ownership state.
Never use real user state in tests.
Keep dependency probes and temporary reports outside tracked artifacts.

For Haskell E2E, preserve each scenario, fixture, assertion, checksum, and task dependency unless the requested behavior requires a change.
The caller builds `c-plugin-e2e:local` once before the Hspec suite.
Each scenario is a standard Hspec `it` example that calls the public `Test.CLI.E2E.withEnvironment` and receives isolated container state.
Use Hspec `parallel` and its `--jobs=2` limit rather than an SDK-specific scheduler or custom case registry.
Do not add image creation inside individual examples.
The CLI under test is `/sandbox/.local/bin/c-plugin`.
The Python PTY driver is a Cabal data file used only inside the Linux test container; Haskell owns the scenario and assertions.
Existing `/tmp/c-plugin-v2-*` paths are synthetic compatibility fixtures, not public product names.

When changing a scenario-bearing Haskell module, update its sibling `.md` document in source order.
Use the ordered headings `Scope`, `Commands under test`, `Arguments and options`, `Preconditions and fixtures`, `Execution flow`, `Expected results`, and `Notes`.
Command tables contain executable/subcommand paths only. Put options in their own table and full ordered argv in the execution flow.
Use relative sibling Haskell source links.
The shared init helper is not an additional registered case.
Review scenario names, order, source links, invocations, and assertions against the actual Haskell source.
Report document review separately from compilation and real Docker execution.

Write maintained artifacts in English and keep [the Japanese contract](docs/design/contract.ja.md) aligned with its English source.
Use Japanese for PR titles, descriptions, review discussions, and Linear collaboration.
Keep `README.md` physical and maintenance instructions in `AGENTS.md`.
Do not add publishing automation without explicit approval and verified licensing, authentication, package availability, and immutable action pins.
