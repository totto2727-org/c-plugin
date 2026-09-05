# Add local skills and handle collisions

Source: [add_test.go](https://github.com/totto2727-org/c-plugin/blob/5d6f66a83be6ed23d16d3c8535722970e028a003/go/e2e/c-plugin/add_test.go)

The Source link identifies the implementation described below. Until the owning feature layer introduces Go source, it points to the immutable saved snapshot.

## `addScenario`

### Scope

`addScenario` verifies local marketplace registration, duplicate rejection, removal, and forced replacement of an eligible collision while preserving a directory collision and its neighbor.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create a new lock without synchronizing links. |
| `c-plugin skill add` | Register selected local skills and reconcile eligible links. |
| `c-plugin skill remove` | Remove selected skills while preserving foreign paths. |

### Arguments and options

| Argument or option                        | Purpose                                                                           |
| ----------------------------------------- | --------------------------------------------------------------------------------- |
| `--local ./marketplace`                   | Resolve the marketplace relative to the discovered project lock.                  |
| `--kind claude`                           | Parse `.claude-plugin/marketplace.json`.                                          |
| `--skill demo/alpha`, `--skill demo/beta` | Select the two fixture skills.                                                    |
| `--force`                                 | Replace the exact desired-link regular-file collision exercised in this scenario. |

### Preconditions and fixtures

- Each case uses a separate `c-plugin-e2e:local` container. `HOME=/tmp/c-plugin-v2-add-e2e/home` and `project=$HOME/project`.
- `c-plugin` in the commands below is the exact executable `/sandbox/.local/bin/c-plugin`; the helper passes argv directly, not through a scenario shell script.
- `HOME` is `/tmp/c-plugin-v2-add-e2e/home`; the project contains a two-skill local marketplace and a nested working directory.
- After `init`, a foreign regular file is created at `.agents/skills/alpha` before the first add.
- Before the forced add, the beta path is a real directory containing `keep`, and a separate `neighbor` file exists.

### Execution flow

1. From `project`, run `c-plugin init`, then create foreign alpha and the nested working directory.
2. From `project/nested`, run `c-plugin skill add --local ./marketplace --kind claude --skill demo/alpha --skill demo/beta` and inspect the lock, beta link, foreign alpha, and ownership state.
3. From the same directory, repeat `c-plugin skill add --local ./marketplace --kind claude --skill demo/alpha --skill demo/beta`; require rejection and unchanged lock digest with beta still linked and owned.
4. Run `c-plugin skill remove --skill marketplace/demo/alpha --skill marketplace/demo/beta` from `project/nested`; alpha remains foreign and beta is removed.
5. Create the real beta directory with `keep` and the foreign `neighbor` file, then run `c-plugin skill add --local ./marketplace --kind claude --skill demo/alpha --skill demo/beta --force` from `project/nested`.
6. Verify exact forced output, alpha replacement, beta directory contents, neighbor contents, and final ownership entries.

### Expected results

Here `<repository>` is `$HOME/project/marketplace` and `<lock>` is `$HOME/project/c-plugin-lock.json`. Exact output lines end in `\n`.

| Phase           | Expected result                                                                                                                                                   |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initial add     | Exit 0; stdout is `Added <repository> to <lock>: partial (2 notices, 0 unavailable repositories)`; beta is managed, while the foreign alpha file remains unowned. |
| Duplicate add   | Nonzero exit with `totto2727/c-plugin.AddLocalError.InvalidInput`; the lock digest is unchanged, and the beta link and ownership entry still exist.                                  |
| Forced add      | Exit 0; exactly `Added <repository> to <lock>: partial (1 notices, 0 unavailable repositories)\n`; alpha becomes a symlink to the marketplace skill, beta remains a directory with its content, and `neighbor` remains unchanged.            |
| Ownership state | The final state contains alpha and excludes beta because only alpha was safely replaced.                                                                          |

### Notes

- The scenario distinguishes safe force replacement from directory and neighbor preservation; it does not authorize broad target-root cleanup.

- Force runs only after the selected repository was removed. This scenario does not authorize a same-source force-repeat sync or union merge.

- Output expectations refer to the helper's captured `cli.Result.Stdout`; these tests do not assert a separate stderr stream.
- These are assertions in the pinned source, not execution results from this documentation-only layer.
