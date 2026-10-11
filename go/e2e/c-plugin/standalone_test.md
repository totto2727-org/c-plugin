# Direct standalone skills and plugin enable sets

Source: [standalone_test.go](./standalone_test.go)

## `standaloneLifecycleScenario`

### Scope

Verify direct standalone registration, same-source idempotency without implicit synchronization, explicit synchronization, and bare-name removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project lock. |
| `c-plugin skill add` | Register a direct standalone skill root. |
| `c-plugin skill sync` | Restore an externally removed owned link. |
| `c-plugin skill remove` | Remove a bare standalone skill identity. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Resolve the skill root relative to the discovered lock. |
| `--skill solo` | Remove the standalone skill without a plugin qualifier. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-lifecycle/home` and `project=$HOME/project`.
`standalone/solo/SKILL.md` has valid matching YAML name solo and a nonempty description, without `plugin.json`.
The helper invokes `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write solo and run `c-plugin init` from the project, then create `project/nested`.
2. From `project/nested`, run `c-plugin skill add local:./standalone/solo` and inspect lock and link.
3. Save exact lock and ownership bytes, delete the managed solo link, and repeat `c-plugin skill add local:./standalone/solo` from the nested directory.
4. Check the successful no-op, exact persisted bytes, and still-missing link.
5. Run `c-plugin skill sync` from the project and verify the restored link.
6. Run `c-plugin skill remove --skill solo` from the nested directory and inspect empty state.

### Expected results

All invocations exit 0.
Add stdout contains `Added skill <project>/standalone/solo`.
The lock is version `3` with empty targets/plugins and `skills:[{name:"solo",source:"./standalone/solo"}]`.
The managed solo link resolves to the standalone root, and the source needs no plugin manifest.
Repeat stdout is exactly `No skill changes for <lock>\n`, lock and ownership bytes stay exact, and the deleted link remains absent until explicit sync.
Removal leaves the empty version `3` lock, ownership `{"version":"1","entries":[]}`, and no solo link.

### Notes

The nested working directory tests lock-relative source resolution, not working-directory-relative guessing.
The no-op intentionally has an incomplete filesystem to detect implicit synchronization.

## `standaloneGlobalScenario`

### Scope

Verify global standalone add and removal from a nested project directory preserve project state with the same skill name.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize independent scopes. |
| `c-plugin skill add` | Register project and global standalone roots. |
| `c-plugin skill remove` | Remove only the global registration. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Select global lock and managed roots. |
| `local:./standalone/solo` | Resolve each source relative to its selected scope. |
| `--skill solo` | Select the bare standalone name. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-global/home`.
Project and global roots each contain a separate valid `standalone/solo/SKILL.md` without a plugin manifest.
The CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Initialize the project with `c-plugin init` and the global lock with `c-plugin init --global` from the project.
2. Run `c-plugin skill add local:./standalone/solo` from the project and save exact project lock/ownership bytes.
3. Create `project/nested` and run `c-plugin skill add --global local:./standalone/solo` there.
4. Verify the global lock and source link, then run `c-plugin skill remove --global --skill solo` from the nested directory.
5. Inspect global cleanup and compare project bytes and link.

### Expected results

All invocations exit 0.
Global add persists only standalone solo at `./standalone/solo` and links to `$HOME/standalone/solo`.
Global removal leaves the global lock empty and its solo link absent.
Project lock and ownership bytes remain exact, and project solo still resolves to its own source.

### Notes

The same skill basename in two scopes does not authorize cross-scope mutation.

## `explicitRootScenario`

### Scope

Verify neither standalone add nor plugin add guesses a child root when the caller supplies a parent directory.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Reject a parent without direct `SKILL.md`. |
| `c-plugin plugin add` | Reject a parent without direct `plugin.json`. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone` | Select the parent of valid solo rather than solo itself. |
| `local:./plugins` | Select the parent of a valid plugin rather than its root. |
| `--all` | Explicitly select plugin skills, isolating direct-root discovery. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-explicit-root/home`.
Valid solo exists at `standalone/solo/SKILL.md`, and valid demo with alpha exists at `plugins/plugin/plugin.json` and its skills directory.
Neither selected parent contains the required direct marker.
Initial lock bytes are saved; the CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Write solo, run `c-plugin init`, and write the nested demo plugin.
2. Save the project lock bytes.
3. Run `c-plugin skill add local:./standalone` from the project.
4. Run `c-plugin plugin add local:./plugins --all` from the project.
5. After each rejection, inspect exact lock bytes and absent ownership/links.

### Expected results

Both attempts exit nonzero.
Lock bytes stay exact, ownership is absent, and neither solo nor alpha is linked.

### Notes

The command family shares the same explicit-root boundary contract.
No collection scan, fallback, or recursive guess is permitted.

## `standaloneDuplicateScenario`

### Scope

Verify the same standalone name cannot silently switch to a different source root.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Register solo, then reject a different source with the same name. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Register the original source. |
| `local:./other/solo` | Attempt a different valid source for solo. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-duplicate/home`.
Both source directories contain valid matching solo frontmatter.
The original solo is linked and owned before exact lock and ownership bytes are captured.
The CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Write solo, run `c-plugin init`, and run `c-plugin skill add local:./standalone/solo` from the project.
2. Write `other/solo/SKILL.md` and capture persisted bytes.
3. Run `c-plugin skill add local:./other/solo`.
4. Compare exact bytes and the existing link target.

