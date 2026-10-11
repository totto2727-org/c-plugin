# Read-only desired-state listings

Source: [list_test.go](./list_test.go)

## `listReadOnlyScenario`

### Scope

Verify exact combined/plugin/skill output, disabled-plugin visibility, active-skill filtering, project/global scope, and read-only behavior despite missing sources/links and corrupt ownership.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the global lock. |
| `c-plugin plugin add` | Prepare active and disabled registrations. |
| `c-plugin skill add` | Prepare a standalone registration. |
| `c-plugin list` | Print both sections. |
| `c-plugin plugin list` | Print all plugin records, including disabled records. |
| `c-plugin skill list` | Print enabled plugin skills and standalone skills. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--skill alpha` | Enable alpha while beta remains disabled. |
| `local:./disabled`, `--none` | Register an entirely disabled plugin. |
| `local:./standalone/solo` | Register standalone solo. |
| `--all`, `--global`, `-g` | Populate or inspect independent HOME state. |

### Preconditions and fixtures

- A disposable container uses synthetic `HOME=/tmp/c-plugin-standard-list-read-only/home` and `project=$HOME/project`.
- The executable is `/sandbox/.local/bin/c-plugin`.
- Project records are demo with alpha enabled and beta disabled, disabled with no enabled skills, and standalone solo; HOME has demo/gamma.
- After installation, all project sources and the alpha link are removed, ownership is replaced with corrupt bytes, and a foreign neighbor is created.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --skill alpha`, `c-plugin plugin add local:./disabled --none`, and `c-plugin skill add local:./standalone/solo`.
2. Run `c-plugin init --global`, prepare HOME's plugin, and run `c-plugin plugin add local:./plugin --all --global`.
3. Capture project/global lock and global ownership digests, then prepare the missing-source/link and corrupt-ownership fixtures.
4. From `project/nested`, run `c-plugin list`, `c-plugin plugin list`, `c-plugin skill list`, `c-plugin list -g`, `c-plugin plugin list -g`, and `c-plugin skill list -g`, in that order.
5. After every invocation, compare exact output, lock/state bytes, foreign neighbor, absent project sources/alpha, surviving dangling solo, and correct global gamma.

### Expected results

- Every list invocation exits 0 without mutation or reconciliation.
- Plugin output begins `Plugins\nname\tsource\tenabled-skills\n` and has rows `demo\tlocal:./plugin\talpha\n` and `disabled\tlocal:./disabled\t-\n`.
- Skill output begins `Skills\nname\towner\tsource\n` and has rows `alpha\tplugin:demo\tlocal:./plugin\n` and `solo\tstandalone\tlocal:./standalone/solo\n`; beta is not listed.
- Global output contains only demo/gamma, never project records.
- Combined output is exactly plugin output, one blank line, then skill output.
- Corrupt ownership is not consulted or repaired, missing links are not created, and source directories are not rediscovered or fetched.

### Notes

The exact tab-delimited output assertions are in the sibling source.
A surviving dangling link is checked with `test -L`, not `realpath`.

## `listMissingCorruptScenario`

### Scope

