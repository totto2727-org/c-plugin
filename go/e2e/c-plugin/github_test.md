# Direct GitHub plugin and standalone sources

Source: [github_test.go](./github_test.go)

All scenarios use the existing Go/Testcontainers runner and `/sandbox/.local/bin/c-plugin` inside a separate disposable container.
The hosted repository is `totto2727-org/c-plugin`.
Scenarios explicitly select their fixture ref.
The caller must publish the maintained `test/fixtures/github` fixtures at that ref before running these scenarios.
Successful installation scenarios require real public HTTPS GitHub access and Git in the container.
They do not use local remotes, transport stubs, marketplaces, or vendor manifests.
Positive install commands use one mandatory `github:` source operand containing the repository and optional subpath; local source operands use `local:./`.
The retired source flags and unprefixed operands are tested only as explicit rejections.
`COMMIT` below means the immutable 40-character commit observed from the installed lock origin, never a hardcoded final fixture commit.

## `githubParserInvalidScenario`

### Scope

Reject missing or unprefixed sources, retired source flags, multiple source operands, malformed explicit source values, unsafe refs, and incompatible selections without desired or ownership mutations.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create the isolated project lock. |
| `c-plugin plugin add` | Reject invalid plugin source arguments. |
| `c-plugin skill add` | Reject invalid standalone source arguments. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:OWNER/REPO[/PATH]`, `local:./PATH` | Require exactly one explicitly typed positional source, with the GitHub subpath inside that same operand. |
| Bare `OWNER/REPO`, HTTPS URL, or `./PATH` | Reject source-kind inference when the mandatory prefix is missing. |
| `--github`, `--local`, `--path` | Reject retired options, rather than treating them as alternative source selectors. |
| `--ref` | Reject a Git ref for a local source, a missing source, or a revision-expression ref. |
| `--all`, `--none`, `--skill alpha` | Reject mutually incompatible plugin selections. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-parser-invalid/home` and the project is `$HOME/project`.
Initialization produces an empty version `3` lock and no ownership state.
Parser and typed-input rejections must not install hosted sources or managed links.

### Execution flow

1. Run `c-plugin init` and save exact lock bytes.
2. Run `c-plugin plugin add --github totto2727-org/c-plugin --all`.
3. Run `c-plugin skill add --local ./solo`.
4. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --path test/fixtures/github/plugin --all`.
5. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --local ./plugin --all`.
6. Run `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo --local ./solo`.
7. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin local:./plugin --all`.
8. Run `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo local:./solo`.
9. Run `c-plugin plugin add local:./plugin --ref haskell/iris-port --all`.
10. Run `c-plugin skill add local:./solo --path test/fixtures/github/solo`.
11. Run `c-plugin plugin add --ref haskell/iris-port --all`.
12. Run `c-plugin skill add --ref haskell/iris-port`.
13. Run `c-plugin plugin add totto2727-org/c-plugin --all`.
14. Run `c-plugin skill add https://github.com/totto2727-org/c-plugin`.
15. Run `c-plugin skill add ./solo`.
16. Run `c-plugin plugin add github:owner --all`.
17. Run `c-plugin skill add github:https://example.com/owner/repo`.
18. Run `c-plugin skill add github:https://github.com/owner/repo?ref=main`.
19. Run `c-plugin plugin add github:totto2727-org/c-plugin/../plugin --all`.
20. Run `c-plugin skill add github:totto2727-org/c-plugin//tmp/solo`.
21. Run `c-plugin skill add github:totto2727-org/c-plugin/.git`.
22. Run `c-plugin skill add local:/tmp/solo`.
23. Run `c-plugin skill add local:solo`.
24. Run `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo --ref 'HEAD^{commit}'`, passing the ref as one argv value.
25. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --all --none`.
26. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --all --skill alpha`.
27. After every rejection, compare exact lock bytes and verify missing ownership, alpha, and solo paths.

### Expected results

Every add exits nonzero.
The initialized lock stays byte-identical, and no ownership state or managed alpha/solo link is created.
Sources without the mandatory prefix never become inferred local or GitHub sources.

### Notes

