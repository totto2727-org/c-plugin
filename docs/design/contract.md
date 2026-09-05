# c-plugin design contract

This document preserves the intended design of the v2 rewrite as the standalone `c-plugin` project.
It is not a statement that every planned command is implemented or released.
The documentation-first baseline adds no product source; see the [saved capability status](../cli.md#capability-status) and [migration stage map](../migration.md#feature-stage-map).

[Japanese translation](./contract.ja.md).
Source: [raw migration snapshot `5d6f66a8`](https://github.com/totto2727-org/c-plugin/blob/5d6f66a83be6ed23d16d3c8535722970e028a003/docs/design/contract.md).

## Availability and identities

The standalone executable is `c-plugin`, the MoonBit source module is `totto2727/c-plugin`, and the repository is `totto2727-org/c-plugin`.
These source identities are not registry publication claims.
Design documents live under `docs/design/`, the saved native package under `src/`, and Go/Testcontainers E2E under `go/e2e/c-plugin/`.
v1 is not included and its old ADRs are not the current contract.
No v1 lock conversion, automatic migration, or `migrate` command is provided.
Never run old and new executables against the same lock scope.

The raw snapshot wires init, local add/remove/sync/recursive sync, and target add/remove.
The bit adapter is present, but GitHub add/update/cache workflows, TTY interaction, and marketplace authoring are not implemented leaf features.
Their contracts below remain planned, tracked by [GitHub lifecycle](https://linear.app/totto2727/issue/TOT-218), [TTY selection](https://linear.app/totto2727/issue/TOT-219), [authoring](https://linear.app/totto2727/issue/TOT-220), and [full parity](https://linear.app/totto2727/issue/TOT-221).
Broad idempotence/union behavior remains an unimplemented goal tracked separately in [TOT-224](https://linear.app/totto2727/issue/TOT-224), not a guarantee overriding accepted local-add rejection.

## Goals

- Reimplement c-plugin in MoonBit while preserving the current user-visible capabilities.
- Organize the command tree around extensible resource namespaces and restore the interactive choices that were present before the current MoonBit port.
- Use typed paths, strict lock-file decoding, library-based Git operations, and deterministic tests from the start.
- Keep project and global installations isolated. Broader non-`init` idempotence remains a goal, not a current blanket guarantee; local add rejects duplicate identities.

Functional equivalence includes preserving the public `c-plugin skill` namespace, while allowing internal functions to be redesigned.

## Technology stack

| Concern             | Decision                                                                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Language and target | MoonBit, native target only                                                                                                                    |
| CLI parsing         | `totto2727/admiral`                                                                                                                            |
| Interactive input   | `mizchi/tui`                                                                                                                                   |
| Git                 | The `mizchi/bit` module used as a library, primarily through its library packages such as `mizchi/bit_lib`; never spawn `git` or the `bit` CLI |
| Paths               | `moonbitlang/x/path.Path` at filesystem boundaries, with `totto2727/x@0.3.0/path.AbsolutePath` and `RelativePath` for validated domain values  |
| Lock discovery      | `totto2727/target-file-discovery`                                                                                                              |
| JSON                | `totto2727/lens` plus the standard `FromJson` and `ToJson` traits                                                                              |
| Async I/O           | `moonbitlang/async`                                                                                                                            |
| Unit tests          | MoonBit black-box and white-box tests using per-test temporary roots                                                                           |
| E2E tests           | Go/Testcontainers orchestration, fixtures, assertions, and one isolated container per scenario                                                 |

All dependencies must be pinned to exact compatible versions. The first implementation gate is a minimal native build importing Admiral, TUI, bit, Lens, target-file-discovery, async, `moonbitlang/x/path`, and `totto2727/x@0.3.0/path` together. Implementation must not proceed on an unverified dependency combination.

`mizchi/bit` currently describes itself as experimental and warns about possible repository corruption. c-plugin therefore treats cached clones as disposable data, pins the dependency, and tests the exact clone, fetch, checkout, and HEAD-resolution APIs it uses.

## Intended command model

The `skill` namespace remains the home of skill management. This preserves room for future top-level resource namespaces such as `hook` and `mcp`. Author-only marketplace conversion stays under `dev` so it remains separate from installation commands.

```text
c-plugin
├── init
├── skill
│   ├── add
│   ├── remove
│   ├── sync
│   ├── update
│   └── target
│       ├── add
│       └── remove
└── dev
    └── marketplace
        └── sync
```

The full intended leaf-command contract is shown below. Only the subset identified under Availability and identities is wired in the saved implementation.

| Command                                                                                                                  | Contract                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `c-plugin init [-g]`                                                                                                     | Exclusively create an empty lock file. Fail without modifying it if it already exists.                                                                                                                                                                                   |
| `c-plugin skill add [<owner/repo> \| --local <./path>] [-g] [-f \| --force] [--kind <kind>] [--skill <plugin/skill>...]` | Add a GitHub or local marketplace, select its marketplace kind and enabled skills, pin GitHub state, write the lock, and synchronize links. Exactly one of the GitHub positional or `--local` is accepted. Force replaces contained regular-file and symlink collisions. |
| `c-plugin skill remove [-g] [--skill <repo/plugin/skill>...]`                                                            | Remove selected installed skills. Remove an empty plugin entry, an empty repository entry, and the disposable Git cache only after its final skill is removed.                                                                                                           |
| `c-plugin skill sync [-g \| -r]`                                                                                         | Reconcile managed links from lock state without changing Git pins.                                                                                                                                                                                                       |
| `c-plugin skill update [-g \| -r]`                                                                                       | Fetch GitHub repositories, advance pins, rewrite the lock, and synchronize links. Local repositories are not fetched.                                                                                                                                                    |
| `c-plugin skill target add <path> [-g]`                                                                                  | Register an additional skill-link root and synchronize it. Duplicate resolved paths are a successful no-op.                                                                                                                                                              |
| `c-plugin skill target remove [-g] [--target <path>...]`                                                                 | Remove selected additional roots from lock state and remove only c-plugin-managed links from those roots.                                                                                                                                                                |
| `c-plugin dev marketplace sync <claude\|cursor\|codex>`                                                                  | Use the selected marketplace kind as the source and regenerate the other marketplace manifests and available per-plugin `plugin.json` files.                                                                                                                             |

`-g` and `-r` are mutually exclusive. Recursive mode applies only to `sync` and `update`.

### Planned interactive and non-interactive input

The following TTY behavior is planned, not implemented in the saved snapshot. Once introduced, `mizchi/tui` will provide the selection UI when stdin is a TTY and an explicit selection option is absent:

- `skill add` shows a single-select marketplace-kind prompt when multiple supported kinds exist.
- `skill add` shows a multi-select list of `plugin/skill` entries, with already-enabled skills preselected.
- `skill remove` shows a multi-select list of installed `repository > plugin/skill` entries.
- `skill target remove` shows a multi-select list of registered additional target directories.

When stdin is not a TTY, the corresponding `--kind`, repeatable `--skill`, or repeatable `--target` options are required. Non-interactive execution must never silently select every item or accept a default that an interactive user would normally choose.

Cancel and empty selection are successful no-ops and must not rewrite the lock file.

The TUI is an adapter around selection state, not part of command business logic. Command handlers consume typed selection results so unit tests can inject deterministic choices without controlling a real terminal.

## Functional parity baseline

The rewrite is complete only when it preserves these capabilities:

- GitHub marketplace sources written as `owner/repository` and local marketplace sources beginning with `./`.
- Claude, Cursor, and Codex marketplace detection and parsing.
- Explicit skill enablement per plugin rather than implicit installation of every discovered skill.
- GitHub commit pinning and repeatable synchronization at the pinned commit.
- Update to the remote default branch followed by lock and link refresh.
- Primary links under `.agents/skills` plus zero or more additional link targets.
- Nearest-parent project lock discovery, exact home-level global lock discovery, and recursive descendant lock discovery.
- `.gitignore`-aware recursive traversal through `totto2727/target-file-discovery`.
- Tolerant multi-repository synchronization: one unavailable repository is reported and skipped without preventing independent repositories from being synchronized.
- Deterministic duplicate skill-name resolution using the last repository in canonical repository order at reconciliation time, independent of JSON input order and internal collection iteration order.
- Marketplace conversion among Claude, Cursor, and Codex formats.
- Codex local source objects with normalized `./plugins/...` paths and `policy.installation = "INSTALLED_BY_DEFAULT"`.
- Copying a base-kind plugin's `plugin.json` to target kinds when the base file exists.

The new lock format is versioned separately from v1. Capability parity does not imply accepting malformed v1 documents or preserving tolerant-decoder bugs.

Lock migration is intentionally out of scope for the current implementation. c-plugin v2 provides neither automatic migration nor a `migrate` command, and its decoder must not reinterpret an older version as v2. When an existing lock declares an unsupported version, every command that loads that lock fails without rewriting it or changing links, cache, or ownership state. `init` also continues to reject any existing lock rather than replacing it.

A migration path may be added later as a separate, explicitly approved milestone. It must be an explicit operation with version-to-version conversion rules, atomic persistence, synchronization after a successful write, and dedicated unit and E2E coverage; it must not be introduced as a permissive fallback inside normal lock decoding. Keeping the top-level lock version mandatory preserves this future extension point without implementing migration now.

## Scope and path rules

The lock filename remains `c-plugin-lock.json`.

| Scope         | Lock path                                                                | Primary managed skill root |
| ------------- | ------------------------------------------------------------------------ | -------------------------- |
| Project       | Nearest ancestor `<root>/c-plugin-lock.json`, bounded by the user's home | `<root>/.agents/skills`    |
| Global (`-g`) | `~/c-plugin-lock.json` exactly                                           | `~/.agents/skills`         |

The global lock file is deliberately not stored under `~/.agents/`.

`init` uses the current working directory as the project root or the injected home directory for `-g`. Every other scoped command locates an existing lock with `totto2727/target-file-discovery`; it does not guess a different root.

Recursive discovery starts at the directory containing the nearest project lock and includes that lock plus descendant locks. Global mode never performs recursive discovery.

The cache root defaults to `~/.cache/c-plugin/repositories` and is configurable at the runtime boundary for tests. Cache contents are never authoritative; the lock file is authoritative.

### Cache identity and lock isolation

Repository caches are scoped by the lock file that owns them. An owner/repository-only cache key is forbidden because two project locks may pin the same GitHub repository to different commits.

After the lock path is normalized to an absolute `Path`, derive its cache scope key as follows:

```text
scope_key = lowercase_hex(sha256(utf8("lock\0" + normalized_absolute_lock_path)))
cache_path = cache_root / scope_key / lowercase(owner) / lowercase(repository)
```

The complete 64-character SHA-256 digest is used; language-runtime hash values and shortened digests are not allowed. Project mode hashes the discovered absolute project lock path, while global mode hashes the absolute `~/c-plugin-lock.json` path under the injected home directory.

Each scope directory contains `c-plugin-cache-scope.json`, generated metadata recording the format version and the exact normalized absolute lock path used as the hash input. Before reusing the directory, c-plugin must strictly validate that metadata. A missing or mismatched record is an error rather than permission to share the directory, so even a digest collision or manually copied cache cannot silently combine two lock scopes.

GitHub owner and repository components are validated by their domain constructors and canonicalized to lowercase before joining them to the scope path. Raw `owner/repository` input is never appended as one path string. This canonicalization intentionally maps case variants to the same identity because GitHub treats both route components as case-insensitive.

The consequences are:

- References to the same repository from one lock share one cache and one pinned working tree.
- Different project or global locks use different caches even when they reference the same repository, so checkout, update, and deletion cannot change another lock's materialized skills.
- Cache mutations are serialized by the complete scoped cache `Path`, not only by owner/repository.
- Removing the last reference in one lock may delete only that lock's scoped repository cache.
- Moving a project changes its normalized lock path and therefore its scope key. The old cache is disposable orphaned data and must never be adopted implicitly by the new scope.

### Path typing

- Convert CLI strings, environment strings, and JSON strings to `Path` immediately at their owning boundary.
- Pass `Path` through command, application, discovery, lock, filesystem, cache, marketplace, and symlink logic.
- Convert `Path` to `String` only at terminal library calls that currently require strings, including MoonBit async filesystem calls, Lens JSON encoding, and current bit APIs.
- Represent a GitHub repository as a validated `GitHubRepository { owner, name }`, not as an unrestricted path-like string.
- Store relative local marketplace paths and target paths as typed domain values whose constructors enforce their constraints.
- Normalize before comparing paths. Do not compare user-provided path spellings directly.

`totto2727/target-file-discovery` currently exposes string-based public functions. Its conversion is confined to one discovery adapter so untyped paths do not leak into the rest of c-plugin. A Path-based API may be added to that library later, but it is not required to create a second discovery implementation.

## Git policy

- Declare the pinned bit library modules used by the saved source (`mizchi/bit_lib`, `mizchi/bit_object`, and `mizchi/bit_osfs`) and call their APIs directly.
- Do not use `moonbitlang/async/process` for Git and do not fall back to an installed `git` or `bit` executable.
- Support HTTPS GitHub clone, fetch, default-branch resolution, checkout of a pinned commit, and HEAD object-id resolution through one narrow `BitRepositoryStore` adapter.
- Keep bit's current string paths inside that adapter; its public c-plugin-facing API accepts and returns `Path` and typed object IDs.
- Store repositories under the deterministic lock-scoped cache path defined above.
- Serialize mutations that address the same cached repository. Independent read-only resolution may run concurrently.
- Never apply working-tree mutations to the user's source repository. All Git mutations occur only in disposable c-plugin cache directories.

## Filesystem and idempotence policy

`init` lock creation is the only exclusive creation operation. It must not overwrite an existing lock file.

Existing directories and command-specific no-op behavior follow the rules below. This is not a general promise that every repeated non-`init` command succeeds:

- Existing expected directories are accepted.
- Local add rejects duplicate repository, plugin, and skill identities before persistence, including a repeated source registration. It does not merge enabled skills or rerun synchronization merely because force was requested. [TOT-121](https://linear.app/totto2727/issue/TOT-121) defines this accepted behavior.
- Registering an already normalized target is a successful no-op. Empty, unknown, and repeated removals retain their documented no-op behavior. These individual guarantees do not imply union semantics for add.
- Existing c-plugin-managed files and symlinks may be refreshed or removed according to the lock.
- By default, a foreign file, directory, or non-managed symlink at a desired output path is left untouched and reported as skipped.
- `skill add -f` or `skill add --force` may replace only a regular file or symlink at the exact contained desired output path. It never removes a real directory, special path, neighbor, or path outside the managed root.
- Sync never clears a directory wholesale; it removes only links known to be managed by c-plugin.
- Planned marketplace generation may replace its own target manifest and copied `plugin.json`, but must never remove unrelated files from existing directories.

### Symlink ownership state

A symlink does not carry reliable metadata identifying the process that created it. The lock records desired portable state, so it cannot by itself identify links that became stale after another person edited the lock. c-plugin therefore maintains a separate machine-local ownership file for materialized links:

| Scope         | Ownership state path                 |
| ------------- | ------------------------------------ |
| Project       | `<root>/.agents/c-plugin-state.json` |
| Global (`-g`) | `~/.agents/c-plugin-state.json`      |

The ownership state is generated runtime state, not shared configuration and not a second source of desired state. Each entry records the absolute link path, the literal target written into the symlink, the normalized resolved target, and the source repository, plugin, and skill identity. It also retains links in target roots that were later removed from the lock.

`sync` reconciles the desired lock with the previous ownership state as follows:

1. Read and strictly validate both the lock and ownership state.
2. Compute desired links from the lock and stale links from `previously owned - desired`.
3. Delete a stale path only after verifying its symlink kind, recorded resolved target, managed-root containment, and applicable ownership identity. Preserve the recorded literal `symlinkTarget` rather than normalizing it into a different identity.
4. If the path is now a file, directory, or different symlink, leave it untouched, report that ownership was lost, and omit it from the next ownership state.
5. Do not automatically adopt a pre-existing unrecorded symlink, even when it currently resolves to the desired target.
6. Reconcile missing desired links and checkpoint the state after each filesystem mutation. Admit a newly created link into durable ownership only after post-create verification and a successful checkpoint; stop and report checkpoint failure instead of declaring success.

This state survives external lock edits, so a later `c-plugin skill sync` can remove links for deleted skills and deleted target registrations. Ownership is scoped per lock; recursive sync must not let one lock delete links owned by another lock.

Safety rules:

- Missing or corrupt ownership state disables deletion of pre-existing links. Sync may create missing non-conflicting links and start a new state, but it must not infer or adopt ownership by scanning.
- Every path loaded from ownership state must be validated against its recorded managed root before any filesystem mutation.
- A broken symlink cannot be target-verified with the current public `moonbitlang/async/fs` API because it exposes symlink-aware `kind` and `realpath`, but not the literal `readlink` value. Leave such a link untouched and report it. A small `readlink` filesystem adapter may be added later if broken-link cleanup becomes required.
- Ownership state writes use a temporary sibling and atomic rename. Ownership-state writes do not recursively trigger `sync`; only lock mutations do.
- A crash between a filesystem mutation and its durability checkpoint does not guarantee recovery or automatic ownership adoption. A pre-existing unrecorded result remains protected by the no-adoption rule.
- Preserve `symlinkTarget` as the exact stored literal and keep it distinct from the normalized resolved target; constructor/codec round trips must not rewrite its identity.
- Disposable Git cache deletion happens after stale managed links are reconciled so their targets remain verifiable during deletion.

### Lock-mutation invariant

Every successful mutation of an existing lock file must run the normal `sync` reconciliation against the exact persisted lock value before the command returns. This applies to repository, plugin, enabled-skill, target, marketplace-kind, commit-pin, and future resource changes.

- `init` is the only exception because it creates a new empty lock rather than updating an existing lock.
- A cancelled or semantic no-op command neither writes the lock nor needs to run `sync`.
- Command workflows must use one `persist_and_sync` application boundary; they must not call the lock writer directly and return without reconciliation.
- If persistence succeeds but `sync` fails, the command returns a non-zero status and reports that rerunning `c-plugin skill sync` will reconcile the persisted state.
- Recursive operations apply this invariant independently to every lock they mutate.

Lock writes use a temporary sibling file followed by an atomic rename. The in-memory candidate is fully validated before persistence. Lock mutations use this order:

1. Resolve and validate the complete candidate state.
2. Write the lock atomically.
3. Reconcile managed links and disposable cache state.

A failure before step 2 preserves the previous state. A failure after step 2 is recoverable by rerunning `sync`.

## Lock-file model

The v2 lock is strict and uses a top-level discriminator for data-carrying enum variants.

```json
{
  "version": "2",
  "targets": ["~/.claude/skills"],
  "repositories": [
    {
      "type": "github",
      "repository": "totto2727-org/agent",
      "marketplaceKind": "claude",
      "commit": "0123456789abcdef0123456789abcdef01234567",
      "plugins": [
        {
          "name": "symphony",
          "path": "plugins/symphony",
          "enabledSkills": ["commit"]
        }
      ]
    },
    {
      "type": "local",
      "path": "./",
      "marketplaceKind": "codex",
      "plugins": []
    }
  ]
}
```

JSON rules:

- Encode the required lock `version` as the exact string `"2"`; JSON numbers are not accepted because binary floating-point parsing cannot preserve precision-sensitive version tokens for strict validation.
- Define every lock field with Lens.
- Decode Lens-selected values through standard `FromJson` with the Lens-derived `JsonPath`.
- Encode with standard `ToJson`, Lens `JsonBuilder`, and `set_or_abort`.
- Decode `LockRepository` by reading its top-level `type` once, then delegate to the complete `github` or `local` payload decoder.
- Encode `LockRepository` by matching the enum once and emitting its complete variant object.
- Do not infer a variant from the presence of `commit`, `repository`, or `path`, and do not branch independently for each property.
- Scalar closed enums such as `MarketplaceKind` may use a strict string representation.
- Missing required fields, unknown enum values, wrong types, malformed paths, invalid repository names, duplicate identities, and unsupported versions are errors.
- Never treat corrupt JSON as an empty lock, silently filter invalid repository entries, or replace invalid values with permissive defaults.
- Store unique aggregates in immutable hash sets and maps without retaining JSON input order. Sort only at the boundary that needs ordering: canonical JSON sorts targets by normalized path, repositories by source kind and identity, plugins by name, enabled skills by name, and ownership entries by normalized link path, using lexicographical code-unit order.

The lock codec has one round-trip property: decoding the canonical encoded form returns the same domain value. Pretty output uses two-space indentation and a trailing newline.

## Conceptual internal structure

The saved implementation is one executable package under `src/` with implementation-aligned source and white-box files. The following diagram describes intended responsibilities, not directories already present or a required package split:

```text
src/
├── cli/            Admiral command definitions and argv-to-domain parsing
├── interaction/    mizchi/tui selection views and pure selection state
├── command/        Add, remove, sync, update, target, init, and dev workflows
├── domain/         Lock, repository, marketplace, skill, target, and validated identifier types
├── adapter/        Lens lock and ownership-state stores, target discovery, bit Git, async filesystem, and symlinks
├── e2e/            Dockerfile for the caller-built E2E image
└── main/           Executable entry point
```

Use direct functions and small records of callbacks where injection is needed. Do not create a service, repository, or trait layer unless it replaces an actual external boundary used by tests.

## Unit-test policy

Unit tests are mandatory and run through normal MoonBit test commands.

- Create a fresh temporary root per test and clean it after the test.
- Place synthetic home, working directory, lock, `.agents`, cache, marketplace, and target directories under that temporary root.
- Inject runtime paths; never read the real user's home, working tree, cache, global lock, or global skill targets from a test.
- Test `-g` with a synthetic home. Omit only a platform-specific case that cannot be isolated, and record the reason next to that test suite.
- Use bit only against disposable repositories under the temporary root in unit tests.
- Test lock round trips, strict failures, top-level enum dispatch, canonical ordering, and JSON error paths.
- Test that unsupported lock versions preserve the exact lock bytes and do not mutate links, cache, or ownership state.
- Test Path normalization, project/global/recursive discovery, local-source constraints, target deduplication, lock-scope key derivation, scope-metadata construction and codec validation, and cache isolation for two locks that pin the same repository differently. Test metadata mismatch rejection when the cache storage adapter that consumes persisted metadata is introduced.
- Test pure TUI selection state and inject scripted selections into command tests.
- Test idempotent repeated commands, foreign path collisions, managed-link replacement, duplicate skill precedence, partial repository failure, and state preservation before persistence.
- Test that every existing-lock mutation passes its persisted candidate to `sync`, while `init`, cancellation, and semantic no-op paths do not trigger unnecessary reconciliation.
- Test ownership-state cleanup after external lock edits, removed target roots, replaced links, missing or corrupt state, broken symlinks, and isolation between recursively synchronized locks.
- Name test files after the implementation file they exercise.

## E2E-test policy

E2E tests are mandatory. Image setup, fixtures, command execution, and assertions live under `go/e2e/c-plugin/`; standalone E2E shell scripts are not used. The E2E package is excluded from `vp test` and `moon test` and is collected through its Vite+ workspace task.

```text
src/e2e/
└── Dockerfile

go/e2e/c-plugin/
├── e2e_test.go
├── scenario_helpers_test.go
├── *_test.go
└── vite.config.ts
```

There is no `moon.pkg` in `src/e2e/`, and E2E files do not use MoonBit test suffixes. The Go E2E package's Vite+ test task is collected by repository CI.

The runner contract is:

1. Before Go tests run, the Vite+ setup task runs the lightweight `c-plugin-e2e-image` Just recipe, which builds the caller-owned `c-plugin-e2e:local` image from the current repository context.
2. Inside the image, run `moon install` once and build the actual native c-plugin executable once.
3. The Go scenarios create JSON, repository, and filesystem fixtures through shared E2E helper functions. Testcontainers-required infrastructure commands are allowed only behind those helpers; scenarios do not dispatch shell scripts.
4. The Go package calls the shared `totto2727-org/e2e` library with the prebuilt local image, and the library runs every leaf-command scenario in a separate disposable Testcontainers container.
5. Never build or remove the image inside the shared library or a command test. The caller-owned image remains after the suite.

Every test container uses an isolated temporary `HOME`, working directory, cache root, and target directories. Global-mode cases therefore cannot affect the host user.

The historical GitHub E2E plan named `totto2727-org/monorepo` as a fixture source. This is not covered by the current eight local cases. Before introducing GitHub add/update coverage, select and verify a real fixture repository/commit that remains valid after the old product is removed. At least the future GitHub `add` and `update` scenarios must exercise the real bit-backed path. Other command tests may start from preconstructed canonical lock JSON and a reusable cached-repository fixture, as allowed by the test contract.

Each leaf-command Go scenario covers at least one successful flow and asserts filesystem state, lock JSON, command output, and exit status relevant to that command. The sync scenario must edit a previously materialized lock externally, verify stale owned links are removed, and verify replaced foreign paths are preserved. The update scenario must use two project locks that pin the same repository differently and verify that updating one lock does not change the other lock's cache or links. Interactive state is primarily unit-tested; E2E uses explicit non-interactive selection options so Docker runs are deterministic.

## Historical implementation milestones

The following original milestone IDs preserve design provenance. They are not the current migration stack, completion status, or instructions to restore v1 coexistence. The current independent migration uses [S0 through S18](../migration.md#feature-stage-map).

Historical Milestone 0 recorded the design contract, not product completion. Historical Milestones 1 through 7 used the following stable atomic-unit IDs. Commas in one wave are the only planned overlap; arrows are hard ordering constraints. The atomic unit `M1` belongs to Milestone 3 and is distinct from the Milestone 1 parent issue.

| Milestone                   | Atomic units                                                                                                                                                                                                                                       | Dependency and parallel waves                                                                             |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| 1. Bootstrap                | `B0` v1 coexistence identity/layout contract; `B1` prove native dependency compatibility and the exact `mizchi/bit` API, then create the CLI skeleton, help, and version; `B2` add the `c-plugin-v2` Nix package                                   | `B0 -> B1 -> B2`                                                                                          |
| 2. State foundation         | `F0` runtime paths; `F1` domain/lock model; `F2` lock codec; `F3` ownership codec; `F4` atomic stores; `F5` cache scope; `F6` discovery; `F7` runtime composition; `C-init` init; `E0` Docker/init E2E                                             | `F0,F1 -> F2,F3,F5,F6 -> F4,F7 -> C-init -> E0`                                                           |
| 3. Local lifecycle          | `M0` marketplace parsing; `M1` local/skill resolution; `R1-P` desired-link planning; `R1-FS` ownership-safe filesystem reconciliation; `C-sync`; `A1` `persist_and_sync`; `C-sync-r`; `C-add-local`; `C-remove`; `C-target-add`; `C-target-remove` | `M0,M1 -> R1-P -> R1-FS -> C-sync -> A1,C-sync-r -> C-add-local,C-target-add -> C-remove,C-target-remove` |
| 4. GitHub lifecycle         | `G0` frozen bit contract/adapter precondition; `G1` clone/checkout/HEAD; `G2` fetch/default branch; `G-add`; `G-update`; `G-update-r`; `G-cleanup`                                                                                                 | `G0 -> G1 -> G2 -> G-add,G-cleanup -> G-update -> G-update-r`                                             |
| 5. Interactive input        | `I1` selection state/TUI adapter; `I2` TTY policy; `I-add-kind`; `I-add-skill`; `I-remove`; `I-target-remove`                                                                                                                                      | `I1 -> I2 -> I-add-kind,I-add-skill,I-remove,I-target-remove`                                             |
| 6. Marketplace authoring    | `D0` common read model; `D1` format conversion; `D2` deterministic writes; `C-dev-sync`                                                                                                                                                            | `D0 -> D1 -> D2 -> C-dev-sync`                                                                            |
| 7. Final parity and cutover | `P1` full parity matrix; `P2` documentation/parity audit; `P3` cutover                                                                                                                                                                             | `P1 -> P2 -> explicit cutover approval -> P3`                                                             |

### Per-unit verification contract

Each atomic unit includes its behavior and tests in the same change. `B0` verifies the documented v1/v2 paths and identities, that v1 remains untouched, and that the two versions never share a lock scope. `B1` proves one native build with all exact pinned dependencies and the exact `mizchi/bit` APIs, then runs targeted check, format, parser tests, and native build and observes real `--help`/`--version`, including the Admiral name `c-plugin`. `B2` builds and evaluates the `c-plugin-v2` Nix package and verifies that its executable runs while the v1 package remains unchanged. `F0` and `F1` test constructors, normalization, rejection, and synthetic homes; `F2` tests canonical round trip, JSON paths, strict failures, unsupported-version byte preservation, and top-level dispatch; `F3` tests strict ownership-state round trip; `F4` tests exclusive create, temporary-sibling rename, and failures before and after persistence; `F5` tests full SHA-256 vectors, validated metadata construction and round trip, canonicalization, moved locks, and two-lock cache isolation; metadata mismatch rejection belongs to future cache storage adapter tests at the persisted-metadata consumption boundary. `F6` tests nearest project, exact global, ignored/recursive descendants, the home boundary, and `-g`/`-r`; `F7` proves all runtime boundaries are injected and no real user path is touched; `C-init` tests project/global success, existing-file byte preservation, invalid scope, and repetition; `E0` builds the image/executable once and asserts isolated project/global init status, output, lock JSON, and host state.

`M0` and `M1` use Claude/Cursor/Codex and local fixtures to test explicit kind/skill selection, duplicate identity, ordering, malformed manifests, and normalized paths. `R1-P` covers enabled-skill filtering, immutable desired ownership, canonical repository precedence, provenance, unavailable repositories, and normalized link paths without filesystem mutation. `R1-FS` covers missing, stale, foreign, replaced, and broken links; missing/corrupt ownership state; removed targets; partial failure; idempotence; and cross-lock isolation. `C-sync` and `C-sync-r` add unit flows and clean-container E2E, including an externally edited lock and ignored recursive descendants. `A1` proves every successful mutation synchronizes the exact persisted candidate while cancel/no-op neither writes nor syncs, and that post-write sync failure is recoverable. `C-add-local`, `C-remove`, `C-target-add`, and `C-target-remove` each add unit and separate clean-container E2E asserting relevant status/output, canonical lock, links/state, repetition or selection, cleanup, and foreign-path preservation.

`G0` consumes the exact APIs proved by `B1`, freezes the bit adapter contract, and tests its typed boundary and injected failure behavior without repeating dependency/API compatibility proof. `G1` and `G2` test scoped serialization, pins, fetch/default branch, partial failure, and two-lock isolation. `G-add` runs real bit-backed `totto2727-org/monorepo` unit/E2E and asserts lock, cache, links, output, and status. `G-update` and `G-update-r` add unit/E2E for pin advancement, local-source non-fetch, recursive/failure isolation, persisted synchronization, and unchanged sibling lock/cache/links. `G-cleanup` proves only the owning lock's final reference removes its cache, after link reconciliation.

`I1` and `I2` test choose, preselection, cancel, empty selection, TTY detection, and required non-interactive options. `I-add-kind`, `I-add-skill`, `I-remove`, and `I-target-remove` each test prompt-to-domain mapping and receive a real-TTY manual observation; non-TTY regression tests forbid implicit defaults and select-all. `D0` and `D1` fixture-test all formats, normalized Codex local sources, installation policy, malformed input, conversion, and ordering. `D2` temporary-root tests owned-output replacement and unrelated-file preservation. `C-dev-sync` adds unit plus one clean-container E2E per source kind for generated/copy/preserved files, output, and status. `P1` runs every targeted check/format/build/unit test and the completed isolated Docker cross-scope matrix. `P2` audits every acceptance criterion against executable evidence and updates both documents together. Only after explicit approval, `P3` switches the executable/Nix entry with rollback, reruns `P1` against the cutover surface, and proves v1/v2 never shared a lock scope; it does not migrate locks.

### Linear and native stack control plane

- Use one umbrella Linear issue plus seven parents for Milestones 1 through 7. Each milestone parent is sequentially `blockedBy` its predecessor.
- Create exactly one child for each active atomic unit. Do not pre-create future atomic issues; expand them just in time immediately before that milestone, after approval of its predecessor.
- One atomic unit equals one commit, one native stack layer, and one PR. Use `codex/cpv2-m<N>-<unit>-<slug>` branches and preserve base-to-tip order.
- Native GitHub stacked PR submission is a hard gate. Immediately before submission, recheck the REST API at version `2026-03-10` and the installed `gh` extension list. The currently observed `404` blocks submission.
- Never silently fall back to conventional dependent PR chains or call them native stacks. Never install `gh-stack` silently. Once supported, use only the official `gh stack` commands referenced below.
- Use team mode only for the comma-separated overlapping waves above, after shared contracts freeze, with an isolated worktree per worker. Arrows remain sequential.

### Milestone rules

- Do not begin a later milestone while the current milestone is incomplete or awaiting user review.
- Stop after every milestone and wait for explicit approval before implementing the next one.
- Keep each milestone as one coherent, reviewable change set. Do not pull future command stubs, unused abstractions, speculative compatibility code, or unrelated cleanup into an earlier milestone.
- Add unit tests with the production behavior they protect. Testing is not deferred to the final milestone.
- Add the Docker harness with Milestone 2 and add one E2E file whenever its leaf command first becomes available. Milestone 7 runs and audits the completed matrix rather than writing all E2E tests at once.
- Every milestone must keep all previously delivered milestones green.
- A dependency or upstream API incompatibility blocks only the active milestone. Record the evidence and revise this design before choosing a workaround.
- Do not claim full c-plugin parity until Milestone 7 passes, even when an intermediate command is usable.
- Stop after `P2`; `P1` and `P2` do not imply cutover approval, and `P3` starts only after explicit user approval.

### Milestone completion gate

A milestone is complete only when all of the following are true for its scope:

1. The documented behavior is implemented without future-facing placeholders.
2. Changed MoonBit packages pass targeted check, format, build, and unit-test commands.
3. Every leaf command introduced so far passes its clean-container E2E success case.
4. The real executable has been exercised through the user-facing command surface introduced by the milestone.
5. The milestone report is written and clearly separates completed behavior from deferred behavior.

### Milestone report format

Every milestone handoff reports:

- Milestone number and result.
- User-visible behavior now available.
- Files and architectural boundaries added or changed.
- Exact unit, build, and E2E commands with their results.
- Manual CLI observation performed against the built executable.
- Known limitations and intentionally deferred commands.
- Any dependency or upstream risk discovered.
- The proposed scope of the next milestone.

The report must state that work stopped at the milestone boundary. It must not describe deferred behavior as partially implemented or automatically continue into the next milestone.

## Planned full-parity acceptance criteria

- The command tree preserves `c-plugin skill` as the public skill-management namespace and exposes every documented leaf command with generated help and version output.
- Project, recursive, and `-g` scopes resolve exactly as documented.
- The global lock is `~/c-plugin-lock.json`, while global links remain under `~/.agents/skills`.
- Internal path values are `Path` except at explicit string boundaries.
- Repository caches are isolated by a full SHA-256 key derived from the normalized absolute owning lock path, and scope metadata prevents silent collision or cross-lock reuse.
- No Git subprocess is invoked; clone, fetch, checkout, and HEAD resolution use the `mizchi/bit` library.
- Lock JSON is strict, Lens-backed, canonical, and round-trips through `FromJson` and `ToJson`.
- Unsupported lock versions fail without mutation; automatic migration and a migration command are not part of the current implementation.
- Data-carrying enums dispatch once on their top-level `type` field.
- Existing directories and managed outputs are idempotent. Foreign paths are preserved unless explicit add force replaces an exact contained regular file or symlink; real directories, special paths, neighbors, and paths outside managed roots are never overwritten or deleted.
- Machine-local ownership state lets `sync` remove stale c-plugin links after external lock edits without deleting replaced or unowned paths.
- Every successful existing-lock mutation runs `sync` against the exact persisted value before returning.
- All restored interactive selections work in a real TTY and all corresponding non-interactive options are deterministic.
- Unit tests pass with all state isolated under temporary directories.
- The Docker E2E image builds once, every leaf test runs in a discarded container, and every successful flow passes against the real executable.

## Primary references

- MoonBit toolchain and `moon install`: https://docs.moonbitlang.com/en/latest/toolchain/moon/commands.html
- `moonbitlang/x/path.Path` public API: https://github.com/moonbitlang/x/blob/main/path/pkg.generated.mbti
- `totto2727/x@0.3.0/path` validated path values: https://mooncakes.io/docs/totto2727/x@0.3.0/path
- Admiral: https://github.com/totto2727/admiral
- mizchi/tui: https://github.com/mizchi/tui.mbt
- mizchi/bit: https://github.com/bit-vcs/bit
- GitHub REST repository path parameters: https://docs.github.com/en/rest/repos/contents
- NIST Secure Hash Standard (FIPS 180-4): https://csrc.nist.gov/pubs/fips/180-4/upd1/final
- MoonBit async filesystem API: https://github.com/moonbitlang/async/blob/main/src/fs/pkg.generated.mbti
- Lens: https://github.com/totto2727-org/monorepo/tree/main/mbt/package/lens
- target-file-discovery: https://github.com/totto2727-org/monorepo/tree/main/mbt/package/target-file-discovery
- GitHub stacked pull requests public preview: https://github.blog/changelog/2026-07-30-stacked-pull-requests-are-now-in-public-preview/
- GitHub stacked pull requests overview: https://docs.github.com/en/pull-requests/get-started/about-stacked-prs
- Official stacked PR CLI commands: https://docs.github.com/en/pull-requests/reference/stacked-prs-cli-commands
- GitHub REST pull-request stacks API (`2026-03-10`): https://docs.github.com/en/rest/pulls/stacks?apiVersion=2026-03-10
