# GitHub sources and recursive reconciliation

Source: [GitHubSpec.hs](./GitHubSpec.hs)
Each scenario installs the trusted driver from host `C_PLUGIN_E2E_DRIVER` once through `newScenario`; physical file-byte assertions use public snapshots.

Each named Hspec example runs in its own `c-plugin-e2e:local` container through `Test.CLI.E2E.withEnvironment`.
The group is parallel and the suite runs with two Hspec jobs.
The executable is `/sandbox/.local/bin/c-plugin` and every CLI call receives an isolated synthetic `HOME`.
The shared `githubEnvironment` helper initializes `project=$HOME/project` with `c-plugin init` and is not an additional case.
The repository fixture is `totto2727-org/c-plugin`, the URL is `https://github.com/totto2727-org/c-plugin`, and the branch is `test/e2e-unified-api`.
Below, `root` means `github:totto2727-org/c-plugin`, `plugin` means `root/hs/test/fixtures/github/plugin`, and `solo` means `root/hs/test/fixtures/github/solo`.
URL variants replace `totto2727-org/c-plugin` with its full HTTPS URL after `github:`.
Registration assertions require exactly one entry in the selected domain, matching its key and name, and a physical source directory under a clean relative `.agents/c-plugin/sources/` path without `..`.
Pin assertions require the fixture repository, a nonempty ref, a lowercase 40-digit hexadecimal commit, and the exact source path `.agents/c-plugin/sources/<repository>/<commit>/tree/<subpath>`.

## `github_parser_invalid`

### Scope

Reject all 25 invalid parser combinations without changing desired or ownership state.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Reject invalid plugin source and selector syntax. |
| `c-plugin skill add` | Reject invalid standalone source syntax. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--github`, `--local`, `--path` | Reject removed source options. |
| `--ref` | Reject missing sources, local refs, and revision expressions. |
| `--all`, `--none`, `--skill` | Reject conflicting plugin selections. |
| Local and GitHub positional sources | Reject inference, extra sources, invalid hosts, and unsafe paths. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-parser-invalid/home` and save the initialized lock bytes.
No ownership state or managed skill links exist.

### Execution flow

Execute these ordered argv tails from the project, expanding the source aliases above without a shell:

1. `plugin add --github totto2727-org/c-plugin --all`
2. `skill add --local ./solo`
3. `plugin add <plugin> --path hs/test/fixtures/github/plugin --all`
4. `plugin add <plugin> --local ./plugin --all`
5. `skill add <solo> --local ./solo`
6. `plugin add <plugin> local:./plugin --all`
7. `skill add <solo> local:./solo`
8. `plugin add local:./plugin --ref test/e2e-unified-api --all`
9. `skill add local:./solo --path hs/test/fixtures/github/solo`
10. `plugin add --ref test/e2e-unified-api --all`
11. `skill add --ref test/e2e-unified-api`
12. `plugin add totto2727-org/c-plugin --all`
13. `skill add https://github.com/totto2727-org/c-plugin`
14. `skill add ./solo`
15. `plugin add github:owner --all`
16. `skill add github:https://example.com/owner/repo`
17. `skill add github:https://github.com/owner/repo?ref=main`
18. `plugin add <root>/../plugin --all`
19. `skill add <root>//tmp/solo`
20. `skill add <root>/.git`
21. `skill add local:/tmp/solo`
22. `skill add local:solo`
23. `skill add <solo> --ref HEAD^{commit}`
24. `plugin add <plugin> --all --none`
25. `plugin add <plugin> --all --skill alpha`

### Expected results

Each command fails.
After every rejection, lock bytes remain exact, ownership state remains absent, and neither alpha nor solo has a managed link.

### Notes

All cases remain separate argv vectors, including braces, question marks, repeated slashes, and traversal components.

## `github_source_failure`

### Scope

Reject real GitHub sources with an invalid root, missing path, nonexistent ref, or nonexistent repository.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Validate an explicit plugin root and ref. |
| `c-plugin skill add` | Validate an explicit standalone root and repository. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--ref test/e2e-unified-api` | Select the public fixture branch. |
| `--all` | Select all skills after valid plugin discovery. |
| Missing root, ref, and repository values | Exercise source rejection. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-source-failure/home` and save the initialized lock.
Real GitHub transport is available.