Retired flags appear only as explicit rejection fixtures, never as positive command forms.
These assertions target c-plugin source policy and persistence, not upstream Iris parser conformance or exact help-text rendering.

## `githubSourceFailureScenario`

### Scope

Reject repository-root inference, collection inference, missing subdirectories, unknown refs, and unavailable repositories without persisting a candidate.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create the project lock. |
| `c-plugin plugin add` | Reject invalid explicit GitHub plugin sources. |
| `c-plugin skill add` | Reject invalid explicit standalone sources. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:totto2727-org/c-plugin[/PATH]` | Use the real public repository with an explicit subpath inside the source operand. |
| `github:totto2727-org/c-plugin-e2e-repository-that-does-not-exist/test/fixtures/github/solo` | Exercise unavailable repository failure. |
| `--ref haskell/iris-port` | Fetch the fixture branch. |
| `--ref c-plugin-e2e-ref-that-does-not-exist` | Exercise ref-resolution failure. |
| Source suffix `test/fixtures/github`, `test/fixtures/github/missing`, or `test/fixtures/github/plugin` | Select a collection, missing directory, or valid root without a separate path flag. |
| `--all` | Supply deterministic plugin selection. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-source-failure/home` and the project is `$HOME/project`.
The real fixture branch has a plugin at `test/fixtures/github/plugin` and solo at `test/fixtures/github/solo`, but no repository-root plugin or collection-level standalone manifest.

### Execution flow

1. Run `c-plugin init` and save the exact lock bytes.
2. Run `c-plugin plugin add github:totto2727-org/c-plugin --ref haskell/iris-port --all` without a subpath.
3. Run `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github --ref haskell/iris-port`.
4. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/missing --ref haskell/iris-port --all`.
5. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --ref c-plugin-e2e-ref-that-does-not-exist --all`.
6. Run `c-plugin skill add github:totto2727-org/c-plugin-e2e-repository-that-does-not-exist/test/fixtures/github/solo`.
7. After each invocation, inspect exit status, exact lock bytes, and missing ownership and links.

### Expected results

All adds fail and leave desired state byte-identical.
No ownership state or alpha/solo link appears.

### Notes

An already downloaded snapshot is not desired-state installation and may remain after validation failure.
The positive lifecycle scenarios separately prove that the fixture ref and HTTPS transport are usable.

## `githubPluginLifecycleScenario`

### Scope

Install a standard GitHub plugin from a nested working directory, verify pinned origin and source containment, preserve an exact same-commit no-op, change the enabled skill set, and remove the registration without deleting the cached source.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project lock. |
| `c-plugin plugin add` | Install and configure the explicit GitHub plugin. |
| `c-plugin skill sync` | Restore an externally removed managed link. |
| `c-plugin skill remove` | Remove the plugin registration. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:totto2727-org/c-plugin/test/fixtures/github/plugin` | Install using an explicitly typed repository and plugin subpath. |
| `github:https://github.com/totto2727-org/c-plugin/test/fixtures/github/plugin` | Exercise prefixed HTTPS location normalization with the same explicit subpath. |
| `--ref haskell/iris-port` | Resolve the fixture branch and preserve its requested-ref identity on re-add. |
| `--all`, `--skill beta`, `--none` | Install both skills, narrow to beta, then disable all. |
| `--plugin github-demo` | Remove the installed plugin by manifest identity. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-plugin-lifecycle/home` and the project is `$HOME/project`.
The hosted standard plugin has canonical schema, name `github-demo`, and valid alpha/beta skills.
Its fixed cache is inside the owning project root at `.agents/c-plugin/sources/totto2727-org/c-plugin/COMMIT/tree/test/fixtures/github/plugin`.

### Execution flow

1. Run `c-plugin init` and create `project/nested`.
2. From `project/nested`, run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --ref haskell/iris-port --all`.
3. Decode the lock, capture `COMMIT`, validate canonical source and origin, and verify both managed skill links.
4. Save exact lock and ownership bytes, then delete only the alpha link.
5. Run `c-plugin plugin add github:https://github.com/totto2727-org/c-plugin/test/fixtures/github/plugin --ref haskell/iris-port --all`.
6. Compare exact persisted bytes and verify that alpha remains absent until `c-plugin skill sync` restores it.
7. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --ref haskell/iris-port --skill beta` and inspect the enabled set and links.
8. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --ref haskell/iris-port --none` and verify no enabled skills or beta link.
9. Run `c-plugin skill remove --plugin github-demo` and inspect empty desired/ownership state and retained cached manifest.