Verify missing, malformed, and unsupported-version locks fail without creating state, and empty valid locks produce headings and headers only.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin list` | Inspect or reject both-section state. |
| `c-plugin plugin list` | Inspect or reject plugin state. |
| `c-plugin skill list` | Inspect or reject skill state. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `-g` | Repeat every check against HOME rather than the project root. |

### Preconditions and fixtures

- A disposable container uses `HOME=/tmp/c-plugin-list-missing-corrupt/home` and an empty project directory.
- The executable is `/sandbox/.local/bin/c-plugin`.
- Both scopes successively have no lock, literal `not JSON\n`, a version-2 lock, then an empty valid version-3 lock.
- No ownership or managed roots exist.

### Execution flow

1. For absent locks, run `c-plugin list`, `c-plugin plugin list`, `c-plugin skill list`, `c-plugin list -g`, `c-plugin plugin list -g`, and `c-plugin skill list -g` in order.
2. Write malformed bytes to both locks and repeat the same six ordered argv.
3. Write the unsupported version-2 fixture to both locks and repeat the same six ordered argv.
4. Write the empty valid version-3 fixture to both locks and repeat the same six ordered argv.
5. After every command, verify both lock contents or continued absence and absent `.agents` directories.

### Expected results

- Missing, malformed, and unsupported-version locks return nonzero for every list command, without conversion, lock creation, or state creation.
- Empty valid locks return 0 with exact headings and column headers and no rows.
- Combined empty output separates its two sections with one blank line.
- Valid locks retain their original bytes and `.agents` remains absent in both scopes.

### Notes

These are real CLI scenarios registered with the existing runner, not zero-test static substitutes.
Their execution requires the caller-owned Docker image.

## `githubListUnavailableScenario`

### Scope

Verify GitHub toggles stay pinned and offline, then verify all list commands succeed read-only when both GitHub snapshot sources are unavailable and any Git invocation is forbidden.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Prepare the project lock. |
| `c-plugin plugin add` | Install the existing public plugin fixture. |
| `c-plugin skill add` | Install standalone solo at the same immutable commit. |
| `c-plugin plugin skill disable` | Disable all cached plugin skills offline. |
| `c-plugin plugin skill enable` | Enable cached plugin skills offline. |
| `git ls-remote` | Prove the network-blocking proxy environment fails. |
| `c-plugin list` | List unavailable pinned GitHub sources. |
| `c-plugin plugin list` | List the pinned plugin registration without Git. |
| `c-plugin skill list` | List pinned plugin and standalone skills without Git. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:totto2727-org/c-plugin/hs/test/fixtures/github/plugin` | Existing public Agent Plugins fixture. |
| `github:totto2727-org/c-plugin/hs/test/fixtures/github/solo` | Existing public standalone fixture. |
| `--ref test/e2e-unified-api`, `--ref COMMIT` | Fetch the plugin ref and pin solo to the resulting full commit. |
| `github-demo`, `--all`, `--skill alpha` | Disable all, enable alpha, then enable all. |
| HTTP(S)/all-proxy variables | Block network during toggles and lists. |
| `PATH` | Put an executable rejecting Git wrapper before system Git during lists. |

### Preconditions and fixtures

- A disposable container uses synthetic `HOME=/tmp/c-plugin-github-list-unavailable/home` and initialized project state.
- The executable is `/sandbox/.local/bin/c-plugin`.
- Initial fixture installation requires access to the existing public repository, as do the other GitHub lifecycle scenarios.
- `COMMIT` is decoded and verified by existing GitHub fixture helpers.
- The Git wrapper records a sentinel and exits 99 if invoked; it is only activated after offline toggle verification.

### Execution flow

1. Run `c-plugin plugin add github:totto2727-org/c-plugin/hs/test/fixtures/github/plugin --ref test/e2e-unified-api --all`.
2. Decode `COMMIT`, then run `c-plugin skill add github:totto2727-org/c-plugin/hs/test/fixtures/github/solo --ref COMMIT`.
3. With uppercase/lowercase HTTP(S)/all-proxy variables set to `127.0.0.1:1` and no-proxy exemptions cleared, run `git ls-remote https://github.com/totto2727-org/c-plugin refs/heads/test/e2e-unified-api` and require failure.
4. In the same blocked-network environment, run `c-plugin plugin skill disable github-demo --all`, `c-plugin plugin skill enable github-demo --skill alpha`, and `c-plugin plugin skill enable github-demo --all`; after each compare pinned commit and manifest digest and inspect link changes.
5. Verify the final desired lock digest equals the original digest and beta is linked again.
6. Write the rejecting Git wrapper to `$HOME/bin/git-template` through the archive-backed helper, run infrastructure `cp $HOME/bin/git-template $HOME/bin/git` to create a new sandbox-owned file, and then run `chmod +x $HOME/bin/git`. Remove only the synthetic snapshot-cache root and alpha link, and record lock/state digests.
7. With the rejecting wrapper first in PATH and network blocked, run `c-plugin list`, `c-plugin plugin list`, and `c-plugin skill list`, in that order.
8. After every list, compare exact output and digests, require absent Git sentinel/cache/source/alpha, and preserve dangling beta/solo links.

### Expected results

- Offline toggles return 0, retain the installed plugin when disabled, and do not change its commit or manifest checksum.
- All three list commands return 0 even though cache directories and resolved sources are absent.
- Source labels are `github:OWNER/REPO/SUBPATH@COMMIT` with the exact full pinned commit, not local cache paths or mutable requested refs.
- Plugin enabled names are `alpha,beta`; skill output includes alpha/beta owned by `plugin:github-demo` and solo owned by `standalone`.
- Desired and ownership bytes are unchanged, cache and missing alpha are not recreated, and the Git wrapper is never invoked.

### Notes

Deleting synthetic fixture caches here tests absence without authorizing production cache deletion.
The setup network dependency is explicit; successful static validation is not proof that the hosted fixture or Docker execution succeeded.
