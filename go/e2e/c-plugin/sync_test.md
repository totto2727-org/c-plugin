# Synchronize desired skills and reconcile stale links

Source: [sync_test.go](./sync_test.go)

## Scope

`syncScenario` verifies initial synchronization to primary and additional targets, unchanged lock bytes, ownership recording, stale-link cleanup, and foreign-path preservation.

## Commands under test

| Command               | Purpose                                                              |
| --------------------- | -------------------------------------------------------------------- |
| `c-plugin skill sync` | Reconcile the discovered project lock with managed filesystem state. |

## Arguments and options

This scenario uses no command options. It relies on project lock discovery from the working directory and executes the same command before and after editing desired state.

## Preconditions and fixtures

- `HOME` is isolated under `/tmp/c-plugin-v2-sync-e2e/home`.
- The local marketplace provides alpha and beta.
- The project lock selects both skills and adds `.cursor/skills` to the default `.agents/skills` target.

## Execution flow

1. Hash the lock and run the initial sync.
2. Verify both skills in both target roots and confirm both ownership entries.
3. Replace the primary beta symlink with a foreign regular file, add a foreign neighbor, and edit the lock to select no skills.
4. Hash the edited lock and run sync again.

## Expected results

| Phase           | Expected result                                                                                                               |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Initial sync    | Exit 0; stdout contains `partial (1 notices, 0 unavailable repositories)`; four desired symlinks point to marketplace skills. |
| Lock integrity  | Neither sync rewrites the lock; its digest equals the value recorded before that invocation.                                  |
| Edited sync     | Owned alpha links and cursor beta are removed; replacement beta and neighbor remain regular files.                            |
| Ownership state | State is reduced to `{"version":"1","entries":[]}` after all safe owned links are gone.                                       |

## Notes

- The notice count reflects target-root creation/reconciliation details; the test intentionally asserts the stable output substring rather than the entire line.