### Expected results

All commands succeed.
The origin identifies GitHub, the canonical repository, and an immutable hexadecimal commit; the relative source is the exact contained snapshot path.
The source manifest matches the maintained standard fixture and both initial links resolve into that snapshot.
Same-commit re-add preserves exact lock/ownership bytes and does not implicitly synchronize the missing link.
Selection changes remove only the disabled owned links.
Final removal empties the lock and ownership entries without deleting the source snapshot.

### Notes

The test never assumes a final published fixture commit and distinguishes source installation from selection configuration and explicit synchronization.
The caller keeps the fixture branch stable during execution so identical requested refs resolve to the observed commit.

## `githubStandaloneOfflineScenario`

### Scope

Install a direct standalone GitHub skill without a plugin manifest, preserve an exact same-commit no-op, synchronize from the pinned snapshot with network transports blocked, and remove only managed state.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project lock. |
| `c-plugin skill add` | Install the direct GitHub standalone root. |
| `c-plugin skill sync` | Restore a missing link using cached data only. |
| `git ls-remote` | Confirm the configured offline environment cannot fetch the real hosted ref. |
| `c-plugin skill remove` | Remove the bare standalone identity. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:https://github.com/totto2727-org/c-plugin/test/fixtures/github/solo`, `github:totto2727-org/c-plugin/test/fixtures/github/solo` | Exercise equivalent explicitly typed locations containing the standalone subpath. |
| `--ref haskell/iris-port` | Resolve the fixture branch and repeat the identical requested ref. |
| `--skill solo` | Remove the bare standalone name. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-standalone-offline/home` and the project is `$HOME/project`.
The hosted solo fixture has a valid `SKILL.md` and no `plugin.json`.
The scenario records the source file checksum and exact desired/ownership bytes before testing the no-op and offline sync.

### Execution flow

1. Run `c-plugin init` and `c-plugin skill add github:https://github.com/totto2727-org/c-plugin/test/fixtures/github/solo --ref haskell/iris-port`.
2. Inspect origin, immutable source, solo link, and absent source plugin manifest, then save bytes and checksum.
3. Delete only the managed solo link.
4. Run `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo --ref haskell/iris-port` and compare exact state, leaving the link absent.
5. Run `git ls-remote https://github.com/totto2727-org/c-plugin refs/heads/haskell/iris-port` with uppercase/lowercase HTTP(S)/all-proxy variables pointing to `127.0.0.1:1` and empty uppercase/lowercase no-proxy exemptions, and require a nonzero result.
6. Run `c-plugin skill sync` with exactly the same proxy environment.
7. Verify restored solo, unchanged desired bytes, and unchanged source checksum.
8. Run `c-plugin skill remove --skill solo` and verify empty desired state, absent managed link, and retained snapshot checksum.

### Expected results

All CLI commands succeed.
The same-commit add does not rewrite or reconcile persisted state.
The real Git network probe fails in the same proxy environment where CLI sync succeeds.
Sync restores solo without a usable HTTP(S) proxy while retaining local Git integrity checks.
Removal does not delete or modify the immutable source.

### Notes

The initial add uses actual HTTPS GitHub cloning; only the later explicit sync blocks transports.
This is an offline cache regression, not a mocked source-resolution test.

## `githubGlobalScenario`

### Scope

