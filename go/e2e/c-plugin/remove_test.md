# Remove selected skills safely

Source: [remove_test.go](./remove_test.go)

The relative Source link identifies the sibling Go implementation described below.

## `removeScenario`

### Scope

`removeScenario` verifies nonterminal missing-selection rejection and unknown-selection no-ops, plugin-qualified selection, disabled-plugin retention, foreign-path preservation, repeat idempotency, and global removal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin sync` | Reconcile desired links without rewriting the lock. |
| `c-plugin skill remove` | Remove selected skills while preserving foreign paths. |
| `c-plugin plugin remove` | Delete only the retained global whole-plugin registration. |

### Arguments and options

| Argument or option                               | Purpose                                                        |
| ------------------------------------------------ | -------------------------------------------------------------- |
| `--skill demo/unknown`               | Confirm an unknown selection is an atomic no-op.               |
| `--skill demo/./alpha`               | Confirm normalization of plugin-qualified selection.           |
| `--skill demo/beta`                  | Disable the final project skill while retaining the plugin record. |
| `--global --skill demo/gamma` | Select and mutate only the global lock and managed root.       |
| `--global --plugin demo` | Delete the global plugin after disabling its last skill. |

### Preconditions and fixtures

- Each case uses a separate `c-plugin-e2e:local` container. `HOME=/tmp/c-plugin-v2-remove-e2e/home` and `project=$HOME/project`.
- `c-plugin` in the commands below is the exact executable `/sandbox/.local/bin/c-plugin`; the helper passes argv directly, not through a scenario shell script.
- The project lock selects alpha and beta from a local plugin; an initial sync creates their managed links and ownership state.
- Alpha is replaced by a regular file and a foreign `neighbor` file is added before removal.
- A separate global plugin and lock select gamma under `HOME`.

### Execution flow

1. Write the project fixture lock and run `c-plugin sync` from `project`; replace alpha with a foreign file and add the neighbor, then record lock/state digests.
2. Run `c-plugin skill remove`, then `c-plugin skill remove --skill demo/unknown` from `project`; compare lock and state digests.
3. Run `c-plugin skill remove --skill demo/./alpha` from `project`; verify plugin-qualified selection and foreign-path preservation, then record new digests.
4. Run `c-plugin skill remove --skill demo/alpha` from `project` and confirm the no-op output and unchanged digests.
5. Run `c-plugin skill remove --skill demo/beta` from `project`; verify the retained plugin with an empty enabled set, removed beta link, and preserved foreign paths.
6. Create the separate global plugin/lock and `project/nested`; from that directory run `c-plugin sync --global`, then `c-plugin skill remove --global --skill demo/gamma`.
7. Verify the global retained disabled plugin, absent gamma link, and removal of gamma from global ownership state.
8. From `project/nested`, run `c-plugin plugin remove --global --plugin demo`; verify global empty desired state, whole-plugin completion, and unchanged project lock digest.

### Expected results

`<lock>` is `$HOME/project/c-plugin-lock.json` and `<global-lock>` is `$HOME/c-plugin-lock.json`. Exact output lines end in `\n`.

| Phase         | Expected result                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Missing selection | Nonzero exit with actionable `--skill` guidance without `--plugin`; lock and ownership bytes, foreign files, and beta link do not change. |
| Unknown selection | Exit 0 with `No skill changes for <lock>`; lock and state digests do not change. |
| Alpha         | Exit 0 with output containing `Removed skills demo/alpha from <lock>: partial`; the replacement file and neighbor remain, beta stays linked and owned, and alpha leaves state. |
| Repeat alpha  | Exit 0 no-op with unchanged lock and state digests.                                                                             |
| Beta          | Exit 0 with output containing `Removed skills demo/beta from <lock>: complete`; project plugin remains registered with skills `[]`, beta link is removed, and foreign paths remain.                                   |
| Global gamma  | Exit 0 with output containing `Removed skills demo/gamma from <global-lock>: complete`; the global plugin remains registered with skills `[]` and the global gamma link/state entry is removed.                               |

### Notes

- A replaced managed path is treated as foreign and is not deletion authority.

- Output expectations refer to the helper's captured `cli.Result.Stdout`; these tests do not assert a separate stderr stream.
- These are assertions in the sibling Go source, not evidence that this workflow has been executed successfully.