### Execution flow

1. Run `plugin add <root> --ref test/e2e-unified-api --all`.
2. Run `skill add <root>/hs/test/fixtures/github --ref test/e2e-unified-api`.
3. Run `plugin add <root>/hs/test/fixtures/github/missing --ref test/e2e-unified-api --all`.
4. Run `plugin add <plugin> --ref c-plugin-e2e-ref-that-does-not-exist --all`.
5. Run `skill add github:totto2727-org/c-plugin-e2e-repository-that-does-not-exist/hs/test/fixtures/github/solo`.

### Expected results

Every command fails, leaves exact lock bytes, creates no ownership state, and creates neither alpha nor solo managed links.

### Notes

These are actual transport and source-validation cases, not mocked failures.

## `github_plugin_lifecycle`

### Scope

Preserve GitHub source identity through equivalent URL syntax, explicit synchronization, selection changes, and removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Register or change a pinned plugin selection. |
| `c-plugin sync` | Restore a removed managed link. |
| `c-plugin plugin remove` | Remove registration without deleting snapshots. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| Shorthand and URL plugin sources | Assert semantic source identity. |
| `--ref test/e2e-unified-api` | Pin the fixture branch. |
| `--all`, `--skill beta`, `--none` | Replace the enabled set. |
| `--plugin github-demo` | Select the plugin removal domain. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-plugin-lifecycle/home` with a nested working directory.
The public fixture exposes alpha and beta.

### Execution flow

1. From nested, run `plugin add <plugin> --ref test/e2e-unified-api --all`.
2. Assert registration, pin, manifest JSON, and both managed links, then save lock and ownership bytes.
3. Delete alpha and run `plugin add <plugin-url> --ref test/e2e-unified-api --all` from the project.
4. Assert unchanged bytes and missing alpha, then run `sync` and verify alpha restoration.
5. Run `plugin add <plugin> --ref test/e2e-unified-api --skill beta` and inspect selection and links.
6. Run `plugin add <plugin> --ref test/e2e-unified-api --none` and inspect disabled registration.
7. Run `plugin remove --plugin github-demo` and inspect empty state and retained snapshot.

### Expected results

All commands succeed.
The snapshot manifest has the standard schema and name github-demo.
Equivalent source syntax is a semantic no-op and does not restore alpha until sync.
Selecting beta removes alpha and preserves beta.
Disabling all skills preserves the plugin registration with an empty enabled set and removes beta.
Removal leaves the empty lock and ownershipEntries object while the source manifest remains a physical regular file.

### Notes

No-op lock and state preservation is byte-exact.

## `github_standalone_offline`

### Scope

Reconcile a pinned standalone snapshot offline and retain source contents after removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Register a standalone GitHub source. |
| `c-plugin sync` | Reconcile offline. |
| `c-plugin skill remove` | Remove only the registration and managed link. |
| `git ls-remote` | Prove the offline network configuration blocks GitHub. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| Shorthand and URL solo sources | Test equivalent source identities. |
| `--ref test/e2e-unified-api` | Select the fixture branch. |
| `--skill solo` | Remove the standalone identity. |
| Uppercase and lowercase HTTP, HTTPS, and ALL proxy variables | Block transport with `http://127.0.0.1:1`. |
| `NO_PROXY`, `no_proxy` | Clear proxy bypasses. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-standalone-offline/home`.
The standalone source has SKILL.md but no plugin.json.

### Execution flow

1. Run `skill add <solo-url> --ref test/e2e-unified-api`, verify registration and pin, and record SKILL.md SHA-256 plus lock and state bytes.
2. Delete the managed link and run `skill add <solo> --ref test/e2e-unified-api`.
3. Check exact no-op bytes and missing link.
4. Under blocked proxies, run `git ls-remote <repository-url> refs/heads/test/e2e-unified-api` and require failure.
5. Under those same proxies, run `sync` and inspect restored link, lock bytes, and source checksum.
6. Run `skill remove --skill solo` and inspect the empty lock, missing link, and retained source checksum.

### Expected results

Add, sync, and removal succeed while the real network probe fails.
The managed link resolves to the pinned standalone directory.
No-op add does not synchronize.
Offline sync and removal do not change source bytes.

### Notes

Local Git integrity verification is allowed during offline sync.

## `github_global`

### Scope

Keep project and global GitHub registrations and snapshot roots isolated.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the global lock. |
| `c-plugin skill add` | Register the same source in separate scopes. |
| `c-plugin sync` | Reconcile global state from a nested project directory. |
| `c-plugin skill remove` | Remove only global solo. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Select HOME instead of project. |
| Branch ref and immutable commit ref | Reuse the observed project pin globally. |
| `--skill solo` | Select standalone removal. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-global/home` and a nested project directory.

