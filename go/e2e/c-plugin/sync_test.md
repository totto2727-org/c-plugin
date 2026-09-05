# Synchronize desired skills and reconcile stale links

Source: [sync_test.go](./sync_test.go)

The Source link identifies the implementation described below. Until the owning feature layer introduces Go source, it points to the immutable saved snapshot.

## `syncScenario`

### Scope

`syncScenario` verifies initial synchronization to primary and additional targets, unchanged lock bytes, ownership recording, stale-link cleanup, and foreign-path preservation.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill sync` | Reconcile desired links without rewriting the lock. |

### Arguments and options

This scenario uses no command options. It relies on project lock discovery from the working directory and executes the same command before and after editing desired state.

### Preconditions and fixtures

- Each case uses a separate `c-plugin-e2e:local` container. `HOME=/tmp/c-plugin-v2-sync-e2e/home` and `project=$HOME/project`.
- `c-plugin` in the commands below is the exact executable `/sandbox/.local/bin/c-plugin`; the helper passes argv directly, not through a scenario shell script.
- `HOME` is isolated under `/tmp/c-plugin-v2-sync-e2e/home`.
- The local marketplace provides alpha and beta.
- The project lock selects both skills and adds `.cursor/skills` to the default `.agents/skills` target.

### Execution flow

1. Write the two-skill project lock with additional `.cursor/skills`, record its digest, and run `c-plugin skill sync` from `project`.
2. Verify the output substring, unchanged lock digest, four symlinks, and alpha/beta ownership records.
3. Replace the primary beta symlink with a foreign file, add the foreign neighbor, and rewrite the lock fixture with no selected skills. Record this edited lock digest.
4. Run `c-plugin skill sync` again from `project`.
5. Verify the same asserted partial-output substring, unchanged edited lock digest, removal of safely owned links, preservation of foreign beta/neighbor contents, and empty version-1 ownership state.

### Expected results

| Phase           | Expected result                                                                                                               |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Initial sync    | Exit 0; stdout contains `partial (1 notices, 0 unavailable repositories)`; four desired symlinks point to marketplace skills. |
| Lock integrity  | Neither sync rewrites the lock; its digest equals the value recorded before that invocation.                                  |
| Edited sync     | Owned alpha links and cursor beta are removed; replacement beta and neighbor remain regular files.                            |
| Ownership state | State is reduced to `{"version":"1","entries":[]}` after all safe owned links are gone.                                       |


The edited sync also asserts exit 0 and `Synced <lock>: partial (1 notices, 0 unavailable repositories)`.

### Notes

- The notice count reflects target-root creation/reconciliation details; the test intentionally asserts the stable output substring rather than the entire line.

- Output expectations refer to the helper's captured `cli.Result.Stdout`; these tests do not assert a separate stderr stream.
- These are assertions in the pinned source, not execution results from this documentation-only layer.
