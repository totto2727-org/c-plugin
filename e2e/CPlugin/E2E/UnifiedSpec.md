# Unified command hierarchy and plugin policy

Source: [UnifiedSpec.hs](./UnifiedSpec.hs).
Every registered Hspec example uses a separate `withEnvironment "c-plugin-e2e:local"` container and the public Caseyard API.
The executable is `/sandbox/.local/bin/c-plugin`.
Examples are parallel, with the caller setting Hspec's job limit to two.
Terminal operations use [Pty.hs](./Pty.hs) and Caseyard's public `withTerminal`, `expectTerminal`, `sendTerminal`, and `waitTerminal` APIs.
The shared scenario installs the caller-supplied static Caseyard driver from `C_PLUGIN_E2E_DRIVER` once per environment.
Each terminal call checks that every key sequence is sent after a new alternate-screen entry and selection footer, normalized termios is restored at child exit, and the final screen/cursor transitions restore display modes.
Raw stdout and terminal output remain separate, with no numbered-input prompt.
Assertions use a ten-second Caseyard child watchdog, five-second prompt expectations, bounded final waits, exact persisted-byte comparisons, and SHA-256 checks.
Pipe-input assertions compare `terminalUnreadInput` bytes directly.
Textual terminal assertions decode UTF-8 with replacement without stripping ANSI bytes.
Termios normalization is Caseyard's contract, including kernel bookkeeping and equivalent standard baud-rate encodings, not the former Python representation.
Display restoration checks ANSI transitions, not a rendered-screen snapshot.

## `unified_help_hierarchy`

### Scope

Verify help nodes, selector placement, and non-mutating rejection of retired aliases.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin` | Top-level help. |
| `c-plugin plugin` | Plugin help. |
| `c-plugin skill` | Skill help without retired children. |
| `c-plugin target` | Target help. |
| `c-plugin plugin add` | Prepare an owned link. |
| `c-plugin sync` | Help and selector rejection. |
| `c-plugin update` | Help and selector rejection. |
| `c-plugin list` | Help and selector rejection. |
| `c-plugin plugin list` | Help and selector rejection. |
| `c-plugin skill list` | Help and selector rejection. |
| `c-plugin plugin remove` | Plugin-only removal selector. |
| `c-plugin skill remove` | Skill-only removal selector. |
| `c-plugin plugin skill enable` | Enable help. |
| `c-plugin plugin skill disable` | Disable help. |
| `c-plugin target add` | Target-add help. |
| `c-plugin target remove` | Help and unrelated-selector rejection. |
| `c-plugin skill sync` | Retired alias rejection. |
| `c-plugin skill update` | Retired alias rejection. |
| `c-plugin skill target add` | Retired alias rejection. |
| `c-plugin skill target remove` | Retired alias rejection. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Prepare demo/alpha. |
| `--help` | Inspect without mutation. |
| `--plugin demo` | Whole-plugin removal selector and misplaced-selector tests. |
| `--skill alpha`, `--skill demo/alpha` | Misplaced-selector tests. |
| `.cursor/skills`, `--target .cursor/skills` | Retired target-alias rejection. |

### Preconditions and fixtures

Synthetic HOME is `/tmp/c-plugin-standard-unified-help/home`, with project lock and a demo plugin containing alpha.
The fixture installs alpha and captures lock/state digests.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --all`.
2. Run `c-plugin --help`, then append `--help` to these ordered paths: `plugin`, `skill`, `target`, `sync`, `update`, `list`, `plugin list`, `plugin remove`, `skill list`, `skill remove`, `plugin skill enable`, `plugin skill disable`, `target add`, `target remove`.
3. Inspect `c-plugin plugin remove --help`, `c-plugin skill --help`, and `c-plugin skill remove --help`.
4. Reject, in order, `c-plugin skill sync`, `c-plugin skill update`, `c-plugin skill target add .cursor/skills`, `c-plugin skill target remove --target .cursor/skills`, `c-plugin skill remove --plugin demo`, and `c-plugin plugin remove --skill demo/alpha`.
5. Reject, in order, `c-plugin target remove --plugin demo`, `c-plugin target remove --skill alpha`, `c-plugin list --skill alpha`, `c-plugin plugin list --plugin demo`, `c-plugin skill list --skill alpha`, `c-plugin sync --skill alpha`, and `c-plugin update --plugin demo`.