### Execution flow

1. Run `init --global` and `skill add <solo> --ref test/e2e-unified-api` from project.
2. Verify project registration and pin and save project lock and state bytes.
3. From nested, run `skill add --global <solo-url> --ref <observed-commit>`.
4. Inspect the global registration and snapshot location.
5. From nested, run `sync --global`, then `skill remove --global --skill solo`.
6. Compare global cleanup and project preservation.

### Expected results

All commands succeed.
Global and project source paths differ.
Global sources are below HOME but not below project.
The global link resolves to the global snapshot.
Global removal empties its lock and removes its link without changing project lock, ownership bytes, or project link.

### Notes

Both scopes use the same public source and standalone name.

## `github_cache_safety`

### Scope

Reject a symlinked cache ancestor and preserve foreign metadata and remote identity during partial sync.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill add` | Reject unsafe cache containment and register a valid source. |
| `c-plugin sync` | Report partial reconciliation for foreign cache identities. |
| `git remote set-url` | Set a foreign cache remote fixture. |
| `git remote get-url` | Verify the foreign remote remains exact. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--force` | Confirm force cannot bypass cache containment. |
| `--ref test/e2e-unified-api` | Select the fixture branch. |
| `foreign/repository` | Replace cache metadata and remote identity independently. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-cache-safety/home`.
Create an outside directory with sentinel bytes `foreign cache must survive\n` and symlink the project sources root to it.

### Execution flow

1. Save lock bytes and run `skill add <solo> --ref test/e2e-unified-api --force`.
2. Check rejection, unchanged lock, no ownership state, no outside `totto2727-org`, intact sentinel, and intact cache-root symlink.
3. Remove only the symlink and run `skill add <solo> --ref test/e2e-unified-api`.
4. Verify source registration and pin, exact origin JSON, and save origin, lock, state, and SKILL.md SHA-256.
5. Replace origin repository with foreign/repository and run `sync`.
6. Check partial success and exact lock, state, foreign origin bytes, link, and source checksum.
7. Restore origin bytes and run `git -C <cache>/tree remote set-url origin https://github.com/foreign/repository.git`.
8. Run `sync` and check partial success, lock, state, link, and checksum again.
9. Run `git -C <cache>/tree remote get-url origin` and compare stdout, then recheck the outside sentinel.

### Expected results

Unsafe add fails even with force.
Valid add succeeds.
Both foreign-identity syncs succeed with stdout containing partial, without adopting, deleting, or rewriting the cache.
Remote stdout remains exactly `https://github.com/foreign/repository.git\n`.

### Notes

The two foreign identity cases are independent because metadata is restored before the remote is changed.

## `github_force_safety`

### Scope

Limit forced replacement to eligible exact files and preserve real directories and neighbors.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Register and force-reconcile the GitHub plugin. |
| `c-plugin plugin remove` | Remove only owned managed links. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--ref test/e2e-unified-api`, `--all` | Enable both fixture skills. |
| `--force` | Replace the eligible beta file only. |
| `--plugin github-demo` | Remove the plugin registration. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-force-safety/home`.
Create a real alpha directory with keep bytes `foreign directory\n`, beta file bytes `replace eligible file\n`, and neighbor bytes `foreign neighbor\n`.

### Execution flow

1. Run `plugin add <plugin> --ref test/e2e-unified-api --all --force`.
2. Verify registration, pin, real alpha directory and keep bytes, neighbor bytes, and beta snapshot link.
3. Run `plugin remove --plugin github-demo`.
4. Inspect the empty lock and absent beta, then recheck alpha keep and neighbor bytes.

### Expected results

