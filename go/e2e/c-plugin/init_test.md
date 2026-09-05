# Initialize project and global locks

Source: [init_test.go](./init_test.go)

## Scope

`initProjectScenario` and `initGlobalScenario` select project/global behavior through the shared `initScenario` workflow, verifying lock placement, short and long global flags, duplicate rejection, and absence of sync side effects.

## Commands under test

| Scenario | Initial command    | Repeat command           |
| -------- | ------------------ | ------------------------ |
| Project  | `c-plugin init`    | `c-plugin init`          |
| Global   | `c-plugin init -g` | `c-plugin init --global` |

## Arguments and options

| Argument or option | Purpose                                                          |
| ------------------ | ---------------------------------------------------------------- |
| no global flag     | Create `c-plugin-lock.json` in the current project.              |
| `-g`               | Create the first global lock in `HOME`.                          |
| `--global`         | Exercise the equivalent long-form flag on the duplicate attempt. |

## Preconditions and fixtures

- Each scenario runs in a fresh container with `HOME=/tmp/c-plugin-v2-init-e2e/home`.
- The project directory is `/tmp/c-plugin-v2-init-e2e/totto2727-org/monorepo` and neither project nor global lock exists.
- No marketplace, ownership state, cache, or managed skill directory is pre-created.

## Execution flow

1. Run the initial project or global `init` command.
2. Hash the created lock and verify the opposite-scope lock is absent.
3. Run the same scope again, using `--global` for the global repeat.
4. Recheck the lock digest and all possible sync-output directories.

## Expected results

| Observation         | Expected result                                                                                 |
| ------------------- | ----------------------------------------------------------------------------------------------- |
| Initial exit/output | Exit 0 with exactly `Created <lock path>` followed by a newline.                                |
| Lock content        | Canonical empty version 2 lock with no targets or repositories.                                 |
| Scope isolation     | Only the selected project or global lock exists.                                                |
| Repeat              | Nonzero exit containing `StateStoreError.AlreadyExists`; the original lock digest is unchanged. |
| Side effects        | No `.agents` directory and no `$HOME/.cache/c-plugin` directory is created.                     |

## Notes

- Project and global initialization are independent `cli.Case` values, so each receives its own container despite sharing this source file.
