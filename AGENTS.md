# c-plugin

<!-- migration-stage:start -->
**Current stage: S17, saved implementation integrated.**
Product sources and all eight existing Go/Testcontainers cases are present. Run the real native and E2E tasks; source presence alone is not a passing-test claim.
<!-- migration-stage:end -->

## Repository structure

```text
README.mbt.md           Canonical end-user entrypoint
README.md               Relative symlink to README.mbt.md
AGENTS.md               Developer and agent instructions
CLAUDE.md               Relative symlink to AGENTS.md
docs/cli.md             Saved implementation reference and capability status
docs/design/            English design contract and existing Japanese translation
docs/migration.md       Snapshot provenance, stage map, and validation boundaries
go/e2e/c-plugin/*.md    Scenario documents before their Go sources are introduced
src/                    Inherited template sample in the documentation-first baseline
moon.mod                Inherited template metadata until the bootstrap layer
flake.nix, package.nix  Inherited template environment and packaging definitions
.github/workflows/      Inherited validation and disabled publishing workflows
```

S0 is the documentation-first baseline; subsequent stages introduce product source and integration.
Product MoonBit sources, Go sources, E2E Dockerfile, and Vite+/Just integration are saved on the pinned migration snapshot and are introduced by their owning feature layers.
See [the stage map](./docs/migration.md#feature-stage-map) before treating a planned file or command as available in the current checkout.

## Development commands

### Execution rules

- Run commands from this independent repository's root, not from its parent workspace.
- Enter the pinned environment with `nix develop` before MoonBit validation when using Nix.
- Use existing Vite+ tasks once the bootstrap and E2E layers introduce them. Do not invent task names or restore unrelated Go/Elixir packages.
- Never use `npx` or `bunx`. Prefer `vp run`, then `vp exec`, then `vpx` for supported commands.
- Do not modify the inherited template implementation merely to make documentation appear executable.
- Before production edits read [share-coding](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/share-coding/SKILL.md) and [mbt-coding](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/mbt-coding/SKILL.md).
- Before test edits read [share-test](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/share-test/SKILL.md) and [mbt-test](https://github.com/totto2727-org/agent/blob/main/plugins/totto2727-coding/skills/mbt-test/SKILL.md).
- Use the installed `moonbit-orientation` skill for language questions, or the [official documentation index](https://raw.githubusercontent.com/moonbitlang/moonbit-docs/main/next/index.md).
- Write repository artifacts in English, preserving the existing Japanese design translation. Use Japanese for PR titles, descriptions, review discussions, and Linear collaboration.
- Keep publishing workflows disabled until publication is explicitly approved and their authentication and immutable action pins have been verified.

### Baseline and feature checks

At S0, the following commands check only the inherited template, not c-plugin product behavior. At later stages, validate the product sources actually present and prefer their defined Vite+ tasks:

```bash
moon check --target native
moon test --target native
```

The README contains no executable MoonBit fences.
Do not report a zero-test run, `no work to do`, or a template-only check as product or documentation-example coverage.
At S0 there are no Go source files, so a scenario validator that discovers zero files is not a successful E2E-documentation check.
Use the pinned-source projection described in [migration validation](./docs/migration.md#documentation-validation) instead.

### Commands introduced by later layers

The saved implementation's Vite+ tasks, Just image recipe, Go commands, Dockerfile, and Nix package commands belong to the feature layers that introduce their real definitions.
Inspect that layer's root and Go `vite.config.ts`, `package.json`, `Justfile`, and Nix outputs before running or documenting them.
Keep ordinary native validation separate from Nix package builds and from Go/Testcontainers E2E.
Run the real E2E suite after its image, source, and dependency-bearing feature layers exist.

## Architecture

### Product boundaries

- Preserve the native MoonBit stack: Admiral CLI parsing, Lens codecs, validated path values, async filesystem I/O, target-file discovery, and bit library adapters.
- Keep untrusted text at adapters and validate it into typed domain values once. Do not pass raw paths or generic JSON through command policy.
- Keep the source module identity `totto2727/c-plugin` distinct from the GitHub repository `totto2727-org/c-plugin` and Go E2E module `github.com/totto2727-org/c-plugin/go/e2e/c-plugin`.
These identities describe the saved product source, not a publication claim or the initial template metadata.
- The saved implementation uses one executable package under `src/`, with implementation-aligned white-box test files. A conceptual layered diagram is not permission to add empty framework packages.
- Git operations use the bit libraries, not spawned `git` or `bit` CLI commands. The adapter alone does not implement GitHub add/update workflows.
- Preserve strict lock version `"2"`, canonical JSON, validated source identities, and isolated project/global lock scopes. Repository migration does not add v1 lock conversion.

### Filesystem and persistence

- Preserve ownership-safe creation/deletion, physical containment, literal symlink-target identity, and per-mutation durability checkpoints.
- Record ownership only after creating and verifying a link and successfully checkpointing it. Do not promise automatic adoption across the filesystem-mutation/checkpoint crash window.
- Missing or corrupt ownership records never authorize deletion or adoption of pre-existing paths.
- Explicit add force can replace only the exact contained eligible file or symlink. It does not authorize real-directory deletion, neighbor mutation, or scope escape.
- Duplicate local repositories/plugins/skills remain invalid input. Do not introduce union merge or same-source force-repeat synchronization under a naming or documentation migration.
- Keep cancellation and supported semantic no-ops distinct from rejection. A persisted mutation synchronizes the exact candidate, while a rejected or no-op candidate must not be silently rewritten.

## Development tools

- **MoonBit**: Native implementation and implementation-aligned tests.
- **Nix flakes and direnv**: Pinned environment and separate CLI package/overlay validation.
- **Vite+ and Just**: Existing task orchestration and caller-owned E2E image setup, introduced with their feature layers.
- **Go and Testcontainers**: Isolated CLI workflows through [totto2727-org/e2e](https://github.com/totto2727-org/e2e).
- **GitHub Actions**: Baseline validation, with separately introduced E2E integration. Disabled publishing workflows are not release evidence.

## Package-specific rules

- Preserve each existing Go scenario, fixture, assertion, module checksum, lint configuration, image input, and task dependency when its feature layer is introduced.
- The caller builds `c-plugin-e2e:local`. Each registered case receives a separate disposable container with synthetic `HOME`, working directory, cache, and targets.
- The CLI under test is `/sandbox/.local/bin/c-plugin`. Existing `/tmp/c-plugin-v2-*` fixture paths are synthetic compatibility fixtures, not obsolete public names to rewrite indiscriminately.
- Maintain one complete section per source `*Scenario` function in each sibling `<stem>_test.md`, in source order, following the [E2E documentation contract](https://github.com/totto2727-org/e2e/pull/8).
- In each scenario use `Scope`, `Commands under test`, `Arguments and options`, `Preconditions and fixtures`, `Execution flow`, `Expected results`, and `Notes` as ordered third-level headings.
- Command tables contain executable/subcommand paths only. Put option tokens in their own table and complete ordered argv in the execution flow.
- Source links point to the pinned snapshot while source is absent. When adding the corresponding Go source, restore its relative source link and validate against the real directory.
- The raw `initScenario` helper is not a ninth registered case. If renamed in a later layer, update the document's helper section and source reference together.

## MoonBit README maintenance

Keep the physical `README.mbt.md` as canonical content and `README.md -> README.mbt.md` as a relative symlink.
Keep `CLAUDE.md -> AGENTS.md` as the relative alias of these instructions.
Do not duplicate README content under `src/` or add permanent package manifests, stubs, or tests solely to compile documentation.
Use explicit `mbt nocheck` only for a real existing example that depends on an API not yet introduced, and record its path, API dependency, feature stage, and re-enablement check.
The documentation has no MoonBit code fences, so there is nothing to disable and no reason to invent an example.
Re-enable real examples as `mbt check` with their implementing feature and validate the exact rendered artifact using supported `moon check README.mbt.md` and `moon test README.mbt.md` context.
Require evidence that the artifact was compiled or executed, not merely a zero-work exit status.
See the [official literate documentation](https://docs.moonbitlang.com/en/latest/language/docs.html) and [README symlink tutorial](https://docs.moonbitlang.com/en/latest/toolchain/moon/tutorial.html).

_This AGENTS.md was generated from the [share-artifact skill](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/SKILL.md) and [AGENTS template](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/agents/template.md)._
