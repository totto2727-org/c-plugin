# Core CLI E2E scenarios

Source: [CoreSpec.hs](./CoreSpec.hs).
Each scenario installs the trusted driver from host `C_PLUGIN_E2E_DRIVER` once through `newScenario`; physical file-byte assertions use public snapshots.
The module contains 18 Hspec examples.
Every example calls `withEnvironment "c-plugin-e2e:local"` and receives its own disposable container.
The module uses `parallel`, and the caller limits Hspec to `--jobs=2`.
No example builds an image.
`c-plugin` below denotes `/sandbox/.local/bin/c-plugin`, with explicit argv and synthetic `HOME`.
JSON comparisons use Aeson values, file assertions use exact bytes, and digest assertions use SHA-256.
Symbolic-link checks require a link and its canonical `realpath` target.
These descriptions are assertion contracts, not claims of a successful Docker run.

## `error_help`

### Scope

Keep contextual parser help and reject incomplete invocations without mutation.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin` | Root help and missing command. |
| `c-plugin plugin` | Plugin help and missing command. |
| `c-plugin skill` | Skill help and missing command. |
| `c-plugin target` | Target help and missing command. |
| `c-plugin plugin add` | Missing source or option value. |
| `c-plugin skill add` | Missing source. |
| `c-plugin target add` | Missing path. |
| `c-plugin init` | Establish an unchanged lock. |

### Arguments and options

`--help` selects the relevant help text.
`--ref` and `--skill` are deliberately supplied without values.

### Preconditions and fixtures

Use `/tmp/c-plugin-error-help-e2e/home/project` and its synthetic home.
Initialize the project lock and record its checksum.

### Execution flow

1. Run `c-plugin init`.
2. For each ordered argv below, first run its command-context help with `--help`.
3. Run `[]`, `[plugin]`, `[skill]`, `[target]`, `[plugin, add]`, `[skill, add]`, `[target, add]`, `[plugin, add, github:owner/repo, --ref]`, and `[plugin, add, local:./plugin, --skill]`.
4. Compare each stderr to both the expected diagnostic and the complete captured help stdout.

### Expected results

All help commands succeed and contain `Available options:`.
Each incomplete invocation exits 1.
The first four diagnostics contain `Missing: COMMAND`, the next two contain `Missing:`, and target add contains `Missing: PATH`.
Missing option values report `The option ` followed by the quoted option name and ` expects an argument.`.
The lock checksum stays unchanged after every invalid invocation.
The home lock and project/home `.agents` remain absent.

### Notes

The nine parser rows are assertions inside one registered example, not nine extra examples.

## `init_project`

### Scope

Create a project lock exclusively and reject a repeated init.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create or reject an existing lock. |

### Arguments and options

Neither invocation uses a scope option.

### Preconditions and fixtures

Use `/tmp/c-plugin-v2-init-e2e/home` and `/tmp/c-plugin-v2-init-e2e/totto2727-org/monorepo`.
Create both directories without locks.

### Execution flow

1. Run `c-plugin init` from the project.
2. Check the selected lock and record its checksum.
3. Run `c-plugin init` again.

### Expected results

The first call succeeds with exact stdout `Created <project lock>\n` and empty-lock JSON.
The second fails with `totto2727/c-plugin.StateStoreError.AlreadyExists` in stdout.
The lock checksum is unchanged, and the home lock stays absent.
Project/home `.agents` and home `.cache/c-plugin` stay absent.

### Notes

`runInitWorkflow` is shared setup and is not a registry case.

## `init_global`

### Scope

Create a global lock exclusively and keep project state untouched.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create or reject an existing global lock. |

### Arguments and options

Use `-g` initially and `--global` on repetition.

### Preconditions and fixtures

Use the same synthetic paths as `init_project` in a separate container.

### Execution flow

1. Run `c-plugin init -g` from the project.
2. Check the home lock and record its checksum.
3. Run `c-plugin init --global`.

### Expected results

The first call succeeds with exact stdout `Created <home lock>\n` and empty-lock JSON.
The second fails with `totto2727/c-plugin.StateStoreError.AlreadyExists` in stdout.
The home lock checksum is unchanged, and the project lock stays absent.
Project/home `.agents` and home `.cache/c-plugin` stay absent.

### Notes

The two init examples use separate environments despite their common paths and helper.

## `sync`

### Scope

Reconcile explicit selections across primary and additional roots while preserving foreign paths.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin sync` | Reconcile the persisted lock offline. |

### Arguments and options

No options are supplied.

### Preconditions and fixtures

Use `/tmp/c-plugin-v2-sync-e2e/home/project`, plugin `demo` with `alpha` and `beta`, and target `.cursor/skills`.
Record the lock checksum.

