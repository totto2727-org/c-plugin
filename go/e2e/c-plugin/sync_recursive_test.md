# Synchronize nested project locks recursively

Source: [sync_recursive_test.go](./sync_recursive_test.go)

## Scope

`syncRecursiveScenario` verifies recursive lock discovery, gitignore handling, parent/child isolation, stale parent cleanup, lock non-mutation, and rejection of conflicting global/recursive flags.

## Commands under test

| Command                           | Purpose                                                  |
| --------------------------------- | -------------------------------------------------------- |
| `c-plugin skill sync -r`          | Discover and synchronize parent and child project locks. |
| `c-plugin skill sync --recursive` | Repeat recursively after editing only the parent lock.   |
| `c-plugin skill sync -g -r`       | Verify conflicting scope flags fail during planning.     |

## Arguments and options

| Argument or option  | Purpose                                                             |
| ------------------- | ------------------------------------------------------------------- |
| `-r`, `--recursive` | Traverse from the project root and synchronize every eligible lock. |
| `-g` with `-r`      | Exercise the invalid global-plus-recursive combination.             |

## Preconditions and fixtures

- Parent and child projects have separate marketplaces and locks selecting alpha and beta respectively.
- The parent `.gitignore` excludes `ignored/`, which contains an intentionally malformed lock.
- A foreign file already exists in the parent primary target.

## Execution flow

1. Hash both locks and run recursive sync with `-r`.
2. Verify exactly two synchronized locks, their links/state, the ignored-lock omission, and foreign-file preservation.
3. Edit only the parent lock to select no skills and run with `--recursive`.
4. Run the conflicting `-g -r` form.

## Expected results

| Observation   | Expected result                                                                                                                            |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Discovery     | Exactly two `Synced` lines name parent and child; the ignored malformed lock is never mentioned.                                           |
| Initial state | Parent alpha and child beta links/state exist; both lock digests remain unchanged.                                                         |
| Edited state  | Parent alpha is removed, child beta and its state remain, the foreign parent file remains, and each lock digest matches its current input. |
| Invalid flags | Nonzero exit with `totto2727/c-plugin.SyncError.Planning`.                                                                              |

## Notes

- Parent and child locks are isolated desired-state roots even though one command discovers both.