### Expected results

All 15 supported help invocations succeed with `Available options:` and unchanged lock/state digests.
Plugin removal advertises only the plugin selector, and skill removal advertises only the skill selector.
Skill help contains no sync, update, or target child.
Each of the 13 invalid commands fails, preserves both digests and alpha's correct link, and leaves `.cursor` absent.

### Notes

Retired command paths in the table are deliberate rejection cases, not supported usage.

## `plugin_toggle`

### Scope

Verify incremental enable/disable, disabled registration retention, atomic failures, scope isolation, and real-terminal nested selection.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize global state. |
| `c-plugin plugin add` | Register disabled and collision-fixture plugins. |
| `c-plugin plugin skill enable` | Union selected skills. |
| `c-plugin plugin skill disable` | Subtract selected skills. |
| `c-plugin skill add` | Prepare standalone collision. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--none` | Register disabled demo. |
| `demo` | Explicit installed-plugin identity. |
| `--skill alpha`, `--skill beta`, `--skill gamma` | Incremental selectors. |
| `--all` | Select every valid skill. |
| `-g`, `--global` | Select HOME state. |
| `--no-input` | Forbid terminal prompts. |
| `missing`, `unknown`, `--none`, conflicting selectors | Atomic rejection cases. |
| `local:./standalone/alpha`, `local:./other` | Collision fixtures. |

### Preconditions and fixtures

Synthetic HOME is `/tmp/c-plugin-standard-plugin-toggle/home`.
The project demo source has alpha/beta/gamma, and the global source later has gamma only.
PTY menus start on the first sorted row without selected rows, regardless of enabled markers.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --none`, `c-plugin plugin skill enable demo --skill beta`, `c-plugin plugin skill enable demo --skill alpha`, and `c-plugin plugin skill disable demo --skill beta`.
2. Remove alpha's link and save digests. Run `c-plugin plugin skill enable demo --skill alpha`, then `c-plugin plugin skill disable demo --skill beta`.
3. For enable then disable, run `c-plugin plugin skill COMMAND demo` with q, then Enter, then Space, Space, Enter on separate PTYs.
4. For each command, run `c-plugin --no-input plugin skill COMMAND demo` on a PTY, then `c-plugin plugin skill COMMAND demo` with pipe stdin.
5. Run `c-plugin plugin skill disable demo --all`. Run `c-plugin plugin skill enable demo` with Down, Space, Enter, then `c-plugin plugin skill disable demo` with Space, Down, Space, Down, Space, Enter.
6. Create the global gamma source, run `c-plugin init --global`, and run `c-plugin plugin add local:./plugin --none --global`.
7. From `project/nested`, run `c-plugin plugin skill enable demo --all -g`, then `c-plugin plugin skill disable demo --skill gamma -g`.
8. Reject, in order, `c-plugin plugin skill enable missing --all`, `c-plugin plugin skill disable missing --all`, `c-plugin plugin skill enable demo --skill unknown`, `c-plugin plugin skill disable demo --skill unknown`, `c-plugin plugin skill enable --all`, `c-plugin plugin skill disable --all`, `c-plugin plugin skill enable demo --none`, `c-plugin plugin skill disable demo --none`, and `c-plugin plugin skill enable demo --all --skill alpha`.
9. Write standalone alpha, run `c-plugin skill add local:./standalone/alpha`, and reject `c-plugin plugin skill enable demo --skill alpha`.
10. Write other/beta, run `c-plugin plugin add local:./other --all`, and reject `c-plugin plugin skill enable demo --skill beta`.
11. Run `c-plugin plugin skill enable` with Space, Down, Space, Enter to select both plugins, then Space, Enter after retry, then Down, Down, Space, Enter in the skill menu.
12. Run `c-plugin plugin skill disable` with Space, Enter, then Down, Down, Space, Enter.
13. For enable then disable, run `c-plugin --no-input plugin skill COMMAND --all` on a PTY, then `c-plugin plugin skill COMMAND --all` with pipe stdin.
14. For enable then disable, run `c-plugin plugin skill COMMAND` with Space, Enter followed by q, Escape, or Ctrl+D in separate nested-menu invocations.
15. Remove the demo source. For enable then disable, run the same argv with q, Escape, Ctrl+D, then Enter at the plugin stage.
16. After those cancellations, reject `c-plugin plugin skill COMMAND demo --all` for the missing source.