### Expected results

The second add exits nonzero.
Lock and ownership bytes remain exact, and the existing solo link still resolves to `standalone/solo`.

### Notes

This is a source-identity conflict, not an invalid skill fixture or a same-source no-op.

## `standaloneUnavailableScenario`

### Scope

Verify synchronization preserves a trusted owned standalone link when its registered source becomes unavailable.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Register and own the standalone link. |
| `c-plugin skill sync` | Reconcile after source loss. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Register the direct source root. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-unavailable/home`.
Valid solo is registered and linked before its source directory is removed externally.
Exact lock and ownership bytes and the literal managed symlink target are saved.
The CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Run `c-plugin init` and `c-plugin skill add local:./standalone/solo` from the project.
2. Save lock/ownership bytes and inspect the literal link with `readlink`.
3. Remove `standalone/solo` and run `c-plugin skill sync`.
4. Compare exact persisted bytes and literal link identity while checking the path remains a symlink.

### Expected results

Sync exits 0 with stdout containing `partial`.
Lock and ownership bytes remain exact.
The dangling managed link is retained as a symlink with the same literal target.

### Notes

The scenario uses `test -L` and `readlink`, not a successful `realpath`, because the source is deliberately unavailable.

## `standaloneInvalidScenario`

### Scope

Verify invalid standalone frontmatter rejects registration before any mutation and preserves foreign managed-root content.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Reject missing required description. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Select the invalid direct skill root. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-invalid/home`.
Solo's frontmatter contains `name: solo` but no description.
A foreign managed-root file contains `foreign\n`, and initial lock bytes are saved.
The CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Write solo and run `c-plugin init` from the project.
2. Replace its marker with invalid frontmatter, write foreign content, and save lock bytes.
3. Run `c-plugin skill add local:./standalone/solo`.
4. Inspect failure, exact lock bytes, absent ownership/link, and foreign contents.

### Expected results

Exit is nonzero.
Lock bytes remain exact, ownership and solo link are absent, and foreign content stays exactly `foreign\n`.

### Notes

The missing description is a concrete Agent Skills frontmatter violation.

## `standaloneEscapeScenario`

### Scope

