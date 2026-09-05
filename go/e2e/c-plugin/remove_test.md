# Remove selected skills safely

Source: [remove_test.go](./remove_test.go)

## Scope

`removeScenario` verifies empty and unknown no-ops, normalized selection, repository pruning, foreign-path preservation, repeat idempotency, and global removal.

## Commands under test

| Command                                                   | Purpose                                                             |
| --------------------------------------------------------- | ------------------------------------------------------------------- |
| `c-plugin skill sync`                                     | Materialize the initial project or global lock.                     |
| `c-plugin skill remove`                                   | Exercise the empty-selection no-op.                                 |
| `c-plugin skill remove --skill <repository/plugin/skill>` | Remove known, unknown, normalized, repeated, and global selections. |

## Arguments and options

| Argument or option                               | Purpose                                                        |
| ------------------------------------------------ | -------------------------------------------------------------- |
| `--skill marketplace/demo/unknown`               | Confirm an unknown selection is an atomic no-op.               |
| `--skill marketplace/./demo/alpha`               | Confirm path normalization before identity matching.           |
| `--skill marketplace/demo/beta`                  | Remove the final project skill and prune the empty repository. |
| `--global --skill global-marketplace/demo/gamma` | Select and mutate only the global lock and managed root.       |

## Preconditions and fixtures

- The project lock selects alpha and beta from a local marketplace; an initial sync creates their managed links and ownership state.
- Alpha is replaced by a regular file and a foreign `neighbor` file is added before removal.
- A separate global marketplace and lock select gamma under `HOME`.

## Execution flow

1. Run empty and unknown removals and compare lock/state digests with the initial values.
2. Remove normalized alpha, then repeat alpha removal after recording new digests.
3. Remove beta, the final selected project skill.
4. Sync the global lock from a nested project directory and remove gamma with `--global`.

## Expected results

| Phase         | Expected result                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Empty/unknown | Exit 0 with `No skill changes for <lock>`; lock and state digests do not change.                                                |
| Alpha         | Partial success with one notice; the replacement file and neighbor remain, beta stays linked and owned, and alpha leaves state. |
| Repeat alpha  | Exit 0 no-op with unchanged lock and state digests.                                                                             |
| Beta          | Complete success; project lock becomes empty, beta link is removed, and foreign paths remain.                                   |
| Global gamma  | Complete success; the global lock becomes empty and the global gamma link/state entry is removed.                               |

## Notes

- A replaced managed path is treated as foreign and is not deletion authority.
