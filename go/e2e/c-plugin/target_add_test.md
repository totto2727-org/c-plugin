# Add project and global target roots

Source: [target_add_test.go](./target_add_test.go)

## Scope

`targetAddScenario` verifies project and global target registration, path normalization, duplicate no-op behavior, immediate reconciliation, and ownership state for additional roots.

## Commands under test

| Command                                             | Purpose                                                                          |
| --------------------------------------------------- | -------------------------------------------------------------------------------- |
| `c-plugin skill target add .cursor/skills`          | Add an additional project target and synchronize it.                             |
| `c-plugin skill target add .cursor/./skills`        | Verify normalized duplicate detection.                                           |
| `c-plugin skill target add .claude/skills --global` | Add and synchronize an additional global target from a nested project directory. |

## Arguments and options

| Argument or option | Purpose                                             |
| ------------------ | --------------------------------------------------- |
| `.cursor/skills`   | Register a project-relative managed root.           |
| `.cursor/./skills` | Normalize to the already registered project target. |
| `.claude/skills`   | Register a second global managed root.              |
| `--global`         | Discover and mutate the lock under `HOME`.          |

## Preconditions and fixtures

- The project lock selects alpha from a local marketplace and initially has no additional targets.
- A separate global lock selects beta from a global marketplace.
- The global command runs from a nested project directory to prove scope selection.

## Execution flow

1. Add `.cursor/skills` to the project lock and inspect links and ownership state.
2. Record lock/state digests and add the normalized duplicate `.cursor/./skills`.
3. Add `.claude/skills` to the global lock with `--global`.

## Expected results

| Phase       | Expected result                                                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Project add | Exit 0 with one notice; lock contains `.cursor/skills`; alpha is linked in default and cursor roots, both recorded in state.               |
| Duplicate   | Exit 0 with `Target .cursor/skills already registered`; lock and state digests are unchanged.                                              |
| Global add  | Exit 0 with one notice; global lock contains `.claude/skills`; beta is linked in default and Claude roots, with Claude ownership recorded. |

## Notes

- Target registration performs persistence and reconciliation in one command; the duplicate path skips both operations.