Keep project and global GitHub standalone snapshots, desired state, ownership state, and links independent while invoking global commands from a nested project directory.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin skill add` | Install project and global standalone snapshots. |
| `c-plugin skill sync` | Reconcile only global state. |
| `c-plugin skill remove` | Remove only the global skill. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Select HOME-owned state and cache. |
| `github:totto2727-org/c-plugin/test/fixtures/github/solo`, `github:https://github.com/totto2727-org/c-plugin/test/fixtures/github/solo` | Use equivalent explicitly typed standalone source operands. |
| `--ref haskell/iris-port`, `--ref COMMIT` | Install the observed project commit in both scopes. |
| `--skill solo` | Remove only the global registration. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-global/home`, project is `$HOME/project`, and commands later run from `project/nested`.
Both scopes start empty and install the same hosted solo identity into separate lock-owned cache roots.

### Execution flow

1. Run `c-plugin init`, `c-plugin init --global`, and `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo --ref haskell/iris-port` from the project.
2. Capture `COMMIT` and exact project lock/ownership bytes, then create the nested directory.
3. From the nested directory, run `c-plugin skill add --global github:https://github.com/totto2727-org/c-plugin/test/fixtures/github/solo --ref COMMIT`.
4. Compare source roots and verify the global solo link resolves into HOME's cache, not the project's cache.
5. From the nested directory, run `c-plugin skill sync --global` and `c-plugin skill remove --global --skill solo`.
6. Verify empty global lock and absent global link, then compare exact project bytes and its intact link.

### Expected results

All commands succeed.
The global and project source directories differ and are contained in their respective owning roots.
Global sync/removal do not alter project desired state, ownership state, or solo link.

### Notes

The global source is fetched independently rather than borrowing the project's snapshot.

## `githubCacheSafetyScenario`

### Scope

Reject a redirected source-cache ancestor even with force, verify snapshot provenance, and preserve installed links and desired/ownership bytes when provenance or the Git remote becomes foreign.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project lock. |
| `c-plugin skill add` | Reject unsafe cache roots and install a valid snapshot. |
| `c-plugin skill sync` | Preserve links when cached source integrity is unavailable. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:totto2727-org/c-plugin/test/fixtures/github/solo` | Select the hosted standalone fixture in one explicitly typed operand. |
| `--ref haskell/iris-port` | Resolve the published branch. |
| `--force` | Confirm force cannot authorize cache-root redirection. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-cache-safety/home` and the project is `$HOME/project`.
A foreign `$HOME/outside/sentinel` exists, and `.agents/c-plugin/sources` initially symlinks to that outside directory.
After rejecting the redirected cache, the scenario removes only its synthetic symlink and installs a real snapshot.
The authoritative snapshot root contains `origin.json` with version `1`, repository, and observed commit, and `tree/.git` with the fixed remote identity.

### Execution flow

1. Run `c-plugin init`, create the sentinel and synthetic cache symlink, and save exact lock bytes.
2. Run `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo --ref haskell/iris-port --force`.
3. Verify failure, exact lock bytes, absent ownership state and outside repository directory, preserved sentinel, and unchanged cache symlink.
4. Remove only that synthetic symlink and run `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo --ref haskell/iris-port`.
5. Verify snapshot provenance and save exact provenance, desired state, ownership state, and source checksum.
6. Replace only provenance repository with `foreign/repository` and run `c-plugin skill sync`.
7. Compare persisted bytes, foreign provenance, solo link, and source checksum.
8. Restore provenance, use infrastructure Git to change only the snapshot origin URL to `https://github.com/foreign/repository.git`, and run `c-plugin skill sync` again.
9. Compare desired/ownership bytes, solo link, source checksum, remaining Git remote, and sentinel.

### Expected results

The redirected-cache add fails safely and does not mutate the foreign directory.
The valid add succeeds with exact version `1` provenance matching the lock commit.
Each integrity-invalid sync succeeds with a partial-result notice while preserving installed links, lock, ownership, source content, and foreign cache metadata.

### Notes

Infrastructure Git modifies only the disposable snapshot to simulate ownership/integrity loss.
The test does not authorize repair, adoption, cache deletion, or outside-root mutation.

## `githubForceSafetyScenario`

### Scope

