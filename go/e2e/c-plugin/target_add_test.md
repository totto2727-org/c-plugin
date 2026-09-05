# Add project and global target roots

Source: [target_add_test.go](./target_add_test.go)

The Source link identifies the implementation described below. Until the owning feature layer introduces Go source, it points to the immutable saved snapshot.

## `targetAddScenario`

### Scope

`targetAddScenario` verifies project and global target registration, path normalization, duplicate no-op behavior, immediate reconciliation, and ownership state for additional roots.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill target add` | Register a normalized additional target and synchronize it. |

### Arguments and options

| Argument or option | Purpose                                             |
| ------------------ | --------------------------------------------------- |
| `.cursor/skills`   | Register a project-relative managed root.           |
| `.cursor/./skills` | Normalize to the already registered project target. |
| `.claude/skills`   | Register a second global managed root.              |
| `--global`         | Discover and mutate the lock under `HOME`.          |

### Preconditions and fixtures

- Each case uses a separate `c-plugin-e2e:local` container. `HOME=/tmp/c-plugin-v2-target-add-e2e/home` and `project=$HOME/project`.
- `c-plugin` in the commands below is the exact executable `/sandbox/.local/bin/c-plugin`; the helper passes argv directly, not through a scenario shell script.
- The project lock selects alpha from a local marketplace and initially has no additional targets.
- A separate global lock selects beta from a global marketplace.
- The global command runs from a nested project directory to prove scope selection.

### Execution flow

1. Write the project marketplace and initial lock, then run `c-plugin skill target add .cursor/skills` from `project`.
2. Verify the lock target, both alpha symlinks, and both ownership roots; record lock/state digests.
3. Run `c-plugin skill target add .cursor/./skills` from `project` and verify normalized duplicate no-op output and unchanged digests.
4. Create a separate global marketplace and lock plus `project/nested`.
5. From `project/nested`, run `c-plugin skill target add .claude/skills --global`.
6. Verify the global output, `.claude/skills` registration, primary/Claude beta links, and additional-root ownership record.

### Expected results

`<lock>` is `$HOME/project/c-plugin-lock.json` and `<global-lock>` is `$HOME/c-plugin-lock.json`.

| Phase       | Expected result                                                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Project add | Exit 0 with exactly `Added target .cursor/skills to <lock>: partial (1 notices, 0 unavailable repositories)\n`; lock contains `.cursor/skills`; alpha is linked in default and cursor roots, both recorded in state.               |
| Duplicate   | Exit 0 with exactly `Target .cursor/skills already registered in <lock>\n`; lock and state digests are unchanged.                                              |
| Global add  | Exit 0 with exactly `Added target .claude/skills to <global-lock>: partial (1 notices, 0 unavailable repositories)\n`; global lock contains `.claude/skills`; beta is linked in default and Claude roots, with Claude ownership recorded. |

### Notes

- Target registration performs persistence and reconciliation in one command; the duplicate path skips both operations.

- Output expectations refer to the helper's captured `cli.Result.Stdout`; these tests do not assert a separate stderr stream.
- These are assertions in the pinned source, not execution results from this documentation-only layer.
