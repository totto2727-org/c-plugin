# Remove project and global target roots

Source: [target_remove_test.go](./target_remove_test.go)

The Source link identifies the implementation described below. Until the owning feature layer introduces Go source, it points to the immutable saved snapshot.

## `targetRemoveScenario`

### Scope

`targetRemoveScenario` verifies empty and unknown no-ops, normalized project removals, last-additional-target cleanup, foreign-neighbor preservation, primary-target isolation, and global removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin skill sync` | Reconcile desired links without rewriting the lock. |
| `c-plugin skill target remove` | Remove additional target registrations and safely owned links. |

### Arguments and options

| Argument or option                 | Purpose                                     |
| ---------------------------------- | ------------------------------------------- |
| `--target .vscode/skills`          | Verify an unknown target is a no-op.        |
| `--target .cursor/./skills`        | Normalize and remove the cursor target.     |
| `--target .claude/skills`          | Remove the final additional project target. |
| `--global --target .cursor/skills` | Select and mutate the global lock only.     |

### Preconditions and fixtures

- Each case uses a separate `c-plugin-e2e:local` container. `HOME=/tmp/c-plugin-v2-target-remove-e2e/home` and `project=$HOME/project`.
- `c-plugin` in the commands below is the exact executable `/sandbox/.local/bin/c-plugin`; the helper passes argv directly, not through a scenario shell script.
- The project lock selects alpha and configures `.cursor/skills` plus `.claude/skills`; an initial sync creates all links and state.
- A foreign `neighbor` file is added under the cursor root after sync.
- A separate global lock selects beta and configures `.cursor/skills`.

### Execution flow

1. Write the project marketplace and lock with cursor/Claude targets. Run `c-plugin skill sync` from `project`, add the foreign cursor neighbor, and record lock/state digests.
2. Run `c-plugin skill target remove --target .vscode/skills`, then `c-plugin skill target remove` from `project`; verify no-op output and unchanged digests.
3. Run `c-plugin skill target remove --target .cursor/./skills` from `project`; verify normalized removal, preserved neighbor, remaining roots, and ownership updates.
4. Run `c-plugin skill target remove --target .claude/skills` from `project`; verify the last additional target is removed while primary alpha and the foreign neighbor remain.
5. Create a separate global marketplace/lock and `project/nested`. From that directory, run `c-plugin skill sync --global`.
6. Run `c-plugin skill target remove --global --target .cursor/skills` from `project/nested`; verify cursor removal, preserved primary beta, the global lock, and ownership cleanup.

### Expected results

`<lock>` is `$HOME/project/c-plugin-lock.json` and `<global-lock>` is `$HOME/c-plugin-lock.json`. Exact output lines end in `\n`.

| Phase          | Expected result                                                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Unknown/empty  | Exit 0 with `No target changes for <lock>`; lock and state digests remain unchanged.                                                     |
| Cursor removal | Exit 0 with exactly `Removed targets .cursor/skills from <lock>: complete (0 notices, 0 unavailable repositories)\n`; cursor alpha is removed, foreign neighbor remains, and default/Claude alpha links and state remain.                    |
| Claude removal | Exit 0 with exactly `Removed targets .claude/skills from <lock>: complete (0 notices, 0 unavailable repositories)\n`; project lock has no additional targets, Claude alpha is removed, default alpha remains, and removed roots leave state. |
| Global removal | Exit 0 with exactly `Removed targets .cursor/skills from <global-lock>: complete (0 notices, 0 unavailable repositories)\n`; global cursor beta is removed, default global beta remains, and the global cursor root leaves ownership state.         |

### Notes

- Removing an additional target never removes the default `.agents/skills` target or foreign files that are not owned links.

- Output expectations refer to the helper's captured `cli.Result.Stdout`; these tests do not assert a separate stderr stream.
- These are assertions in the pinned source, not execution results from this documentation-only layer.
