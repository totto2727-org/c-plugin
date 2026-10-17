# Interactive selection in real terminals

Source: [interactive_test.go](./interactive_test.go)

## `interactiveSelectionScenario`

### Scope

Verify project add, skill removal, and target removal with arrow-key navigation and Space selection, without changes to global state.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize project and global locks. |
| `c-plugin plugin add` | Select discovered skills. |
| `c-plugin skill remove` | Remove one registered skill. |
| `c-plugin target add` | Register additional roots. |
| `c-plugin target remove` | Select one additional root. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize the independent global lock. |
| `local:./plugin` | Select the direct project plugin root. |
| `.claude/skills`, `.cursor/skills` | Register two additional roots using separate positional target-add arguments. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-selection/home`, with separate project and global demo plugins containing alpha, beta, and gamma.
- `c-plugin` is `/sandbox/.local/bin/c-plugin`.
- A Python standard-library fixture creates an actual PTY for stdin and stderr, captures stdout separately, and sets `TERM=xterm`.
- The fixture sets a 40-row, 120-column terminal and sends raw keys only after the stderr footer `Space: toggle`.
- Every invocation checks restoration of the original terminal settings, except kernel input-replay bookkeeping in PENDIN.
- For keyboard invocations, the xterm transcript must enter and leave the alternate screen and hide then restore the cursor.
- Lock assertions use Generic records with keyed plugins and standaloneSkills. Ownership assertions use the ownershipEntries map and tagged source tuples.

### Execution flow

1. Run `c-plugin init` and `c-plugin init --global` from the project, then record the global lock digest.
2. Run `c-plugin plugin add local:./plugin` from the project and press Space, Down, Down, Space, Enter to select alpha and gamma.
3. Check alpha and gamma selection, then run `c-plugin skill remove` and press Down, Space, Enter to select gamma after alpha, with no entire-plugin row.
4. Run `c-plugin target add .claude/skills`, then `c-plugin target add .cursor/skills`.
5. Run `c-plugin target remove` and press Down, Space, Enter to select the cursor row.
6. Inspect final project links, ownership, and lock, then compare independent global state.

### Expected results

- Every CLI invocation exits 0 and restores terminal settings. Add completion appears on stdout. Menu labels and the keyboard footer appear on stderr, never stdout.
- The terminal does not display the retired numbered-input prompt.
- Add persists only alpha and gamma. Removal leaves only alpha and removes gamma's owned link and state entry.
- Target removal leaves only `.claude/skills` registered, removes cursor alpha and cursor ownership, and preserves primary and Claude alpha links.
- The global lock digest is unchanged and global ownership remains absent.

### Notes

The embedded fixture explicitly waits for the child and emits exit/status/output JSON to the existing Go runner.
Each child has a ten-second deadline and an outer fifteen-second timeout.
The driver removes terminal escape sequences from the captured stderr transcript before label assertions.
It does not use sleeps or append line endings to key actions.

## `interactiveGlobalScenario`

### Scope

Verify interactive global operations from a nested project directory preserve all project lock, ownership, and links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate project and select global skills. |
| `c-plugin skill remove` | Remove a global subset. |
| `c-plugin target add` | Register a global additional root. |
| `c-plugin target remove` | Remove the global additional root. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin` | Resolve the direct plugin root relative to the selected scope root. |
| `--all` | Explicitly populate project skills without prompting. |
| `--global` | Select only global state. |
| `.cursor/skills` | Register the global cursor root. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-global/home` with separate project and global plugins, each containing alpha, beta, and gamma.
- The fixture initializes both locks and populates project links and ownership before recording their digests.
- The actual PTY uses stdin and stderr, separate stdout, `TERM=xterm`, footer-driven raw keys, and bounded child waits.

### Execution flow

1. Run `c-plugin init`, `c-plugin init --global`, and `c-plugin plugin add local:./plugin --all` from the project.
2. Record project lock and ownership digests and create `project/nested`.
3. From `project/nested`, run `c-plugin plugin add --global local:./plugin` and press Space, Down, Space, Down, Space, Enter to select all three skills.
4. From the project, run `c-plugin target add --global .cursor/skills`.
5. From `project/nested`, run `c-plugin target remove --global` and press Space, Enter to select the only additional target.
6. Run `c-plugin skill remove --global` from the same directory and press Space, Down, Down, Space, Enter to select alpha and gamma from skill-only rows.
7. Inspect global beta and all project state.

### Expected results

- All invocations exit 0 and no prompt appears on stdout.
- Global add initially selects all three skills. Global removal leaves only beta, with its link resolving to the global plugin.
- Global cursor alpha and primary alpha/gamma are absent after their removals.
- Project lock and ownership digests are identical to their snapshots, and every project skill link remains correct.

### Notes

The command family intentionally exercises one global scope-isolation contract through sequential state transitions.
Each registered scenario receives its own container.

## `interactiveCancelScenario`

### Scope

Verify q and Escape preserve exact persisted bytes and do not synchronize deliberately missing links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both independent locks. |
| `c-plugin plugin add` | Populate fixture skills and cancel a later selection. |
| `c-plugin target add` | Populate an additional root. |
| `c-plugin skill remove` | Cancel skill removal. |
| `c-plugin target remove` | Cancel target removal. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize independent global state. |
| `local:./plugin --all` | Explicitly install all fixture skills. |
| `local:./plugin` | Prompt for discovered add rows. |
| `.cursor/skills` | Create additional owned links. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-cancel/home`.
- Project demo contains alpha, beta, and gamma. All are registered and synchronized to primary and cursor roots.
- Primary and cursor alpha links are then removed externally, leaving trusted ownership unchanged.
- Exact lock and ownership bytes are captured before cancellation.
- Real stdin/stderr PTYs use separate stdout, `TERM=xterm`, and footer-driven raw keys.

