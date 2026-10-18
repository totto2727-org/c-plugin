# Standalone skills and plugin enabled sets

Source: [StandaloneSpec.hs](./StandaloneSpec.hs)

Every named Hspec example owns a fresh `c-plugin-e2e:local` container through `Test.CLI.E2E.withEnvironment`.
The examples use `parallel`, with concurrency controlled by the suite's two Hspec jobs.
The executable is `/sandbox/.local/bin/c-plugin` and each CLI command receives a synthetic HOME.
The shared `standaloneFixture` initializes `project=$HOME/project`, writes valid standalone solo SKILL.md, and runs `c-plugin init`.
It is not an additional registered case.
The standard fixture has a matching YAML name and a nonempty description but no plugin.json.
All exact lock and ownership comparisons preserve bytes, JSON assertions preserve structural equality, and digest assertions use SHA-256.

## `standaloneLifecycle` (`standalone_lifecycle`)

### Scope

Verify direct registration, no-op behavior without synchronization, explicit sync, and bare-name removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Register a direct standalone root. |
| `c-plugin sync` | Restore an externally deleted link. |
| `c-plugin skill remove` | Remove the standalone identity. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Resolve relative to the discovered lock. |
| `--skill solo` | Select the standalone removal domain. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-lifecycle/home` and create project/nested.

### Execution flow

1. From nested, run `skill add local:./standalone/solo`.
2. Check add output, complete solo lock JSON, managed link, ownership identity, and absent source plugin.json.
3. Save lock and state bytes, delete the managed link, and repeat `skill add local:./standalone/solo` from nested.
4. Check exact no-op output and bytes and verify the link remains missing.
5. Run `sync` from project and inspect the restored link.
6. From nested, run `skill remove --skill solo` and inspect empty lock, ownership, and missing link.

### Expected results

All commands succeed.
Add stdout contains `Added skill <project>/standalone/solo`.
The lock contains only solo with installedSkillName solo, installedSkillSource standalone/solo, and null installedSkillOrigin, plus empty targets and plugins.
The link resolves to project/standalone/solo.
Ownership includes solo in a valid StandaloneSource tuple.
Repeat stdout is exactly `No skill changes for <project>/c-plugin-lock.json\n` and does not restore the missing link.
Removal leaves the empty lock, `{"ownershipEntries":{}}`, and no solo link.

### Notes

The nested working directory verifies lock-relative resolution.

## `standaloneGlobal` (`standalone_global`)

### Scope

Keep global and project standalone identities isolated during add and removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize independent global state. |
| `c-plugin skill add` | Register each scope's solo source. |
| `c-plugin skill remove` | Remove global solo only. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Resolve against HOME. |
| `local:./standalone/solo` | Select each scope's explicit source. |
| `--skill solo` | Select standalone removal. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-global/home`.
Write separate valid solo roots below HOME and project.

### Execution flow

1. Run `init --global`, then `skill add local:./standalone/solo` from project.
2. Save project lock and ownership bytes and create nested.
3. From nested, run `skill add --global local:./standalone/solo`.
4. Verify global solo lock and HOME-relative link.
5. From nested, run `skill remove --global --skill solo`.
6. Check global cleanup and project preservation.

### Expected results

All commands succeed.
Global removal leaves an empty global lock and no global solo link.
Project lock and state bytes remain exact, with the project solo link pointing to its own source.

### Notes

Both scopes intentionally use the same name.

## `explicitRoot` (`explicit_root`)

### Scope

Reject collection directories instead of scanning descendants or inferring a source root.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Reject a parent standalone collection. |
| `c-plugin plugin add` | Reject a parent plugin collection. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone` | Select a parent without its own SKILL.md. |
| `local:./plugins`, `--all` | Select a parent containing a plugin child. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-explicit-root/home`.
Write valid solo under standalone/solo and demo alpha under plugins/plugin.
Save the initialized lock bytes.

### Execution flow

1. Run `skill add local:./standalone`.
2. Run `plugin add local:./plugins --all`.
3. After each command, inspect lock, ownership, and both potential managed links.

### Expected results

Both commands fail.
Lock bytes remain exact and ownership, solo link, and alpha link remain absent after each rejection.

### Notes

Only an explicit standard plugin root or standalone skill root is accepted.

## `standaloneDuplicate` (`standalone_duplicate`)

### Scope

Reject the same standalone name from a different source.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Register solo and reject a competing source. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Register the original source. |
| `local:./other/solo` | Attempt a different source with the same name. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-duplicate/home`.
Both roots contain valid solo manifests.

### Execution flow

1. Run `skill add local:./standalone/solo` successfully.
2. Write other/solo and save exact lock and ownership bytes.
3. Run `skill add local:./other/solo`.
4. Compare state and original link.

### Expected results

The duplicate add fails without changing either saved file or the original managed link.

### Notes

The original source identity is retained rather than replaced.

## `standaloneUnavailable` (`standalone_unavailable`)

### Scope

Preserve ownership and exact dangling-link identity when a source disappears.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Create standalone ownership. |
| `c-plugin sync` | Report partial reconciliation for missing source content. |
| `readlink` | Compare literal symlink target bytes. |
| `test` | Verify the dangling path remains a link. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Select the source that will disappear. |
| `-L` | Check link existence without following its target. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-unavailable/home`.