Both commands succeed.
Beta is replaced by an owned link and removed on plugin removal.
The foreign alpha directory and neighboring file survive unchanged.

### Notes

Force does not authorize directory deletion or neighboring mutations.

## `top_level_sync_update_recursive`

### Scope

Exercise both source domains, both top-level reconciliation commands, pinned no-op lock identity, and every recursive discovery boundary.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `git ls-remote` | Resolve a real immutable fixture commit. |
| `c-plugin plugin add` | Register the explicit `.git` URL subpath source. |
| `c-plugin skill add` | Register solo at the same commit. |
| `c-plugin sync` | Reconcile current pins and recursively discover locks. |
| `c-plugin update` | Refresh sources and reconcile even with unchanged locks. |
| `stat` | Inspect lock inode and modification time. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--ref <observed-commit>`, `--all` | Pin both domains to the observed fixture SHA. |
| `-r` | Use original Admiral recursive discovery rules plus safety exclusions. |
| `--global -r` | Reject incompatible scopes. |
| `%i:%Y` | Compare inode and modification time exactly. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-top-level-recursive/home`.
The parent contains github-demo alpha/beta and standalone solo at one observed commit.
The child contains local demo child-skill plus local standalone solo.
Save exact parent lock and ownership bytes and `stat -c %i:%Y <parent-lock>` output.
The parent .gitignore bytes are `  # comment-visible/  \n  .hidden-excluded/  \n  ignored-*/  \n!ignored-keep/\n/anchored/\nglobstar/**/blocked/\npatterns/a*/blocked/\nquestion?/\nc-plugin-lock.json\n`.
A directory-scoped .gitignore contains `  scoped/  \n`.
Visible roots are parent, child, `.hidden-included`, `comment-visible`, `globstar/a/b/blocked`, `other/scoped`, and `questionx`.
Invalid-lock traps are `.git/trap`, `.hidden-excluded`, `ignored-alpha`, `ignored-keep`, `anchored`, `wrapped/anchored`, `globstar/a/blocked`, `wrapped/patterns/alpha/blocked`, `directory-scope/scoped`, `question?`, and `.agents/c-plugin/sources/discovery-trap`.
Every trap has exact bytes `{invalid discovery trap\n`.
A symlinked-project directory points outside to a valid empty lock.

### Execution flow

1. Run `git ls-remote <repository-url> refs/heads/test/e2e-unified-api` and require exactly a SHA plus the expected ref.
2. Run `plugin add github:https://github.com/totto2727-org/c-plugin.git/hs/test/fixtures/github/plugin --ref <commit> --all`, then `skill add <solo> --ref <commit>`.
3. Assert both registrations and both observed pins.
4. For each of `sync` and `update`, delete all three parent links, run the command from nested, then verify owning-lock output, restored links, exact lock and ownership bytes, and exact stat identity.
5. Create the child sources and exact child lock, visible empty locks, invalid skipped locks, gitignore files, and outside symlink fixture.
6. For each command, delete all parent and child links and run `<command> -r` from nested.
7. Verify every visible root is reported and parent is reported before every other visible root.
8. Verify all skipped roots are absent from output, retain exact invalid bytes, and have no ownership state.
9. Verify no symlinked-project output, no outside ownership state, and an unchanged empty outside lock.
10. Verify all five parent/child links, exact parent and child lock bytes, and exact parent stat identity.
11. Create `missing-root/child/c-plugin-lock.json` without a root lock.
12. For each command, run `<command> -r` from missing-root and `<command> --global -r` from project, checking both rejection paths and unchanged project/child locks.

### Expected results

Real ref resolution and all valid add, sync, and update commands succeed.
All recursive visibility and exclusions follow the fixture sets exactly.
Update reconciles deleted links even when the persisted candidate is unchanged and does not rewrite the lock inode or time.
Missing-root recursion fails with LockFileNotFound, creates no root lock or child ownership, and leaves the child lock empty.
Global recursion fails with `--global cannot be combined with --recursive`, creates no global lock or ownership, and preserves both existing locks.

### Notes

The matcher trims rules, ignores negations, strips anchors, and applies `*` within a path segment.
The ignored lock filename does not prevent discovery of visible roots.
The source snapshot cache and .git exclusions are explicit safety boundaries.