### Execution flow

1. Initialize both scopes, run `c-plugin plugin add local:./plugin --all`, and run `c-plugin target add .cursor/skills` from the project.
2. Delete both alpha links and capture lock and ownership bytes.
3. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin target remove` in order, pressing q for each menu.
4. Repeat those three invocations, pressing Escape for each menu.
5. After every invocation, compare exact lock and ownership bytes, absent alpha links, and the retained beta link.

### Expected results

- Every cancellation exits 0 with `Cancelled; no changes.` on stdout and no prompt on stdout.
- Lock and ownership files are byte-identical after every cancellation.
- Both alpha links remain absent, proving no implicit synchronization; beta remains correctly linked.

### Notes

The already-registered add fixture verifies cancellation does not replace the current enabled set.
The helper groups the command family because each implements the same cancellation non-mutation contract.

## `interactiveEmptyScenario`

### Scope

Verify Enter with an empty selection leaves removals unchanged and disables all plugin skills, then verify arrow-key selections replace the enabled set.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both locks. |
| `c-plugin plugin add` | Keep or replace the plugin's enabled set. |
| `c-plugin target add` | Populate the cursor root. |
| `c-plugin skill remove` | Choose no skill rows. |
| `c-plugin target remove` | Choose no target rows. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize global isolation state. |
| `local:./plugin --all` | Explicitly register all fixture skills. |
| `local:./plugin` | Prompt for add rows. |
| `.cursor/skills` | Add the cursor root. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-empty/home` with alpha, beta, and gamma registered to primary and cursor roots.
- Both alpha links are deliberately deleted after synchronization while ownership is retained.
- Exact lock and ownership bytes are saved.
- An actual PTY provides stdin/stderr with `TERM=xterm`; stdout is captured separately.

### Execution flow

1. Initialize both locks. Run `c-plugin plugin add local:./plugin` and press Enter without Space. Verify a new empty plugin registration, empty ownership, and absent skill links. Then run `c-plugin plugin add local:./plugin --all` and `c-plugin target add .cursor/skills` from the project.
2. Delete primary and cursor alpha links and capture persisted bytes.
3. Run `c-plugin skill remove` and `c-plugin target remove`, pressing Enter without Space for each menu.
4. Repeat both removal commands, pressing Space twice and Enter to clear the focused row before confirmation. Compare exact persisted bytes and missing alpha links after each invocation.
5. Run `c-plugin plugin add local:./plugin` and press Enter without Space. Inspect enabled row markers, the retained empty plugin registration, empty ownership, and absent links.
6. Run `c-plugin plugin add local:./plugin` and press Down, Space, Enter. Verify beta-only registration and a disabled beta menu marker before selection.
7. Run `c-plugin plugin add local:./plugin` and press Space, Down, Down, Space, Enter. Inspect alpha/gamma disabled markers and the beta enabled marker before selection.
8. Verify alpha/gamma-only registration, their primary and cursor links, and beta's removal from both roots.

### Expected results

- All operations exit 0, with prompts confined to stderr.
- Enter with an empty removal selection reports `No selection; no changes.` and preserves exact bytes, the retained beta link, and both missing alpha links.
- Plugin add with an empty selection persists demo with skills `[]` and the cursor target retained, removes all owned links, and leaves empty ownership.
- Selecting beta enables only beta. Selecting alpha and gamma then replaces beta, creates both selected links in both roots, and removes beta links.

### Notes

Every menu starts with no selected rows, even when informational markers show enabled skills.
Enter confirms the current selection. It does not cancel the menu.
The sequential disable, enable, and replacement operations are one enabled-set workflow, not an additive merge.