Verify a physically escaping standalone marker symlink is rejected without changing its outside target.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Reject an escaping direct marker. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./standalone/solo` | Select the root containing the escaped marker. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-escape/home`.
`standalone/solo/SKILL.md` symlinks to valid `$HOME/outside/SKILL.md`, physically outside the direct skill root.
The outside marker digest and initial lock bytes are saved.
The CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Write solo and run `c-plugin init` from the project.
2. Write the outside marker, save its digest, and replace solo's marker with the escaping symlink.
3. Save lock bytes and run `c-plugin skill add local:./standalone/solo`.
4. Inspect rejection, exact lock bytes, outside digest, retained marker symlink, and absent state/link.

### Expected results

Exit is nonzero.
Lock bytes and outside digest are unchanged; the escaped marker link remains intact.
Ownership and the managed solo link remain absent.

### Notes

The assertion verifies physical containment and preservation rather than only lexical path checks.

## `standalonePluginConflictScenario`

### Scope

Verify a standalone skill cannot claim a basename already enabled by a plugin.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin plugin add` | Register demo's alpha. |
| `c-plugin skill add` | Reject standalone alpha's conflicting basename. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin` | Select demo's direct plugin root. |
| `--all` | Enable plugin alpha explicitly. |
| `local:./standalone/alpha` | Select a valid but conflicting standalone root. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standalone-plugin-conflict/home`.
Demo has valid alpha, and the standalone alpha has valid matching frontmatter.
Plugin alpha is registered and owned before exact persisted bytes are saved.
The CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Initialize the project, write demo, and run `c-plugin plugin add local:./plugin --all`.
2. Write standalone alpha and save exact lock and ownership bytes.
3. Run `c-plugin skill add local:./standalone/alpha`.
4. Compare persisted bytes and the original alpha link target.

### Expected results

Standalone add exits nonzero.
Lock and ownership bytes stay exact, and alpha continues to resolve to demo's plugin skill directory.

### Notes

The existing enabled plugin skill determines the basename conflict, not a foreign file or invalid source.

## `pluginEnabledSetScenario`

### Scope

Verify same-source plugin registration replaces its enabled set, preserves an empty registration, supports re-enabling, and rejects conflicting selector modes without mutation.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project lock. |
| `c-plugin plugin add` | Replace or repeat the plugin enabled set. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin` | Select the same direct demo root each time. |
| `--all` | Enable all discovered skills. |
| `--skill beta` | Replace the enabled set with beta only. |
| `--none` | Disable all skills while retaining the plugin. |
| `--skill alpha` | Supply a conflicting selector in rejection checks. |

### Preconditions and fixtures

A fresh container uses `HOME=/tmp/c-plugin-standard-enabled-set/home` with canonical demo alpha and beta.
The CLI is `/sandbox/.local/bin/c-plugin` with isolated HOME.

### Execution flow

1. Run `c-plugin init` and `c-plugin plugin add local:./plugin --all` from the project.
2. Run `c-plugin plugin add local:./plugin --skill beta` and inspect beta-only state.
3. Run `c-plugin plugin add local:./plugin --none` and inspect an empty enabled set with the registration retained.
4. Save exact lock and ownership bytes and repeat `c-plugin plugin add local:./plugin --none`.
5. Compare no-op output and exact persisted bytes.
6. Run `c-plugin plugin add local:./plugin --all` and verify both links are restored.
7. Save persisted bytes, then run `c-plugin plugin add local:./plugin --all --skill alpha`, `c-plugin plugin add local:./plugin --all --none`, and `c-plugin plugin add local:./plugin --none --skill alpha`.
8. After each selector conflict, compare exact bytes and both retained links.

### Expected results

Enabled-set updates and repeat exit 0.
Beta-only state removes alpha and keeps beta linked.
`--none` retains demo with skills `[]`, removes beta, and leaves empty ownership.
Repeating `--none` prints exactly `No skill changes for <lock>\n` and changes no bytes.
`--all` restores both skill links and the full enabled set.
All three conflicting selector combinations exit nonzero and preserve exact lock/ownership bytes and both links.

### Notes

This ordered workflow verifies replacement semantics rather than an additive merge.
The selector-conflict family shares one mutually exclusive mode contract.
