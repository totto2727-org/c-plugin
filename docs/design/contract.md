# Design contract

This contract is for contributors who change c-plugin.
The [CLI reference](../cli.md) owns user-facing command details.
The [Japanese translation](contract.ja.md) has the same scope and requirements.

## Scope

c-plugin is a skills-only installer for local and pinned GitHub sources in the Agent Plugins 1.0 package format.
It uses Haskell, Cabal, Iris, and a pinned Nix environment.
It does not manage marketplaces, vendor-specific packages, non-GitHub remotes, MCP servers, or hooks.
Do not treat those exclusions as future command placeholders.

## Module ownership

Keep a domain type, its pure validation, and its wire-format conversion in the same module.
`CPlugin.Types` only re-exports the type modules.
Do not define orphan JSON instances in filesystem or command modules.

| Module | Owned rules |
| --- | --- |
| `CPlugin.Types.Source` | Mandatory local/GitHub source schemes and pure parsing into typed source values |
| `CPlugin.Types.GitHub` | GitHub repository, ref, subpath, commit, and origin values, validation, and JSON conversion |
| `CPlugin.Types.Path` | Relative and absolute path values, validation, and JSON conversion |
| `CPlugin.Types.Name` | Item names and plugin/skill name validation, with JSON conversion |
| `CPlugin.Types.Plugin` | Installed plugin selections, validation, and JSON conversion |
| `CPlugin.Types.InstalledSkill` | Standalone skill registration, validation, and JSON conversion |
| `CPlugin.Types.Lock` | Desired lock shape, uniqueness, derived JSON, and boundary validation |
| `CPlugin.Types.Ownership` | Related ownership records, relationship validation, and JSON conversion |
| `CPlugin.Types.PluginManifest` | Standard plugin manifest type, decoding, and validation |
| `CPlugin.Types.Skill` | Discovered skill type and frontmatter decoding/validation |
| `CPlugin.Types.Sync` | Synchronization results and notices |
| `CPlugin.Types.Selection` | Selection requests, typed results, and line-response validation |

Keep Iris CLI parsing and interactive-mode detection in `hs/app/Main.hs`.
`CPlugin.Interaction` adapts typed choices to terminal handles; handlers consume typed selection results before constructing a candidate.
`CPlugin.StateStore` owns file IO, canonical JSON rendering, and durable atomic writes.
It does not define type-specific wire rules.
Keep discovery in `CPlugin.Plugin`, filesystem containment in `CPlugin.Paths`, and reconciliation in `CPlugin.Reconcile`.
`CPlugin.Commands` only dispatches command values to per-operation handler modules.
List rendering and related plugin/skill mutations can use small shared helpers.
`CPlugin.Commands.Common` owns shared lock loading, candidate persistence, and completion reporting.
`syncLoadedLock` only orchestrates a plan and reconciliation session.
`CPlugin.Reconcile.Plan` resolves sources and desired links, `Session` owns notices and durable checkpoints, `Mutation` owns named link operations, and `Report` owns user-facing result text.
Keep mutation/checkpoint order and exception scopes intact when moving these steps.
Native specs are separate modules by responsibility, with shared isolated fixtures in `CPlugin.TestSupport`.

## Input boundaries

Use validated path and identity values after parsing CLI strings, JSON, and filesystem input.
Resolve local sources and additional targets against the owning lock root.
Reject parent traversal and physical containment escapes.
Output roots and their ancestors must be physical directories inside the lock root, not symlink redirects.

`plugin add` accepts one explicit plugin root, while `skill add` accepts one explicit standalone skill directory.
Require a single `local:./PATH` or `github:OWNER/REPO[/PATH]` source argument; reject missing prefixes, multiple sources, deprecated source flags, and local sources combined with `--ref`.
Do not infer source kinds, reconstruct missing data, or fall back to another path.
Do not search a parent collection, infer the input kind, or accept a list of roots.
Require `plugin.json` directly in a plugin root and `SKILL.md` directly in a standalone root.
Keep sources inside their owning lock root after physical resolution.
The standard manifest has no skill-list field; use only the fixed `skills/` child location for plugin skills.

Apply the locally supported Agent Plugins 1.0 manifest rules:

- Require `plugin.json` at the plugin root and the exact supported `$schema` identifier.
- Validate required names and permitted metadata types. Do not add URL, email, SPDX, or semantic-version constraints where the specification requires only strings.
- Report and ignore unknown top-level manifest fields.
- Treat a non-object `extensions` field as a non-fatal ignored field.
- Reject other manifest violations before discovering skills.
- Do not retrieve schemas at runtime or fall back to vendor formats.

Discover skills only from immediate child directories of `skills/`.
Each `SKILL.md` must resolve to a regular file within the resolved plugin root.
Validate its frontmatter against the Agent Skills format, including directory/name agreement.
Report invalid skills and skip them without disabling valid siblings.
Reject an explicitly selected unavailable skill.
Ignore unsupported component types without executing their content.
This contract does not establish a complete conformance certification.

## Interactive boundary