## `interactiveInvalidScenario`

### Scope

Verify ignored numeric input, Space toggling, arrow navigation, and scrolling after terminal resize.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Select skills after ignored unsupported keys. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize separate global state. |
| `local:./plugin` | Select the direct project plugin root. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-invalid/home`, with demo alpha, beta, and gamma available and an empty project lock.
- A real stdin/stderr PTY uses `TERM=xterm`; stdout remains separate.
- Raw keys are released only after the keyboard footer appears.

### Execution flow

1. Run `c-plugin init` and `c-plugin init --global` from the project.
2. Run `c-plugin plugin add local:./plugin`.
3. Type `1,199xyz` without Enter, then press Space, Space, Down, Space, Up, Space, Enter.
4. Inspect the lock and skill links. The two initial Space presses leave alpha unselected before Down selects beta and Up returns to alpha.
5. Add valid source skills `scroll-00` through `scroll-49` to the same plugin. Run `c-plugin plugin add local:./plugin` again with all 53 skills available.
6. After the first footer, shrink the PTY from 40 by 120 to 2 by 80 and deliver process-group SIGWINCH. Wait for `Enlarge terminal`, then send Enter. During a bounded 0.2-second stdout wait, verify the process stays alive, prints no completion, and preserves exact lock and ownership bytes. Enlarge to 12 by 80, deliver SIGWINCH, and wait for the keyboard footer.
7. Press Down 52 times, Space, Enter to select the final sorted row. Inspect the rendered `scroll-49` label, final lock, selected link, and all 52 unselected link paths.

### Expected results

- Both CLI invocations exit 0, and the harness confirms every footer-triggered action was sent.
- The first invocation persists and links only alpha and beta, leaving gamma absent.
- Enter cannot confirm while the terminal cannot show a menu row. The process stays alive and persisted bytes remain unchanged until enlargement.
- The resized menu renders the final off-screen row. The second invocation persists and links only `scroll-49`, with all 52 other links absent.
- The selection prompt never appears on stdout, and both children restore the original terminal settings.

### Notes

The registered scenario name is retained, but invalid numbered-line retries are no longer a terminal UI contract.
The single-plugin policy retry remains covered by [pluginToggleScenario](./unified_api_test.md#plugintogglescenario).
The ignored letters exclude optional shortcuts such as a and n.

## `interactiveNoInputScenario`

### Scope

Verify global `--no-input` prevents prompting on an actual terminal and rejects omitted selectors without state changes.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both locks. |
| `c-plugin plugin add` | Populate fixtures and reject missing selection. |
| `c-plugin target add` | Populate additional roots. |
| `c-plugin skill remove` | Reject missing removal selection. |
| `c-plugin target remove` | Reject missing target selection. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize global isolation state. |
| `local:./plugin --all` | Populate project fixture skills. |
| `.cursor/skills` | Populate cursor links. |
| `--no-input` | Disable interactive selection before subcommands. |
| `local:./plugin` | Supply a direct plugin root but omit enable-set selectors. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-no-input/home` with alpha, beta, and gamma registered and a cursor target.
- Primary alpha is deliberately removed after synchronization; exact lock and ownership bytes are saved.
- Real stdin/stderr PTYs set `TERM=xterm` and receive no input.

### Execution flow

1. Initialize both locks, add all project skills explicitly, and register cursor with `c-plugin target add .cursor/skills`.
2. Delete primary alpha and save lock and ownership bytes.
3. Run `c-plugin --no-input plugin add local:./plugin` on a PTY.
4. Run `c-plugin --no-input skill remove` and `c-plugin --no-input target remove` on separate PTYs.
5. Inspect each result and persisted state immediately.

### Expected results

- Each omitted-selection command exits nonzero without printing the selection prompt on either stream.
- Stdout diagnostics contain `--all`, `--none`, and `--skill` for plugin add, `--skill` for skill removal, and `--target` for target removal.
- Lock and ownership bytes remain identical, and primary alpha remains absent.

### Notes

Each child is explicitly waited for and bounded, so accidental prompting cannot hang the suite.
`--no-input` is an Iris global option, not a command-specific flag.

## `interactivePipeScenario`

### Scope

