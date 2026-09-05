# Remove selected skills safely

Source: [remove_test.go](./remove_test.go)

The Source link identifies the implementation described below. Until the owning feature layer introduces Go source, it points to the immutable saved snapshot.

## `removeScenario`

### Scope

`removeScenario` verifies empty and unknown no-ops, normalized selection, repository pruning, foreign-path preservation, repeat idempotency, and global removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill sync` | Reconcile desired links without rewriting the lock. |
| `c-plugin skill remove` | Remove selected skills while preserving foreign paths. |

### Arguments and options

| Argument or option                               | Purpose                                                        |
| ------------------------------------------------ | -------------------------------------------------------------- |
| `--skill marketplace/demo/unknown`               | Confirm an unknown selection is an atomic no-op.               |
| `--skill marketplace/./demo/alpha`               | Confirm path normalization before identity matching.           |
| `--skill marketplace/demo/beta`                  | Remove the final project skill and prune the empty repository. |
| `--global --skill global-marketplace/demo/gamma` | Select and mutate only the global lock and managed root.       |

### Preconditions and fixtures

- Each case uses a separate `c-plugin-e2e:local` container. `HOME=/tmp/c-plugin-v2-remove-e2e/home` and `project=$HOME/project`.
- `c-plugin` in the commands below is the exact executable `/sandbox/.local/bin/c-plugin`; the helper passes argv directly, not through a scenario shell script.
- The project lock selects alpha and beta from a local marketplace; an initial sync creates their managed links and ownership state.
- Alpha is replaced by a regular file and a foreign `neighbor` file is added before removal.
- A separate global marketplace and lock select gamma under `HOME`.

### Execution flow

1. Write the project fixture lock and run `c-plugin skill sync` from `project`; replace alpha with a foreign file and add the neighbor, then record lock/state digests.
2. Run `c-plugin skill remove`, then `c-plugin skill remove --skill marketplace/demo/unknown` from `project`; compare lock and state digests.
3. Run `c-plugin skill remove --skill marketplace/./demo/alpha` from `project`; verify normalized removal and foreign-path preservation, then record new digests.
4. Run `c-plugin skill remove --skill marketplace/demo/alpha` from `project` and confirm the no-op output and unchanged digests.
5. Run `c-plugin skill remove --skill marketplace/demo/beta` from `project`; verify the empty lock, removed beta link, and preserved foreign paths.
6. Create the separate global marketplace/lock and `project/nested`; from that directory run `c-plugin skill sync --global`, then `c-plugin skill remove --global --skill global-marketplace/demo/gamma`.
7. Verify the global empty lock, absent gamma link, and removal of gamma from global ownership state.

### Expected results

`<lock>` is `$HOME/project/c-plugin-lock.json` and `<global-lock>` is `$HOME/c-plugin-lock.json`. Exact output lines end in `\n`.

| Phase         | Expected result                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Empty/unknown | Exit 0 with `No skill changes for <lock>`; lock and state digests do not change.                                                |
| Alpha         | Exit 0 with exactly `Removed skills marketplace/demo/alpha from <lock>: partial (1 notices, 0 unavailable repositories)\n`; the replacement file and neighbor remain, beta stays linked and owned, and alpha leaves state. |
| Repeat alpha  | Exit 0 no-op with unchanged lock and state digests.                                                                             |
| Beta          | Exit 0 with exactly `Removed skills marketplace/demo/beta from <lock>: complete (0 notices, 0 unavailable repositories)\n`; project lock becomes empty, beta link is removed, and foreign paths remain.                                   |
| Global gamma  | Exit 0 with exactly `Removed skills global-marketplace/demo/gamma from <global-lock>: complete (0 notices, 0 unavailable repositories)\n`; the global lock becomes empty and the global gamma link/state entry is removed.                               |

### Notes

- A replaced managed path is treated as foreign and is not deletion authority.

- Output expectations refer to the helper's captured `cli.Result.Stdout`; these tests do not assert a separate stderr stream.
- These are assertions in the pinned source, not execution results from this documentation-only layer.