Apply explicit add force only to an eligible exact file collision while preserving a real directory and an unrelated neighbor, then safely remove the installed GitHub plugin.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project lock. |
| `c-plugin plugin add` | Install the standard GitHub plugin with explicit force. |
| `c-plugin skill remove` | Remove only the managed plugin links and registration. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `github:totto2727-org/c-plugin/test/fixtures/github/plugin` | Select the real plugin fixture in one explicitly typed source operand. |
| `--ref haskell/iris-port` | Resolve the published fixture branch. |
| `--all`, `--force` | Enable both skills and force only eligible exact collisions. |
| `--plugin github-demo` | Remove the installed plugin identity. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-force-safety/home` and the project is `$HOME/project`.
Before installation, `.agents/skills/alpha` is a real directory containing `keep`, beta is a contained regular file, and neighbor is an unrelated regular file.
Their synthetic contents are asserted exactly after installation and removal.

### Execution flow

1. Run `c-plugin init` and create the three foreign collision fixtures.
2. Run `c-plugin plugin add github:totto2727-org/c-plugin/test/fixtures/github/plugin --ref haskell/iris-port --all --force`.
3. Inspect GitHub origin/source, preserved real alpha directory and its file, unchanged neighbor, and replaced beta symlink.
4. Run `c-plugin skill remove --plugin github-demo`.
5. Verify empty desired lock and missing beta while alpha/keep and neighbor remain byte-identical.

### Expected results

Installation and removal succeed.
The real alpha directory is never deleted or adopted.
Only the eligible beta collision becomes an owned snapshot link and is later cleaned up.
The foreign neighbor is never changed.

### Notes

Partial synchronization is allowed for the alpha directory collision; force does not broaden deletion eligibility.

## `topLevelSyncUpdateRecursiveScenario`

### Scope

Verify top-level sync and update restore both plugin and standalone links, including unchanged-commit update without lock replacement.
Verify recursive commands apply to independent descendant locks using the inspected historical Admiral 0.6.2 directory-discovery semantics, with deliberate Git metadata and pinned-source-cache safety exclusions.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the owning project lock. |
| `git ls-remote` | Observe the immutable commit of the published fixture branch. |
| `c-plugin plugin add` | Install the hosted standard plugin at that commit. |
| `c-plugin skill add` | Install the hosted standalone skill at that commit. |
| `c-plugin sync` | Reconcile both source domains using pinned snapshots. |
| `c-plugin update` | Refresh both source domains and reconcile even when the commit is unchanged. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `https://github.com/totto2727-org/c-plugin`, `refs/heads/haskell/iris-port` | Resolve the exact hosted branch with infrastructure Git. |
| `github:https://github.com/totto2727-org/c-plugin.git/test/fixtures/github/plugin` | Exercise the mandatory source prefix, optional repository suffix, and explicit plugin subpath. |
| `github:totto2727-org/c-plugin/test/fixtures/github/solo` | Select the standalone root with the mandatory source prefix and explicit subpath. |
| `--ref COMMIT` | Use the observed immutable commit for both installed domains. |
| `--all` | Enable alpha and beta. |
| `-r` | Traverse locks below the nearest owning project lock. |
| `--global` | Reject combination with recursive traversal for both top-level commands. |

### Preconditions and fixtures

`HOME=/tmp/c-plugin-github-top-level-recursive/home` and project is `$HOME/project`.
The scenario resolves the public fixture branch to a real immutable commit and installs github-demo and solo with that same commit.
The project lock therefore contains both domains, with cached sources inside the project rather than synthetic transport replacements.
Exact lock and ownership bytes plus lock inode/modification-second identity are captured before repair checks.
Child has an independent local standard demo plugin with child-skill and a standalone solo root.
Additional visible directories contain empty version `3` locks, while deliberately excluded directories contain malformed locks so accidental discovery fails visibly.