[Iris 0.1.0.0](https://hackage.haskell.org/package/iris-0.1.0.0) provides `cliEnvInteractiveMode` and the global `--no-input` option.
Its [interactive module](https://hackage.haskell.org/package/iris-0.1.0.0/docs/Iris-Cli-Interactive.html) detects terminal input; it does not provide selection widgets.
Use that mode with a terminal check for the prompt output handle.
The terminal adapter uses [Brick](https://hackage.haskell.org/package/brick) with Vty input on stdin and screen output on stderr.
Bracket terminal setup and shutdown so completion, cancellation, and asynchronous interruption restore terminal state.

Keep selection types and response validation in `CPlugin.Types.Selection`.
Keep input/output effects in `CPlugin.Interaction` and command policy in each handler.
Pass typed plugin/skill and target values through selection; do not reconstruct identities from display labels.
Keep the deterministic line-based handle adapter for non-terminal test inputs; the CLI still rejects missing selectors outside a terminal.

Missing selectors in interactive mode request a choice for plugin configuration, remove, and target removal.
Standalone skill add already identifies one complete item by its path and does not need a selection prompt.
Explicit options bypass prompts.
Non-interactive mode requires explicit selectors, or `--all` or `--none` for plugin configuration, and must not consume pipe input or silently select everything.
Up/Down move focus, Space toggles an item, and Enter confirms the selected set.
The selection starts empty; `a` selects all and `n` clears it.
Selecting multiple plugins where exactly one is required repeats the prompt before any candidate write.
Esc, `q`, and Ctrl-D cancel without writing configuration or running synchronization.
For plugin configuration, a confirmed empty set or `--none` disables all skills while retaining the plugin.
An unchanged enabled set is a semantic no-op; a changed set replaces the previous set.
Empty removal selections do not mutate state.
Do not catch asynchronous interruption as an ordinary selection error.
No installed skill is preselected for removal.

## Operation boundaries

Keep `target`, `sync`, and `update` at the top level.
Plugin removal offers whole plugins only; skill removal offers enabled plugin skills and standalone skills only.
Removing or disabling the final plugin skill retains its plugin registration.
Registered-plugin skill enable/disable adds or subtracts selected available names without replacing source identity or fetching GitHub refs.
Validate the registered source and complete candidate before saving a changed enabled set.
Cancellation and semantic no-ops do not save or reconcile.

The three list commands read the selected lock without source loading, cache verification, network access, state writes, or reconciliation.
Include disabled plugin registrations in plugin lists, and include only enabled plugin skills and standalone registrations in skill lists.
Missing or corrupt locks remain errors; unavailable sources or missing links do not change list behavior.

## State

The desired lock is `c-plugin-lock.json`:

```json
{
  "targets": [],
  "plugins": {
    "demo": {"pluginName": "demo", "pluginSource": "plugins/demo", "enabledSkills": ["alpha"], "pluginOrigin": null}
  },
  "standaloneSkills": {}
}
```

Use stock Generic-derived JSON instances for records and sums, and newtype-derived instances for primitive string/path values and map keys.
Do not customize field names, constructor tags, or optional-field encoding.
Keep validation separate from structural decoding, next to each type, and call validated decoders at persistence and cache boundaries.
Check map keys against their records before rebuilding validated domain values.
The `standaloneSkills` map stores records with `installedSkillName`, `installedSkillSource`, and `installedSkillOrigin` fields.
Plugin and standalone origins use `githubOriginRepository`, `githubOriginRef`, `githubOriginSubpath`, and `githubOriginCommit`.
Validate repository/ref/subpath and the full commit ID before deriving the cache path, and require that path to match the record's source.
Local records encode their origin as `null`.
Cache provenance stores only the repository and commit, because different requested refs and subpaths can share one immutable snapshot.
Validate standalone name/source uniqueness and reject a standalone name that collides with an enabled plugin skill.
Do not provide legacy wire conversion or fallback parsing.
Reject duplicate sources, plugin identities, selected skills, and target entries.
Encode normalized relative paths and deterministic ordering.
Keep project and global locks independent.

Machine-local ownership state is `.agents/c-plugin-state.json`, with an `ownershipEntries` map keyed by absolute link path.
It is not portable desired configuration.
Each entry records the absolute link path, managed root, exact literal symlink target, resolved target, and source/plugin/skill identity.
The literal target must round-trip unchanged, separately from the resolved path.
The `entrySource` sum uses Aeson's default `tag` and `contents` fields for `OwnershipSource` or `StandaloneSource`.
External Agent Plugins manifests and Agent Skills frontmatter keep their standard format and validation.

## Persistence and reconciliation

`init` creates a new lock exclusively and does not synchronize links.
For a changed existing lock:

1. Resolve and validate the complete candidate.
2. Save the lock through a temporary sibling file and atomic rename.
3. Reconcile exactly that persisted candidate.

Rejected candidates and add/configuration semantic no-ops do not rewrite the lock or trigger reconciliation.
Explicit `sync` reconciles both source kinds from pinned state without network access.
Explicit `update` refreshes all remote plugin and standalone sources, validates the whole per-lock candidate before persistence, and reconciles even when the candidate is unchanged.
An unchanged update does not rewrite the lock.
Refresh failure must not partially persist one source before another source validates.
Ordinary collisions and unavailable plugins can produce partial success.
A terminal checkpoint, durability, or verification failure returns failure without pretending that the lock was rolled back.
A later sync can retry the persisted desired state.

For each link mutation:

1. Check physical containment and ownership or explicit force eligibility.
2. Perform only the exact authorized mutation.
3. Verify a new link before recording ownership.
4. Save an ownership checkpoint before the next mutation.

Stop on checkpoint failure.
Atomic replacement does not eliminate the crash window between a filesystem mutation and its ownership checkpoint.
Do not promise automatic recovery or ownership adoption across that window.

## Concurrent IO

Independent repository and filesystem IO runs concurrently through ordered worker pools with at most eight workers per traversal.
A process-wide eight-slot gate bounds active Git processes and skill, lock, and ignore-file reads, including nested traversals.
Only leaf effects hold a slot; an operation must not hold a slot while it waits for child work.
Worker failure or asynchronous interruption cancels and joins its dependent workers before control returns.

`update` fetches each repository and requested ref once per lock, sharing the verified snapshot across plugin and standalone subpaths.
Offline planning verifies each repository and pinned commit once per lock, then validates each selected subpath separately.
Invalid snapshot contents make its selections unavailable; an invalid subpath does not make valid siblings unavailable.
Concurrent publishers can reuse only an existing, fully verified snapshot with the exact repository and commit.
They never remove an existing cache entry.

Recursive commands prepare and apply locks with disjoint root directories concurrently.
Ancestor and descendant roots execute in discovery order, including their reads: an ancestor can change a descendant's selected source or target.
Within each lock, link mutations and their ownership checkpoints remain sequential.
Reporting and collision resolution retain deterministic discovery and identity order, not completion order.
An ordinary failure does not interrupt another independent lock halfway through its checkpoints.
All locks in the current disjoint wave finish, including work queued behind the worker limit, before the first failure is reported.
No later wave starts after that failure.
There is no cross-lock transaction or rollback guarantee.

## Safety rules

- Delete or replace an owned link only when its filesystem kind, literal target, resolved target, and containment still match its record.
- Preserve replaced paths and report ownership loss.
- Missing or corrupt ownership state never authorizes cleanup or adoption of existing paths.
- Do not adopt an existing unrecorded link merely because it points to the desired destination.
- Explicit add force may replace only the exact contained regular file or symlink collision.
- Limit add force to the selected source identities across managed targets; other registrations receive ordinary reconciliation without force.
- Never delete a real directory, special file, neighboring path, or path outside a managed root.
- Keep stale owned entries for removed target roots available for safe cleanup.
- Preserve links for unavailable plugin sources rather than deleting them because resolution failed.
- Keep recursive lock ownership isolated and do not follow symlink directories during discovery.

These checks reduce accidental scope escape. They are not a sandbox against a concurrent hostile filesystem writer.

## GitHub transport

`CPlugin.Source.GitHub` owns argv-based Git invocation, isolated staging directories, immutable snapshots, and pinned verification.
Disable interactive authentication, hooks, submodule recursion, and non-HTTPS protocols.
Reject installed URL rewrites and HTTP redirects away from the fixed GitHub endpoint.
Use normal installed credentials only for network operations; isolate Git configuration during checkout and offline verification.
Validate physical cache directories, provenance, remote URL, HEAD, Git metadata indirections, tracked content hashes, and contained tracked symlinks.
Do not adopt, overwrite, or delete an existing corrupt cache entry.
Cleanup is restricted to staging directories created by the current fetch.
Caches are implementation-owned inputs, not descendant projects for `-r`.
These checks are not a concurrent hostile-writer sandbox.

The backend decision is documented in [Git transport](git-transport.md).

## Toolchain

Keep GHC 9.4.8 and Iris 0.1 within their published dependency bounds.
Do not substitute dependency probes for product tests.

## Validation

Native tests must use isolated temporary roots and exercise real product boundaries.
Cover response parsing, typed selection mapping, cancellation, byte-preserving no-ops, explicit-root rejection, standalone installation, plugin enabled-set replacement, and non-interactive rejection.
Run actual CLI selection, retry, cancellation, and interruption through a pseudo-terminal in the Haskell Hspec/Caseyard suite.
Assert terminal detection, exit status, exact state preservation, and final link state rather than only prompt text.
Hspec scenarios use the public Caseyard API with a caller-built image and isolated container state per example.
Build the shared image once before the suite, not inside individual examples.
Hspec owns scheduling through `parallel` and `--jobs=2`.
Keep the E2E host compiler in its separate `hs/e2e` Cabal project; it does not change the GHC 9.4 product build.
Check source-linked scenario documents against the actual Haskell modules.
Validate the ordinary Cabal build and native tests, and report real Docker E2E separately.
Independent Nix package builds are optional, not required by `just ci`.
Documentation examples describe expected behavior, not evidence that a test passed.

## Sources

- [Agent Plugins 1.0 specification](https://agent-plugins.org/specification)
- [Plugin manifest schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)
- [Agent Skills specification](https://agentskills.io/specification)
- [Iris package](https://hackage.haskell.org/package/iris)
