# Add local plugin skills and handle collisions

Source: [add_test.go](./add_test.go)

## `addScenario`

### Scope

Verify standard local plugin registration, duplicate rejection, removal, and forced replacement of an eligible file collision while preserving a real-directory collision and its neighbor.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Create the project lock. |
| `c-plugin skill add` | Register selected local plugin skills and reconcile links. |
| `c-plugin skill remove` | Remove selected skills with ownership-safe cleanup. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Resolve the plugin relative to the discovered project lock. |
| `--skill alpha`, `--skill beta` | Select bare discovered skill names for add. |
| `--skill demo/alpha`, `--skill demo/beta` | Select plugin-qualified identities for remove. |
| `--force` | Replace only the exact eligible file collision. |

### Preconditions and fixtures

- The registered case has its own disposable `c-plugin-e2e:local` container with `HOME=/tmp/c-plugin-v2-add-e2e/home` and `project=$HOME/project`.
- `c-plugin` is `/sandbox/.local/bin/c-plugin`, invoked directly with ordered argv by the helper.
- `project/plugin/plugin.json` contains only the canonical `$schema` value `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json` and `name: demo`.
- Alpha and beta have valid YAML frontmatter, matching directory names and descriptions.
- A foreign regular file occupies `.agents/skills/alpha`. Before force, beta is replaced by a real directory containing `keep`, beside a foreign `neighbor` file.

### Execution flow

1. From `project`, run `c-plugin init`, then create foreign alpha and `project/nested`.
2. From `project/nested`, run `c-plugin skill add --local ./plugin --skill alpha --skill beta` and inspect the lock, beta link, foreign alpha, and ownership state.
3. Repeat `c-plugin skill add --local ./plugin --skill alpha --skill beta` from the same directory and verify rejection, unchanged lock/state digests, and unchanged links and foreign content.
4. Run `c-plugin skill remove --skill demo/alpha --skill demo/beta` from `project/nested`. Alpha remains foreign and beta is removed.
5. Create beta's real directory and `keep` plus the foreign neighbor. Run `c-plugin skill add --local ./plugin --skill alpha --skill beta --force` from `project/nested`.
6. Verify alpha replacement, beta directory contents, neighbor contents, and final ownership entries.

### Expected results

| Observation | Expected result |
| --- | --- |
| Initial add | Exit 0, stdout contains `Added <project>/plugin to <lock>: partial`. |
| Lock | Version `3`, targets `[]`, one plugin `{source:"./plugin",name:"demo",skills:["alpha","beta"]}`. |
| Duplicate add | Nonzero exit containing `totto2727/c-plugin.AddLocalError.InvalidInput`, unchanged lock and ownership-state digests, foreign alpha and managed beta preserved. |
| Force | Exit 0 with the same partial action prefix. Alpha links to `<project>/plugin/skills/alpha`; beta remains a real directory containing `directory-content\n`; neighbor remains `neighbor\n`. |
| Ownership | Initial state contains beta but not alpha. Final state contains alpha but not beta. |

### Notes

- Notice counts are incidental. Partial status and all persisted state/filesystem safety assertions remain required.
- Force runs after removing the selected plugin, not as a duplicate-source synchronization or merge.
- Synthetic `/tmp/c-plugin-v2-*` paths are retained for compatibility, not a lock-version claim.
- These are expected assertions, not an execution report. Captured output is `cli.Result.Stdout`.
