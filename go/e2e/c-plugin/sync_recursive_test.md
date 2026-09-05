# Synchronize nested project locks recursively

Source: [sync_recursive_test.go](./sync_recursive_test.go)

The Source link identifies the implementation described below. Until the owning feature layer introduces Go source, it points to the immutable saved snapshot.

## `syncRecursiveScenario`

### Scope

`syncRecursiveScenario` verifies recursive lock discovery, gitignore handling, parent/child isolation, stale parent cleanup, lock non-mutation, and rejection of conflicting global/recursive flags.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill sync` | Reconcile desired links without rewriting the lock. |

### Arguments and options

| Argument or option  | Purpose                                                             |
| ------------------- | ------------------------------------------------------------------- |
| `-r`, `--recursive` | Traverse from the project root and synchronize every eligible lock. |
| `-g` with `-r`      | Exercise the invalid global-plus-recursive combination.             |

### Preconditions and fixtures

- Each case uses a separate `c-plugin-e2e:local` container. `HOME=/tmp/c-plugin-v2-sync-recursive-e2e/home` and `project=$HOME/project`.
- `c-plugin` in the commands below is the exact executable `/sandbox/.local/bin/c-plugin`; the helper passes argv directly, not through a scenario shell script.
- Parent and child projects have separate marketplaces and locks selecting alpha and beta respectively.
- The parent `.gitignore` excludes `ignored/`, which contains an intentionally malformed lock.
- A foreign file already exists in the parent primary target.

### Execution flow

1. Write parent/child locks and marketplaces, the ignored malformed lock, `.gitignore`, and foreign parent file. Record both valid lock digests.
2. Run `c-plugin skill sync -r` from `project`.
3. Verify exactly two `Synced` lines, parent/child links and state, omission of the ignored lock, foreign-file contents, and unchanged digests.
4. Rewrite only the parent lock to select no skills and record its new digest. Run `c-plugin skill sync --recursive` from `project`.
5. Verify two synchronized locks, removed parent alpha, preserved child beta and ownership, preserved foreign file, and unchanged digests relative to each current lock input.
6. Run `c-plugin skill sync -g -r` from `project`; require nonzero status and `totto2727/c-plugin.SyncError.Planning`.

### Expected results

| Observation   | Expected result                                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Discovery     | Exactly two `Synced` lines name parent and child; the ignored malformed lock is never mentioned.                                           |
| Initial state | Parent alpha and child beta links/state exist; both lock digests remain unchanged.                                                         |
| Edited state  | Parent alpha is removed, child beta and its state remain, the foreign parent file remains, and each lock digest matches its current input. |
| Invalid flags | Nonzero exit with `totto2727/c-plugin.SyncError.Planning`.                                                                              |

### Notes

- Parent and child locks are isolated desired-state roots even though one command discovers both.

- Output expectations refer to the helper's captured `cli.Result.Stdout`; these tests do not assert a separate stderr stream.
- These are assertions in the pinned source, not execution results from this documentation-only layer.