### Expected results

Enabling beta then alpha produces beta-only then alpha/beta locks and correct links, with gamma absent.
Disabling beta leaves alpha only and no beta link.
Semantic no-ops preserve lock/state digests and do not repair the missing alpha link.
Cancellation prints `Cancelled; no changes.`, while empty skill selection prints `No skill changes for `, without repairing alpha or changing digests.
Explicit nonterminal rejection prints `--skill` and `--all`, never prompts, preserves digests, and leaves pipe input exactly `unconsumed-input\n`.
Disabling all retains demo with an empty enabled set, and terminal selection enables only beta before disabling all again.
Global enable creates gamma's correct HOME link, global disable removes it, and both preserve project digests.
All invalid selector/identity operations fail without mutation.
Standalone and other-plugin collisions preserve their links and captured lock/state digests.
Selecting two plugins reports `Invalid selection: choose exactly one registered plugin.`, displays demo/other and gamma disabled without an entire-plugin row, then enables gamma while preserving standalone alpha.
The nested disable displays gamma enabled, removes its link, and restores the previous lock digest.
Missing-plugin nonterminal errors contain `PLUGIN`, do not prompt or consume pipe input, and preserve digests.
Nested cancellation displays gamma disabled and preserves both collision links and digests.
Plugin-stage cancellation succeeds even with the demo source absent, displays demo/other without skill-status labels, and preserves digests and source absence.
Explicit operations against the missing source fail without mutation.

### Notes

Every PTY call also requires alternate-screen, cursor, and termios restoration.
No source refresh or substitute terminal simulation is introduced.

## `separated_removal`

### Scope

Verify disjoint plugin/skill removal selectors and never adopt or delete unowned exact-target links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Install demo/alpha. |
| `c-plugin skill add` | Install standalone solo. |
| `c-plugin sync` | Reconcile without adopting unowned links. |
| `c-plugin plugin remove` | Remove whole registrations. |
| `c-plugin skill remove` | Disable plugin skills or remove standalone registrations. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Install alpha. |
| `local:./standalone/solo` | Install standalone solo. |
| `--plugin demo` | Whole-plugin explicit selector. |
| `--skill solo` | Standalone explicit selector. |

### Preconditions and fixtures

Synthetic HOME is `/tmp/c-plugin-standard-separated-removal/home`.
The fixture installs alpha and solo, removes the ownership record, and then synchronizes.
Both existing exact-target symlinks must remain unowned.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --all`, then `c-plugin skill add local:./standalone/solo`.
2. Delete ownership, run `c-plugin sync`, verify both links and empty ownership, and save digests.
3. Run `c-plugin plugin remove` with q, Escape, and Ctrl+D in separate invocations.
4. Run the same argv with Enter, then Space, Space, Enter.
5. Run `c-plugin skill remove` with Space, Enter to disable demo/alpha only.
6. Run `c-plugin plugin remove` with Space, Enter to remove demo's registration.
7. Save the lock digest, run `c-plugin plugin remove --plugin demo`, then run `c-plugin skill remove --skill solo`.

### Expected results

Plugin menus contain only `demo (entire plugin)`, not demo/alpha or solo.
Cancellation and empty selection preserve digests, and empty selections preserve both links.
Skill menus contain demo/alpha and `solo (standalone skill)`, not an entire-plugin row.
Skill removal retains demo disabled and solo registered, with both unowned links intact.
Plugin removal reports `Removed plugins demo`, leaves the exact solo-only lock and empty ownership, and preserves both unowned links.
Repeated explicit removal of missing demo preserves the lock digest.
Removing solo produces the empty lock while preserving its unowned symlink.

### Notes

Lock assertions compare complete JSON structures, including null local origins.