Verify piped stdin disables interactive selection even when stderr is a terminal, without consuming input or mutating state.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate skills and reject omitted selection. |
| `c-plugin target add` | Populate cursor roots. |
| `c-plugin skill remove` | Reject omitted removal selection. |
| `c-plugin target remove` | Reject omitted target selection. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize global isolation state. |
| `local:./plugin --all` | Explicitly add fixture skills. |
| `.cursor/skills` | Register a cursor root. |
| `local:./plugin` | Specify the direct plugin root without an enable-set selector. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-pipe/home` with synchronized alpha, beta, gamma, and a cursor target.
- Primary alpha is deleted externally; exact persisted bytes are saved.
- Each child receives a pipe containing `unconsumed-input\n`, terminal stderr, separate stdout, and `TERM=xterm`.
- The parent retains the pipe read end and checks its remaining bytes after the child exits.

### Execution flow

1. Initialize both locks, run `c-plugin plugin add local:./plugin --all`, and run `c-plugin target add .cursor/skills`.
2. Delete primary alpha and save persisted bytes.
3. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin target remove` with a fresh input pipe each time.
4. Check each exit, captured streams, unread pipe bytes, exact persisted bytes, and absent alpha.

### Expected results

- Every missing-selection invocation exits nonzero without a selection prompt on stdout or stderr.
- Stdout diagnostics contain `--all`, `--none`, and `--skill` for plugin add, `--skill` for skill removal, and `--target` for target removal.
- The pipe retains exactly `unconsumed-input\n` after each child exits.
- Lock and ownership bytes do not change, and missing alpha is not recreated.

### Notes

This deliberately distinguishes the required stdin-and-stderr terminal check from a stderr-only check.
The standard-library fixture remains inside the existing Go/Testcontainers execution path.

## `interactiveInterruptScenario`

### Scope

Verify Ctrl+C and external SIGINT propagate without cancellation, restore terminal settings, and cannot rewrite state or trigger synchronization.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate project fixture skills. |
| `c-plugin skill remove` | Interrupt keyboard selection before confirmation. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize separate global state. |
| `local:./plugin --all` | Explicitly populate fixture skills. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-interrupt/home` with all three skills registered.
- Primary alpha is deliberately deleted, and lock and ownership bytes are saved.
- A real stdin/stderr PTY uses `TERM=xterm`, with stdout captured independently.
- The child starts in its own process session so the fixture can deliver `SIGINT` to its process group.

### Execution flow

1. Initialize both locks and run `c-plugin plugin add local:./plugin --all` from the project.
2. Delete primary alpha and save lock and ownership bytes.
3. Run `c-plugin skill remove` and send the Ctrl+C key byte `0x03` after the keyboard footer appears.
4. Wait for the child, compare terminal settings, and inspect persisted bytes and links.
5. Repeat the command with process-group SIGINT after the footer appears, then repeat all checks.
6. Run `c-plugin skill remove` on a fresh PTY with `TERM=c-plugin-no-such-terminal` and no key actions. Verify initialization failure, no keyboard footer, restored terminal settings, unchanged persisted bytes, and unchanged links.

### Expected results

- Both interrupted CLI invocations exit nonzero without `Cancelled; no changes.` and restore the original terminal settings, alternate screen, and cursor visibility.
- Invalid TERM exits nonzero before a keyboard footer and restores terminal settings even when Vty initialization fails.
- The keyboard footer does not appear on stdout.
- Lock and ownership files remain byte-identical.
- Alpha stays absent and beta remains linked to its source skill directory.

### Notes

The scenario covers both raw-mode Ctrl+C and the external process signal.
No sleep is used to race either interruption against startup.

## `interactiveEOFScenario`

### Scope

Verify Ctrl+D cancels each keyboard selection successfully without writes or implicit synchronization.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate skills and cancel add selection with EOF. |
| `c-plugin target add` | Populate cursor links. |
| `c-plugin skill remove` | Cancel skill selection with EOF. |
| `c-plugin target remove` | Cancel target selection with EOF. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize independent global state. |
| `local:./plugin --all` | Explicitly install fixture skills. |
| `local:./plugin` | Prompt for add selection. |
| `.cursor/skills` | Register an additional root. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-eof/home` with all skills registered in primary and cursor roots.
- Both alpha links are deliberately removed while ownership is retained; exact persisted bytes are captured.
- A real PTY uses `TERM=xterm` and separate stdout. The driver preserves its original echo and canonical settings as the restoration baseline.

### Execution flow

1. Initialize both locks, run `c-plugin plugin add local:./plugin --all`, then `c-plugin target add .cursor/skills` from the project.
2. Remove primary and cursor alpha links and capture persisted bytes.
3. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin target remove` on separate PTYs.
4. At each observed keyboard footer, write Ctrl+D byte `0x04` without a line ending.
5. After each child exits, compare persisted bytes, both missing alpha links, and the retained beta link.

### Expected results

- All three EOF cancellations exit 0 with `Cancelled; no changes.` on stdout, with no prompt on stdout.
- Lock and ownership bytes remain exact.
- Alpha links remain missing and beta stays correctly linked.

### Notes

Ctrl+D cancels in the raw-mode UI without closing the PTY master before stderr is drained.
The fixture explicitly waits for the child and propagates its exit status through JSON.
