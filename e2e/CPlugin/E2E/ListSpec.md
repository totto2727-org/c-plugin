# Read-only desired-state lists

Source: [ListSpec.hs](./ListSpec.hs)
Each scenario installs the trusted driver from host `C_PLUGIN_E2E_DRIVER` once through `newScenario`; physical file-byte assertions use public snapshots.

Every named Hspec example runs in a separate `c-plugin-e2e:local` container through `Test.CLI.E2E.withEnvironment`.
The group is parallel and the suite uses two Hspec jobs.
The executable is `/sandbox/.local/bin/c-plugin` and CLI commands receive a synthetic HOME.
All output comparisons include tabs, newlines, row order, and empty separators.
All digest assertions use SHA-256.
Plugin output starts with `Plugins\nname\tsource\tenabled-skills\n` and skill output starts with `Skills\nname\towner\tsource\n`.
The combined list inserts one additional newline between the complete plugin and skill tables.
The shared `listCases` helper builds three argv/output pairs and does not register additional cases.

## `list_read_only`

### Scope

Read project and global desired state without requiring available sources, valid ownership, or complete managed links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Register enabled and disabled plugin fixtures. |
| `c-plugin skill add` | Register standalone solo. |
| `c-plugin init` | Initialize independent global state. |
| `c-plugin list` | Render both desired-state domains. |
| `c-plugin plugin list` | Render plugins only. |
| `c-plugin skill list` | Render skills only. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--skill alpha` | Enable only project demo alpha. |
| `local:./disabled`, `--none` | Keep a disabled plugin registration visible. |
| `local:./standalone/solo` | Register project standalone solo. |
| `--global`, `--all` | Set up global demo gamma. |
| `-g` | Select global list output. |

### Preconditions and fixtures

The standard environment named list-read-only contains project demo alpha and beta.
Write the standard-schema disabled plugin manifest and valid standalone solo.
Register project demo alpha, disabled with no skills, and standalone solo.
Initialize global state and write a separate HOME/plugin containing gamma.
Create project/nested and save project lock, global lock, and global ownership SHA-256.
Delete project plugin, disabled, standalone, and managed alpha.
Replace project ownership with exact bytes `corrupt ownership\n` and add managed-root neighbor bytes `foreign\n`.

### Execution flow

1. Set up with `plugin add local:./plugin --skill alpha`, `plugin add local:./disabled --none`, `skill add local:./standalone/solo`, `init --global`, and `plugin add local:./plugin --all --global`, in that order.
2. Corrupt and remove the fixtures as described above.
3. From nested, run `list`, `plugin list`, `skill list`, `list -g`, `plugin list -g`, and `skill list -g`, in that order.
4. After every call, compare exact expected output and all three saved checksums.
5. After every call, check exact corrupt ownership and neighbor bytes and absence of alpha and all three deleted source roots.
6. Check that solo remains a dangling symlink and global gamma still resolves to HOME/plugin/skills/gamma.

### Expected results

Every list command succeeds.
Project plugin rows are exactly `demo\tlocal:./plugin\talpha\n` followed by `disabled\tlocal:./disabled\t-\n`.
Project skill rows are exactly `alpha\tplugin:demo\tlocal:./plugin\n` followed by `solo\tstandalone\tlocal:./standalone/solo\n`.
Global plugin output has only `demo\tlocal:./plugin\tgamma\n`.
Global skill output has only `gamma\tplugin:demo\tlocal:./plugin\n`.
Listing never repairs sources, links, ownership, or lock files.
All unrelated global state and links remain unchanged.

### Notes

The solo link is checked with `test -L` because its source was removed.
Disabled plugins remain visible even when they contribute no skill rows.

## `list_missing_corrupt`

### Scope

Reject missing or invalid lock files without creating state, and render valid empty locks without mutations.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin list` | Read both domains. |
| `c-plugin plugin list` | Read the plugin domain. |
| `c-plugin skill list` | Read the skill domain. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `-g` | Exercise each command against the global lock. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-list-missing-corrupt/home` and project=$HOME/project.
The four lock conditions are absent, exact bytes `not JSON\n`, `{"version":"2","targets":[],"plugins":[]}`, and `{"version":"3","targets":[],"plugins":[]}`.
Each nonempty invalid fixture is written to both HOME and project.

### Execution flow

1. For each lock condition, run `list`, `plugin list`, `skill list`, `list -g`, `plugin list -g`, and `skill list -g` from project, in that order.
2. After every rejected call, check both locks remain absent or byte-identical to the fixture and both .agents directories remain absent.
3. Replace both locks with exact empty lock bytes `{"targets":[],"plugins":{},"standaloneSkills":{}}`.
4. Run those same six argv vectors again, checking exact header-only output, exact lock bytes, and absent .agents directories after every call.

### Expected results

All 24 calls against missing or invalid locks fail.
All six calls against valid empty locks succeed.
Single-domain output is exactly its heading and combined output is the plugin heading, one separator newline, and the skill heading.
No call creates ownership, managed directories, or replacement lock bytes.

### Notes

Old version-shaped documents are invalid fixtures, not a compatibility conversion request.

## `github_list_unavailable`

### Scope

Toggle registered pinned content offline, then prove listing needs neither cached files nor any Git invocation.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Register the real GitHub plugin fixture. |
| `c-plugin skill add` | Register standalone solo at the observed pin. |
| `git ls-remote` | Prove blocked proxies prevent real transport. |
| `c-plugin plugin skill disable` | Disable pinned content offline. |
| `c-plugin plugin skill enable` | Enable selected or all pinned content offline. |
| `c-plugin list` | Read both domains with unavailable snapshots. |
| `c-plugin plugin list` | Read plugin state without Git. |
| `c-plugin skill list` | Read skill state without Git. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:totto2727-org/c-plugin/hs/test/fixtures/github/plugin` | Select the public plugin root. |
| `github:totto2727-org/c-plugin/hs/test/fixtures/github/solo` | Select the standalone fixture. |
| `--ref test/e2e-unified-api`, `--ref <commit>` | Pin the branch and reuse the immutable observed commit. |
| `--all`, `--skill alpha` | Change registered-plugin enabled sets. |
| Uppercase and lowercase HTTP, HTTPS, and ALL proxy variables | Block network at `http://127.0.0.1:1`. |
| `NO_PROXY`, `no_proxy` | Clear proxy bypasses. |
| `PATH` | Prefer a rejecting Git wrapper during listing. |

