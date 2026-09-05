# Remove project and global target roots

Source: [target_remove_test.go](./target_remove_test.go)

## Scope

`targetRemoveScenario` verifies empty and unknown no-ops, normalized project removals, last-additional-target cleanup, foreign-neighbor preservation, primary-target isolation, and global removal.

## Commands under test

| Command                                        | Purpose                                                       |
| ---------------------------------------------- | ------------------------------------------------------------- |
| `c-plugin skill sync`                          | Materialize configured targets before removal.                |
| `c-plugin skill target remove`                 | Exercise the empty-selection no-op.                           |
| `c-plugin skill target remove --target <path>` | Remove unknown, normalized, project, and global target roots. |

## Arguments and options

| Argument or option                 | Purpose                                     |
| ---------------------------------- | ------------------------------------------- |
| `--target .vscode/skills`          | Verify an unknown target is a no-op.        |
| `--target .cursor/./skills`        | Normalize and remove the cursor target.     |
| `--target .claude/skills`          | Remove the final additional project target. |
| `--global --target .cursor/skills` | Select and mutate the global lock only.     |

## Preconditions and fixtures

- The project lock selects alpha and configures `.cursor/skills` plus `.claude/skills`; an initial sync creates all links and state.
- A foreign `neighbor` file is added under the cursor root after sync.
- A separate global lock selects beta and configures `.cursor/skills`.

## Execution flow

1. Record project lock/state digests, then run unknown and empty removals.
2. Remove normalized cursor, verify remaining roots, then remove Claude.
3. Sync the global lock from a nested project directory and remove its cursor target with `--global`.

## Expected results

| Phase          | Expected result                                                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Unknown/empty  | Exit 0 with `No target changes for <lock>`; lock and state digests remain unchanged.                                                     |
| Cursor removal | Complete success; cursor alpha is removed, foreign neighbor remains, and default/Claude alpha links and state remain.                    |
| Claude removal | Complete success; project lock has no additional targets, Claude alpha is removed, default alpha remains, and removed roots leave state. |
| Global removal | Complete success; global cursor beta is removed, default global beta remains, and the global cursor root leaves ownership state.         |

## Notes

- Removing an additional target never removes the default `.agents/skills` target or foreign files that are not owned links.
