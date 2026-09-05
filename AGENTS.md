# c-plugin

<!-- Temporary: this feature PR intentionally precedes complete command integration.
Remove this availability note in S17 after the bit adapter and all eight Go cases are integrated. -->
**Current feature stage: S14.**
Available CLI entrypoints: help/version, init, skill sync, recursive sync, skill add --local, skill target add.
Later-stage commands and their examples below are specifications, not executable claims for this checkout.
Registered Go/Testcontainers cases in this checkout: 5.

## Repository structure

```text
README.mbt.md           Canonical end-user entrypoint
README.md               Relative symlink to README.mbt.md
AGENTS.md               Developer and agent instructions
CLAUDE.md               Relative symlink to AGENTS.md
docs/cli.md             CLI reference and capability status
docs/design/            English design contract and Japanese translation
go/e2e/c-plugin/         Scenario documents and cases introduced through this stage
src/                    Native CLI sources and implementation-aligned tests
moon.mod                Independent c-plugin module metadata
flake.nix, package.nix  Independent environment and CLI packaging definitions
.github/workflows/      Native and E2E validation
```

## Development commands

### Execution rules

- Run commands from this independent repository's root, not from its parent workspace.
- Enter the pinned environment with `nix develop`, install JavaScript dependencies with `vp install --frozen-lockfile`, and synchronize MoonBit dependencies with `moon update` before validation.
- Never use `npx` or `bunx`. Prefer `vp run`, then `vp exec`, then `vpx` for supported commands.
- Before production edits read [share-coding](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/share-coding/SKILL.md) and [mbt-coding](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/mbt-coding/SKILL.md).
- Before test edits read [share-test](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/share-test/SKILL.md) and [mbt-test](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/mbt-test/SKILL.md).
- Use the installed `moonbit-orientation` skill for language questions, or the [official documentation index](https://raw.githubusercontent.com/moonbitlang/moonbit-docs/main/next/index.md).
- Write repository artifacts in English, preserving the existing Japanese design translation. Use Japanese for PR titles, descriptions, review discussions, and Linear collaboration.
- Add publishing automation only after publication is explicitly approved and licensing, authentication, actual package availability, and immutable action pins have been verified.

### Standard tasks

```bash
vp run check       # Native checks and Go formatting/lint checks
vp run build       # Native CLI and Go package build
vp run mbt:test    # Native product tests without Docker
moon fmt --check   # Strict MoonBit formatting check
vp run test        # Native tests and real Go/Testcontainers E2E
vp run fix         # MoonBit and Go formatting/lint fixes
```

The E2E task builds the caller-owned image through `just c-plugin-e2e-image` and requires a working Docker daemon.
Keep native validation, Go/Testcontainers E2E, and Nix package builds as separately reported checks.
For package validation, run `nix build .#c-plugin` independently of development-shell checks.
Inspect the root and Go `vite.config.ts`, `package.json`, `Justfile`, and Nix outputs before changing task contracts.
Tests verify c-plugin behavior, not upstream-library conformance.
Dependency/toolchain probes are temporary investigation artifacts and must stay outside tracked output.
Product adapter contracts and end-to-end scenarios remain required.
Do not report a zero-test run or `no work to do` as product coverage.

### Documentation validation

Use the validator shipped with the `document-e2e-scenarios` skill:

```bash
python3 <skill-directory>/scripts/validate_scenario_docs.py go/e2e/c-plugin
```

Validate the real source/document directory, then run Go/Testcontainers separately.
A validator that discovers zero Go sources is not coverage, and documented expected results are not test-run reports.

## Architecture

### Product boundaries

- Preserve the native MoonBit stack: Admiral CLI parsing, Lens codecs, validated path values, async filesystem I/O, target-file discovery, and bit library adapters.
- Keep untrusted text at adapters and validate it into typed domain values once. Do not pass raw paths or generic JSON through command policy.
- Keep the source module identity `totto2727/c-plugin` distinct from the GitHub repository `totto2727-org/c-plugin` and Go E2E module `github.com/totto2727-org/c-plugin/go/e2e/c-plugin`.
These identities describe product source, not a publication claim.
- The implementation uses one executable package under `src/`, with implementation-aligned white-box test files. A conceptual layered diagram is not permission to add empty framework packages.
- Git operations use the bit libraries, not spawned `git` or `bit` CLI commands. The adapter alone does not implement GitHub add/update workflows.
- Preserve strict lock version `"2"`, canonical JSON, validated source identities, and isolated project/global lock scopes. No v1 lock conversion is provided.

### Filesystem and persistence

- Preserve ownership-safe creation/deletion, physical containment, literal symlink-target identity, and per-mutation durability checkpoints.
- Record ownership only after creating and verifying a link and successfully checkpointing it. Do not promise automatic adoption across the filesystem-mutation/checkpoint crash window.
- Missing or corrupt ownership records never authorize deletion or adoption of pre-existing paths.
- Explicit add force can replace only the exact contained eligible file or symlink. It does not authorize real-directory deletion, neighbor mutation, or scope escape.
- Duplicate local repositories/plugins/skills remain invalid input. Do not introduce union merge or same-source force-repeat synchronization through unrelated naming or documentation changes.
- Keep cancellation and supported semantic no-ops distinct from rejection. A persisted mutation synchronizes the exact candidate, while a rejected or no-op candidate must not be silently rewritten.

## Development tools

- **MoonBit**: Native implementation and implementation-aligned tests.
- **Nix flakes and direnv**: Pinned environment and separate CLI package/overlay validation.
- **Vite+ and Just**: Task orchestration and caller-owned E2E image setup.
- **Go and Testcontainers**: Isolated CLI workflows through [totto2727-org/e2e](https://github.com/totto2727-org/e2e).
- **GitHub Actions**: Native validation and separate Go/Testcontainers E2E execution.

## Package-specific rules

- Preserve each existing Go scenario, fixture, assertion, module checksum, lint configuration, image input, and task dependency.
- The caller builds `c-plugin-e2e:local`. Each registered case receives a separate disposable container with synthetic `HOME`, working directory, cache, and targets.
- The CLI under test is `/sandbox/.local/bin/c-plugin`. Existing `/tmp/c-plugin-v2-*` fixture paths are synthetic compatibility fixtures, not obsolete public names to rewrite indiscriminately.
- Maintain one complete section per source `*Scenario` function in each sibling `<stem>_test.md`, in source order, following the [E2E documentation contract](https://github.com/totto2727-org/e2e/pull/8).
- In each scenario use `Scope`, `Commands under test`, `Arguments and options`, `Preconditions and fixtures`, `Execution flow`, `Expected results`, and `Notes` as ordered third-level headings.
- Command tables contain executable/subcommand paths only. Put option tokens in their own table and complete ordered argv in the execution flow.
- Scenario Source links remain pinned while the corresponding Go source is absent. Restore sibling links with the owning implementation and validate every real source/document pair.
- The shared `runInitWorkflow` helper is not a ninth registered case. Keep the two init scenario sections aligned with the registered cases.

## MoonBit README maintenance

Keep the physical `README.mbt.md` as canonical content and `README.md -> README.mbt.md` as a relative symlink.
Keep `CLAUDE.md -> AGENTS.md` as the relative alias of these instructions.
Do not duplicate README content under `src/` or add permanent package manifests, stubs, or tests solely to compile documentation.
Use explicit `mbt nocheck` only for a real existing example that depends on an API not yet introduced, and record its path, API dependency, owning implementation, and re-enablement check.
The documentation has no MoonBit code fences, so there is nothing to disable and no reason to invent an example.
Re-enable real examples as `mbt check` with their implementing feature and validate the exact rendered artifact using supported `moon check README.mbt.md` and `moon test README.mbt.md` context.
Require evidence that the artifact was compiled or executed, not merely a zero-work exit status.
See the [official literate documentation](https://docs.moonbitlang.com/en/latest/language/docs.html) and [README symlink tutorial](https://docs.moonbitlang.com/en/latest/toolchain/moon/tutorial.html).

_This AGENTS.md was generated from the [share-artifact skill](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/SKILL.md) and [AGENTS template](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/agents/template.md)._