### Preconditions and fixtures

Use `HOME=/tmp/c-plugin-github-list-unavailable/home` and the real public branch fixture.
Reuse GitHub registration and pin assertions from [GitHubSpec.hs](./GitHubSpec.hs).
The wrapper template is exactly `#!/bin/sh\nprintf called > '<HOME>/git-called'\nexit 99\n`.
Copy the archive-written template into HOME/bin/git and make the copy executable to preserve sandbox ownership semantics.

### Execution flow

1. Run `plugin add github:totto2727-org/c-plugin/hs/test/fixtures/github/plugin --ref test/e2e-unified-api --all`.
2. Verify registration and immutable pin, then run `skill add github:totto2727-org/c-plugin/hs/test/fixtures/github/solo --ref <commit>`.
3. Under blocked proxies and isolated HOME, run `git ls-remote https://github.com/totto2727-org/c-plugin refs/heads/test/e2e-unified-api` and require failure.
4. Save original lock and snapshot plugin.json SHA-256.
5. Under those same proxies, run `plugin skill disable github-demo --all`, `plugin skill enable github-demo --skill alpha`, and `plugin skill enable github-demo --all`, in that order.
6. After every toggle, verify unchanged pin and manifest checksum.
7. After disable, verify empty enabled skills and missing alpha and beta links; after each enable, verify the alpha link.
8. Verify the final lock checksum matches the original and beta resolves to the snapshot.
9. Write, copy, and chmod the Git wrapper, delete the sources cache and alpha link, then save lock and ownership checksums.
10. Set PATH to `<HOME>/bin:/usr/bin:/bin`, retain the blocked proxies, and run `list`, `plugin list`, and `skill list` from project.
11. After every list, compare exact output, unchanged lock and ownership checksums, missing cache and source, missing wrapper marker, missing alpha, and dangling beta and solo symlinks.

### Expected results

Add and toggle commands succeed, and the real network probe fails.
Toggles keep the observed commit and exact manifest contents and restore the original all-enabled lock bytes.
All three offline list commands succeed without invoking Git, recreating a snapshot, repairing alpha, or changing ownership.
The plugin row is `github-demo\tgithub:totto2727-org/c-plugin/hs/test/fixtures/github/plugin@<commit>\talpha,beta\n`.
Skill rows are alpha and beta owned by plugin:github-demo at the plugin source plus the same commit, followed by solo owned by standalone at the solo source plus the same commit.
Headers and combined-list separation are exact.

### Notes

The Git wrapper catches attempted local verification as well as attempted network access.
Dangling beta and solo symlinks are checked with `test -L`, not canonical resolution.
