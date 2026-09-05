# Add local skills and handle collisions

Source: [add_test.go](./add_test.go)

## Scope

`addScenario` verifies local marketplace registration, duplicate rejection, removal, and forced replacement of an eligible collision while preserving a directory collision and its neighbor.

## Commands under test

| Command                                                                                       | Purpose                                                                            |
| --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `c-plugin init`                                                                               | Create the project lock before local registration.                                 |
| `c-plugin skill add --local ./marketplace --kind claude --skill demo/alpha --skill demo/beta` | Register two local skills from a nested working directory.                         |
| `c-plugin skill remove --skill marketplace/demo/alpha --skill marketplace/demo/beta`          | Remove both skills before the forced-add phase.                                    |
| `c-plugin skill add ... --force`                                                              | Replace an eligible regular-file collision while preserving a directory collision. |

## Arguments and options

| Argument or option                        | Purpose                                                                           |
| ----------------------------------------- | --------------------------------------------------------------------------------- |
| `--local ./marketplace`                   | Resolve the marketplace relative to the discovered project lock.                  |
| `--kind claude`                           | Parse `.claude-plugin/marketplace.json`.                                          |
| `--skill demo/alpha`, `--skill demo/beta` | Select the two fixture skills.                                                    |
| `--force`                                 | Replace the exact desired-link regular-file collision exercised in this scenario. |

## Preconditions and fixtures

- `HOME` is `/tmp/c-plugin-v2-add-e2e/home`; the project contains a two-skill local marketplace and a nested working directory.
- After `init`, a foreign regular file is created at `.agents/skills/alpha` before the first add.
- Before the forced add, the beta path is a real directory containing `keep`, and a separate `neighbor` file exists.

## Execution flow

1. Initialize the project and run the two-skill add from the nested directory.
2. Repeat the same add and verify rejection without lock or managed-link mutation.
3. Remove both selected skills, create the beta directory collision and foreign neighbor, then repeat add with `--force`.

## Expected results

| Phase           | Expected result                                                                                                                                                   |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Initial add     | Exit 0; stdout is `Added <repository> to <lock>: partial (2 notices, 0 unavailable repositories)`; beta is managed, while the foreign alpha file remains unowned. |
| Duplicate add   | Nonzero exit with `AddLocalError.InvalidInput`; the lock digest is unchanged, and the beta link and ownership entry still exist.                                  |
| Forced add      | Exit 0 with one notice; alpha becomes a symlink to the marketplace skill, beta remains a directory with its content, and `neighbor` remains unchanged.            |
| Ownership state | The final state contains alpha and excludes beta because only alpha was safely replaced.                                                                          |

## Notes

- The scenario distinguishes safe force replacement from directory and neighbor preservation; it does not authorize broad target-root cleanup.