### Execution flow

1. Run `skill add local:./standalone/solo`, save lock and ownership bytes, and record successful `readlink <solo-link>` output.
2. Delete the source directory and run `sync`.
3. Check partial output, exact saved files, successful `test -L <solo-link>`, and successful repeated readlink output.

### Expected results

Add and sync succeed.
Sync stdout contains partial.
Lock and ownership bytes remain exact, the dangling symlink remains present, and its literal target stdout is unchanged.

### Notes

Canonical resolution is deliberately not used for the dangling-link identity assertion.

## `standaloneInvalid` (`standalone_invalid`)

### Scope

Reject an invalid skill manifest without changing unrelated managed-root files.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Validate the standalone manifest boundary. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Select the invalid source. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-invalid/home`.
Replace SKILL.md with exact bytes `---\nname: solo\n---\n`, omitting the required description.
Write managed-root foreign file bytes `foreign\n` and save the initialized lock.

### Execution flow

1. Run `skill add local:./standalone/solo`.
2. Inspect lock, ownership, solo link, and foreign file.

### Expected results

Add fails, preserves exact lock and foreign bytes, and creates neither ownership state nor solo link.

### Notes

The rejection must happen before managed-path mutations.

## `standaloneEscape` (`standalone_escape`)

### Scope

Reject a SKILL.md symlink that escapes the explicit source root.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Enforce physical containment. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Select the root containing an escaping manifest. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-escape/home`.
Write HOME/outside/SKILL.md with valid solo content and record its SHA-256.
Replace the source SKILL.md with a symlink to that outside file and save the initialized lock bytes.

### Execution flow

1. Run `skill add local:./standalone/solo`.
2. Compare exact lock bytes and outside checksum.
3. Verify the manifest symlink still resolves to the outside file and ownership and managed solo remain absent.

### Expected results

Add fails without modifying outside data, lock, source symlink, or managed state.

### Notes

The outside fixture remains within the synthetic HOME, not real user state.

## `standalonePluginConflict` (`standalone_plugin_conflict`)

### Scope

Reject a standalone identity that conflicts with an enabled plugin skill.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Register plugin demo alpha. |
| `c-plugin skill add` | Reject standalone alpha. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Enable plugin alpha. |
| `local:./standalone/alpha` | Attempt the conflicting standalone identity. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-standalone-plugin-conflict/home`.
Write a demo plugin with valid alpha and a valid standalone alpha source.

### Execution flow

1. Run `plugin add local:./plugin --all`.
2. Write standalone alpha and save exact lock and ownership bytes.
3. Run `skill add local:./standalone/alpha`.
4. Compare saved bytes and plugin alpha link.

### Expected results

Plugin add succeeds and standalone add fails.
The original files and plugin alpha link remain unchanged.

### Notes

A conflict cannot silently transfer ownership between domains.

## `pluginEnabledSet` (`plugin_enabled_set`)

### Scope

Replace a registered plugin enabled set without losing registration and reject all incompatible selectors.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Replace the enabled set or report a semantic no-op. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin` | Keep the same explicit source identity. |
| `--all`, `--skill beta`, `--none` | Enable all, select beta only, or disable all. |
| Conflicting selector pairs | Reject mixed selection modes. |

### Preconditions and fixtures

The standard environment named enabled-set contains demo alpha and beta and an initialized project lock.

### Execution flow

1. Run `plugin add local:./plugin --all`, then `plugin add local:./plugin --skill beta`.
2. Assert complete beta-only lock JSON, absent alpha, and the beta plugin link.
3. Run `plugin add local:./plugin --none` and assert the retained plugin registration with an empty enabled set, empty ownershipEntries, and absent beta.
4. Save exact lock and state bytes and repeat `plugin add local:./plugin --none`.
5. Assert successful exact no-op output and unchanged bytes.
6. Run `plugin add local:./plugin --all` and inspect complete all-enabled lock JSON and both links.
7. Save lock and state again, then run `plugin add local:./plugin --all --skill alpha`, `plugin add local:./plugin --all --none`, and `plugin add local:./plugin --none --skill alpha` in that order.
8. After each rejection, verify exact lock and state bytes and both original links.

### Expected results

All valid adds succeed and all three conflicting-selector adds fail.
Disabling the final skill preserves demo registration.
The repeated none selection prints exactly `No skill changes for <project>/c-plugin-lock.json\n`.
No semantic no-op or rejected selection changes persisted bytes.

### Notes

This case changes desired enabled sets through source add, not the registered-plugin toggle command.