### Execution flow

1. Run `c-plugin sync` and check both skills in `.agents/skills` and `.cursor/skills`.
2. Replace primary `beta` with `foreign\n` and create neighboring `neighbor\n`.
3. Persist an empty enabled set and record its checksum.
4. Run `c-plugin sync` again.

### Expected results

Both calls succeed and report `Synced <lock>: partial` without changing the corresponding lock checksum.
The initial state owns both skills.
The second sync removes primary `alpha` and both additional-target links.
Primary `beta` stays a physical regular file with exact foreign bytes, and its neighbor is unchanged.
Ownership JSON becomes `{"ownershipEntries":{}}`.

### Notes

The physical replacement deliberately no longer matches the original owned symlink.

## `sync_recursive`

### Scope

Discover two nonignored locks and reconcile them independently.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin sync` | Recursive project reconciliation and invalid scope rejection. |

### Arguments and options

Use `-r`, then `--recursive`, then the invalid combination `-g -r`.

### Preconditions and fixtures

Use `/tmp/c-plugin-v2-sync-recursive-e2e/home/project`, a parent `alpha` plugin, a child `beta` plugin, and both locks.
`.gitignore` contains `ignored/\n`, whose lock contains `{invalid\n`.
Create a foreign primary file and record both lock checksums.

### Execution flow

1. Run `c-plugin sync -r`.
2. Clear the parent enabled set and record its new lock checksum.
3. Run `c-plugin sync --recursive`.
4. Run `c-plugin sync -g -r`.

### Expected results

Both valid invocations succeed and contain exactly two `Synced ` occurrences.
The first identifies parent and child locks, excludes the ignored lock, creates both canonical skill links, and creates both ownership states.
The second removes parent `alpha` while preserving child `beta` and its ownership.
The foreign file remains exact, and parent/child lock checksums stay equal to their corresponding snapshots.
The invalid invocation fails with `totto2727/c-plugin.SyncError.Planning` in stdout.

### Notes

The ignored corrupt lock must not be parsed.

## `add`

### Scope

Preserve partial collision handling, semantic no-op behavior, and exact force limits.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create the project lock. |
| `c-plugin plugin add` | Register selected plugin skills. |
| `c-plugin skill remove` | Disable selected plugin skills. |

### Arguments and options

Use source `local:./plugin`, repeated `--skill alpha --skill beta`, and `--force` only for the final add.
Removal uses `--skill demo/alpha --skill demo/beta`.

### Preconditions and fixtures

Use `/tmp/c-plugin-v2-add-e2e/home/project`, standard plugin skills `alpha` and `beta`, and a foreign regular file at primary `alpha`.
Run product commands from `project/nested` after init.

### Execution flow

1. Run `c-plugin init`.
2. Run `c-plugin plugin add local:./plugin --skill alpha --skill beta` twice.
3. Run `c-plugin skill remove --skill demo/alpha --skill demo/beta`.
4. Create a real `beta` directory containing `keep`, and a neighboring file.
5. Run `c-plugin plugin add local:./plugin --skill alpha --skill beta --force`.

### Expected results

The first add succeeds with a partial report and both skills selected in the lock.
`beta` links to the canonical source and is owned, while foreign `alpha` stays a physical file with exact bytes and no ownership.
The repeat reports exact `No skill changes for <lock>\n`, preserves both lock/state checksums, and preserves the same file/link kinds and bytes.
Removal preserves foreign `alpha` and removes the `beta` link.
Forced add replaces eligible `alpha` with its source link and owns it.
It preserves the real `beta` directory, its `directory-content\n`, and the neighboring `neighbor\n`, and does not own `beta`.

### Notes

A force flag never authorizes directory deletion or neighbor mutation.

## `remove`

### Scope

Disable plugin skills without removing foreign replacements or the final plugin registration, and isolate global removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin sync` | Establish ownership. |
| `c-plugin skill remove` | Disable plugin selections. |
| `c-plugin plugin remove` | Remove the global registration. |

### Arguments and options

Use no selection, `--skill demo/unknown`, normalized `--skill demo/./alpha`, repeated `--skill demo/alpha`, and `--skill demo/beta`.
Global commands use `--global`, `--skill demo/gamma`, and `--plugin demo`.

### Preconditions and fixtures

Use `/tmp/c-plugin-v2-remove-e2e/home/project` with selected `alpha` and `beta`.
After sync, replace primary `alpha` with `replacement\n`, create neighbor `foreign\n`, and snapshot lock/state checksums.

### Execution flow

1. Run `c-plugin sync` and prepare the replacement fixtures.
2. Run `c-plugin skill remove`, then `c-plugin skill remove --skill demo/unknown`.
3. Run `c-plugin skill remove --skill demo/./alpha`, then repeat with `demo/alpha`.
4. Run `c-plugin skill remove --skill demo/beta`.
5. Create a home plugin with `gamma`, home lock, and project nested directory.
6. Run `c-plugin sync --global`, `c-plugin skill remove --global --skill demo/gamma`, and `c-plugin plugin remove --global --plugin demo` from the nested directory.

### Expected results

Missing selection fails with `--skill` but not `--plugin` in stdout.
The invalid and unknown selections preserve lock/state checksums, replacement bytes, neighbor bytes, and the `beta` link.
Normalized alpha removal reports partial completion, selects only `beta`, drops alpha ownership, and preserves beta ownership and link.
Repeating alpha removal is a checksum-preserving exact no-op report.
Final beta removal reports complete, retains an empty plugin registration, removes its link, and preserves both foreign files.
Global gamma removal clears the home enabled set, link, and ownership.
Global plugin removal empties the home lock while preserving the project lock checksum.

### Notes

Project and global actions share a synthetic home but have separate ownership stores.

## `target_add`

### Scope

Add normalized additional roots, avoid rewriting a semantic no-op, and isolate global targets.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin target add` | Add project or global targets and reconcile. |

### Arguments and options

Use `.cursor/skills`, equivalent `.cursor/./skills`, and `.claude/skills --global`.

### Preconditions and fixtures

Use `/tmp/c-plugin-v2-target-add-e2e/home/project` with selected project `alpha` and no extra target.
Later create a separate home plugin with `beta` and no extra target.

### Execution flow

1. Run `c-plugin target add .cursor/skills`.
2. Snapshot project lock/state, then run `c-plugin target add .cursor/./skills`.
3. From a nested project directory, run `c-plugin target add .claude/skills --global`.

### Expected results

Project add reports partial completion, persists the extra target, links `alpha` in both roots, and records both managed roots.
The normalized repeat has exact already-registered output and preserves both checksums.
Global add reports partial completion, persists `.claude/skills`, links `beta` in primary and extra home roots, and records the extra managed root.

### Notes

The implicit primary root is not an additional lock target.

## `target_remove`

### Scope

Remove only selected additional targets and preserve primary links, unrelated targets, and foreign neighbors.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin sync` | Establish project/global target ownership. |
| `c-plugin target remove` | Remove selected additional targets. |

### Arguments and options

Use unknown `--target .vscode/skills`, no selection, normalized `--target .cursor/./skills`, `--target .claude/skills`, and `--global --target .cursor/skills`.

### Preconditions and fixtures

Use `/tmp/c-plugin-v2-target-remove-e2e/home/project`, project `alpha`, and additional `.cursor/skills` and `.claude/skills`.
After sync, create `.cursor/skills/neighbor` with `foreign\n` and record lock/state checksums.

### Execution flow

1. Run `c-plugin sync`, then `c-plugin target remove --target .vscode/skills` and `c-plugin target remove`.
2. Run `c-plugin target remove --target .cursor/./skills`.
3. Run `c-plugin target remove --target .claude/skills`.
4. Create a home `beta` plugin with a cursor target and run `c-plugin sync --global` from a nested project directory.
5. Run `c-plugin target remove --global --target .cursor/skills` from the nested directory.

### Expected results

Unknown removal is an exact no-op and empty removal fails with `--target`.
All three project links, neighbor bytes, and lock/state checksums remain unchanged after these two invocations.
Cursor removal reports complete, retains only the Claude target, removes its link and managed-root record, and preserves both other links and neighbor bytes.
Claude removal reports complete, leaves no additional targets, removes its link, keeps the primary link and neighbor, and clears both old managed-root paths.
Global removal clears the home cursor target, link, and managed-root record while preserving the home primary `beta` link.

### Notes

Foreign neighboring files are not target ownership.

## `standard_minimal`

### Scope

Install and remove all skills from a minimal standard manifest.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Register the standard plugin. |
| `c-plugin plugin remove` | Remove its registration. |

### Arguments and options

Add uses `local:./plugin --all`, and removal uses `--plugin demo`.

### Preconditions and fixtures

`standardEnvironment` uses suffix `minimal` and skills `alpha`, `beta`.

### Execution flow

1. Initialize, then run `c-plugin plugin add local:./plugin --all`.
2. Run `c-plugin plugin remove --plugin demo`.

### Expected results

Add succeeds with the exact expected partial-report substring and both enabled selections.
Both skill links resolve to their source directories, and each skill is owned.
Removal succeeds with its expected report prefix, empties the lock and ownership JSON, and removes both links.

### Notes

The manifest has only schema and name.

## `standard_empty`

### Scope

Register a valid plugin with no discoverable skills.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Register an empty plugin. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

`standardEnvironment` uses suffix `empty` and no skills.

### Execution flow

1. Initialize, then run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add succeeds and reports the source.
The lock retains plugin `demo` with no enabled skills, ownership is empty, and alpha/beta links remain absent.

### Notes

The source has no skills directory.

## `standard_unknown_field`

### Scope

Warn for unknown manifest fields without redirecting standard discovery.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Parse the manifest and discover skills. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

Use suffix `unknown`, valid `alpha`, manifest fields `skills: "./elsewhere"` and `custom: true`, and `elsewhere/beta/SKILL.md`.

### Execution flow

1. Initialize and overwrite the manifest.
2. Run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add succeeds and warns separately for `skills` and `custom`.
Only `alpha` is enabled and linked, and `beta` stays absent.

### Notes

Unknown fields do not change the standard skills root.

## `standard_wrong_schema`

### Scope

Reject a wrong schema without mutating the lock or foreign paths.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Reject the manifest. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

Use suffix `wrong-schema`, valid `alpha`, schema `https://example.invalid/plugin.schema.json`, and a foreign managed-root file.
Record the lock checksum.

### Execution flow

1. Initialize and replace the schema.
2. Run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add fails with `totto2727/c-plugin.PluginAddError.InvalidInput` in stdout.
The lock checksum and exact `foreign\n` file bytes remain unchanged.
Ownership state and the alpha link stay absent.

### Notes

The invalid candidate is not persisted.

## `standard_invalid_skill`

### Scope

Skip an invalid skill while installing a valid sibling.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Validate discovered skills. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

Use suffix `invalid-skill`, valid `alpha`, and beta frontmatter `---\nname: beta\n---\n`, which lacks a description.

### Execution flow

1. Initialize and create the invalid skill.
2. Run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add succeeds with `Warning: invalid skill beta:`.
Only alpha is enabled and canonically linked.
Beta has no link and no ownership.

### Notes

Invalid sibling metadata does not reject the whole plugin.

## `standard_shallow_discovery`

### Scope

Discover only direct skill children.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Discover direct skill directories. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

Use suffix `shallow`, direct `alpha`, and nested `skills/group/beta/SKILL.md`.

### Execution flow

1. Initialize and write nested beta.
2. Run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add succeeds, selects only alpha, and creates its canonical link.
Neither beta nor group appears in the managed skills root.

### Notes

Nested directories are not recursively promoted to skills.

## `standard_manifest_escape`

### Scope

Reject a manifest symlink that leaves the plugin root.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Reject the escaping manifest. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

Use suffix `manifest-escape` with `alpha`.
Write `outside/plugin.json`, snapshot its checksum, replace `plugin/plugin.json` with a symlink to it, and create a foreign file.
Snapshot the project lock checksum.

### Execution flow

1. Initialize and prepare the manifest symlink.
2. Run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add fails and reports `outside plugin root`.
Lock and outside-file checksums stay unchanged, ownership state and alpha link stay absent, and foreign bytes remain exact.

### Notes

The outside manifest is valid JSON but physically outside the allowed source root.

## `standard_skills_escape`

### Scope

Skip an escaping skills-directory symlink without damaging its target.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Skip an escaping skills root. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

Use suffix `skills-escape` without initial skills.
Write and checksum `outside/alpha/SKILL.md`, then link `plugin/skills` to `outside`.

### Execution flow

1. Initialize and create the escaping skills-root link.
2. Run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add succeeds and reports `outside plugin root`.
The plugin stays registered with no enabled skills, ownership is empty, and the alpha link is absent.
The outside skill checksum is unchanged.

### Notes

The omitted initial skills directory is required for this fixture.

## `standard_skill_file_escape`

### Scope

Skip an escaping skill metadata file while installing a valid sibling.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the fixture. |
| `c-plugin plugin add` | Reject escaping metadata for one skill. |

### Arguments and options

Use `local:./plugin --all`.

### Preconditions and fixtures

Use suffix `skill-file-escape` with valid `alpha`.
Write and checksum `outside/SKILL.md` for beta, create `plugin/skills/beta`, and link its `SKILL.md` to that outside file.

### Execution flow

1. Initialize and create the escaping metadata link.
2. Run `c-plugin plugin add local:./plugin --all`.

### Expected results

Add succeeds and emits both `Warning: invalid skill beta:` and `outside plugin root`.
Only alpha is selected and canonically linked, beta stays absent, and the outside checksum is unchanged.

### Notes

Metadata containment is checked independently of the skill directory.