| Directory fixture | Discovery expectation |
| --- | --- |
| Project and child | Included even with `c-plugin-lock.json` in root ignore rules, because rules govern directory traversal only. |
| `.hidden-included` | Included without blanket hidden-directory filtering. |
| `comment-visible` | Included because the surrounding-whitespace comment is ignored. |
| `.hidden-excluded` | Excluded by the trimmed explicit directory rule. |
| `ignored-alpha`, `ignored-keep` | Excluded by the segment star; the negation line is unsupported and ignored. |
| `anchored`, `wrapped/anchored` | Both excluded because leading/trailing slashes are stripped rather than anchoring the rule. |
| `globstar/a/blocked` | Excluded by three-segment `globstar/**/blocked`. |
| `globstar/a/b/blocked` | Included because repeated stars do not cross path segments. |
| `wrapped/patterns/alpha/blocked` | Excluded because multi-segment rules match a contiguous window anywhere below their declaring directory. |
| `directory-scope/scoped` | Excluded by that directory's local trimmed rule. |
| `other/scoped` | Included because the local rule does not leak into a sibling subtree. |
| `question?`, `questionx` | The literal question-mark directory is excluded; questionx is included because `?` is not a wildcard. |
| `.git/trap`, `.agents/c-plugin/sources/discovery-trap` | Excluded by intentional metadata/cache safety pruning. |

A project symlink points to `$HOME/outside-project`, whose valid empty lock and absent ownership must stay unchanged.
`$HOME/missing-root` has only a descendant empty lock and no nearest ancestor lock.
No global HOME lock exists during the missing-root and global/recursive rejection checks.

### Execution flow

1. Run `c-plugin init` and `git ls-remote https://github.com/totto2727-org/c-plugin refs/heads/haskell/iris-port`, then validate the returned branch name and full hexadecimal `COMMIT`.
2. Run `c-plugin plugin add github:https://github.com/totto2727-org/c-plugin.git/test/fixtures/github/plugin --ref COMMIT --all` and `c-plugin skill add github:totto2727-org/c-plugin/test/fixtures/github/solo --ref COMMIT`.
3. Inspect both pinned origins, save exact lock/ownership bytes and Linux stat identity, and create `project/nested`.
4. Delete alpha, beta, and solo links, run `c-plugin sync` from the nested directory, and verify all three repaired links with unchanged lock/ownership bytes and lock identity.
5. Delete the same three links again, run `c-plugin update` from the nested directory, and verify the same repair and non-replacement guarantees despite identical resolved commits.
6. Create child sources and its complete local plugin/standalone lock, root and directory-local ignore rules, every visible/excluded fixture in the table, and the synthetic outside-project symlink.
7. Delete both parent-domain links and both child-domain links, run `c-plugin sync -r` from the nested directory, and inspect included paths, root-first ordering, excluded malformed fixtures, scope-specific repaired links, and unchanged desired bytes/parent lock identity.
8. Delete the same links again, run `c-plugin update -r` from the nested directory, and repeat those checks, including local-only descendant reconciliation.
9. Create only `missing-root/child/c-plugin-lock.json`, run `c-plugin sync -r` from missing-root, then `c-plugin sync --global -r` from project, and verify rejection and non-mutation after each invocation.
10. In the same order, run `c-plugin update -r` from missing-root, then `c-plugin update --global -r` from project, and repeat rejection and non-mutation checks.

### Expected results

Initial installation, nonrecursive sync/update, and recursive sync/update succeed.
Both hosted origins pin exactly the observed immutable commit, and all managed links resolve to their owning scope's sources.
Unchanged-commit update repairs missing links in both domains while preserving lock bytes and inode identity rather than rewriting an equal candidate.
Recursive stdout reports every expected visible lock after the owning root and no excluded lock or symlink subtree.
Every malformed excluded lock stays exact and creates no ownership state.
Child plugin and standalone links are reconciled independently without borrowing parent sources.
Missing-root commands fail with `LockFileNotFound`, leaving their descendant lock unchanged and no ownership state.
Global/recursive combinations fail with `--global cannot be combined with --recursive`, without creating a global lock/state or changing parent/child desired state.

### Notes

The historical dependency's actual cached `totto2727/admiral` version `0.6.2` implementation and tests were inspected before constructing these expectations.
Its matcher is deliberately traversal-only and is not a full Gitignore matcher: negations, anchored semantics, globstar, question-mark wildcards, and backslash escaping are unsupported.
The explicit `.git` and pinned-source-cache exclusions are safety exceptions, not a claim of complete upstream behavior equivalence.
The cache trap is a sibling under sources, outside any committed snapshot tree, so testing discovery does not corrupt a tracked GitHub source.
The historical nearest-parent requirement is preserved: descendant locks alone do not establish a recursive project root.
