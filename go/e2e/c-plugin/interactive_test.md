# Interactive selection in real terminals

Source: [interactive_test.go](./interactive_test.go)

## `interactiveSelectionScenario`

### Scope

Verify project add, skill removal, and target removal as an ordered numbered-selection workflow, without changing global state.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize project and global locks. |
| `c-plugin plugin add` | Select discovered skills. |
| `c-plugin skill remove` | Remove one registered skill. |
| `c-plugin skill target add` | Register additional roots. |
| `c-plugin skill target remove` | Select one additional root. |

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
- The fixture feeds input only after the flushed stderr prompt `Select indexes (comma/space separated), all, none, or q to cancel: `.

### Execution flow

1. Run `c-plugin init` and `c-plugin init --global` from the project, then record the global lock digest.
2. Run `c-plugin plugin add local:./plugin` from the project and enter `1, 3` at the prompt.
3. Check alpha and gamma selection, then run `c-plugin skill remove` and enter `3`, the gamma row after the entire-plugin and alpha rows.
4. Run `c-plugin skill target add .claude/skills`, then `c-plugin skill target add .cursor/skills`.
5. Run `c-plugin skill target remove` and enter `2`, the cursor row.
6. Inspect final project links, ownership, and lock, then compare independent global state.

### Expected results

- Every CLI invocation exits 0. Add completion appears on stdout, while numbered menu labels and the prompt appear on stderr, never stdout.
- Add persists only alpha and gamma. Removal leaves only alpha and removes gamma's owned link and state entry.
- Target removal leaves only `.claude/skills` registered, removes cursor alpha and cursor ownership, and preserves primary and Claude alpha links.
- The global lock digest is unchanged and global ownership remains absent.

### Notes

The embedded fixture explicitly waits for the child and emits exit/status/output JSON to the existing Go runner.
Each child has a ten-second deadline and an outer fifteen-second timeout.
No arrow-key interface or sleeps are used.

## `interactiveGlobalScenario`

### Scope

Verify interactive global operations from a nested project directory preserve all project lock, ownership, and links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate project and select global skills. |
| `c-plugin skill remove` | Remove a global subset. |
| `c-plugin skill target add` | Register a global additional root. |
| `c-plugin skill target remove` | Remove the global additional root. |

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
- The actual PTY uses stdin and stderr, separate stdout, `TERM=xterm`, prompt-driven input, and bounded child waits.

### Execution flow

1. Run `c-plugin init`, `c-plugin init --global`, and `c-plugin plugin add local:./plugin --all` from the project.
2. Record project lock and ownership digests and create `project/nested`.
3. From `project/nested`, run `c-plugin plugin add --global local:./plugin` and enter `all`.
4. From the project, run `c-plugin skill target add --global .cursor/skills`.
5. From `project/nested`, run `c-plugin skill target remove --global` and enter `all`.
6. Run `c-plugin skill remove --global` from the same directory and enter `2 4`, selecting alpha and gamma after the entire-plugin row.
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

Verify both cancellation words preserve exact persisted bytes and do not synchronize deliberately missing links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both independent locks. |
| `c-plugin plugin add` | Populate fixture skills and cancel a later selection. |
| `c-plugin skill target add` | Populate an additional root. |
| `c-plugin skill remove` | Cancel skill removal. |
| `c-plugin skill target remove` | Cancel target removal. |

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
- Real stdin/stderr PTYs use separate stdout, `TERM=xterm`, and prompt-driven input.

### Execution flow

1. Initialize both scopes, run `c-plugin plugin add local:./plugin --all`, and run `c-plugin skill target add .cursor/skills` from the project.
2. Delete both alpha links and capture lock and ownership bytes.
3. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin skill target remove` in order, entering `q` for each prompt.
4. Repeat those three invocations, entering `cancel` for each prompt.
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

Verify blank input keeps the current state, removal `none` is a no-op, and plugin `none` disables all skills before subsequent numeric selections replace the enabled set.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both locks. |
| `c-plugin plugin add` | Keep or replace the plugin's enabled set. |
| `c-plugin skill target add` | Populate the cursor root. |
| `c-plugin skill remove` | Choose no skill rows. |
| `c-plugin skill target remove` | Choose no target rows. |

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

1. Initialize both locks, run `c-plugin plugin add local:./plugin --all`, then `c-plugin skill target add .cursor/skills` from the project.
2. Delete primary and cursor alpha links and capture persisted bytes.
3. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin skill target remove`, sending a blank line at each prompt.
4. Run `c-plugin skill remove` and `c-plugin skill target remove` with `none`; compare exact persisted bytes and missing alpha links after each.
5. Run `c-plugin plugin add local:./plugin` with `none`; inspect enabled row markers, the retained empty plugin registration, empty ownership, and absent links.
6. Run `c-plugin plugin add local:./plugin` with `2` and verify beta-only registration with a disabled beta menu marker before selection.
7. Run `c-plugin plugin add local:./plugin` with `1 3`; inspect alpha/gamma disabled markers and beta enabled marker before selection.
8. Verify alpha/gamma-only registration, their primary and cursor links, and beta's removal from both roots.

### Expected results

- All operations exit 0, with prompts confined to stderr.
- Blank input reports `Cancelled; no changes.` and preserves exact lock and ownership bytes, the retained beta link, and both missing alpha links.
- Removal `none` reports `No selection; no changes.` and also preserves exact bytes and missing links.
- Plugin `none` persists demo with skills `[]` and the cursor target retained, removes all owned links, and leaves empty ownership.
- Selecting `2` enables only beta. Selecting `1 3` then replaces beta with alpha and gamma, creates both selected links in both roots, and removes beta links.

### Notes

Blank cancels, but plugin `none` explicitly chooses an empty enabled set.
The sequential disable, enable, and replacement operations are one enabled-set workflow, not an additive merge.

## `interactiveInvalidScenario`

### Scope

Verify duplicate, out-of-range, and nonnumeric inputs reprompt until a valid selection succeeds.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Recover from invalid selection lines. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize separate global state. |
| `local:./plugin` | Select the direct project plugin root. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-interactive-invalid/home`, with demo alpha, beta, and gamma available and an empty project lock.
- A real stdin/stderr PTY uses `TERM=xterm`; stdout remains separate.
- Input is released one line per observed prompt, including each repeated prompt.

### Execution flow

1. Run `c-plugin init` and `c-plugin init --global` from the project.
2. Run `c-plugin plugin add local:./plugin`.
3. Enter `1,1`, then `99`, then `garbage`, and finally `1 2`, waiting for the next prompt before every input.
4. Inspect the final lock and skill links.

### Expected results

- The final CLI exit is 0, and the harness confirms all four prompt-triggered inputs were sent.
- Only alpha and beta are persisted and linked; gamma remains absent.
- The selection prompt never appears on stdout.

### Notes

A failure to reprompt or an early acceptance of invalid input fails the bounded harness or its input-count assertion.
No ranges, wildcards, or arrow-key grammar is assumed.

## `interactiveNoInputScenario`

### Scope

Verify global `--no-input` prevents prompting on an actual terminal and rejects omitted selectors without state changes.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both locks. |
| `c-plugin plugin add` | Populate fixtures and reject missing selection. |
| `c-plugin skill target add` | Populate additional roots. |
| `c-plugin skill remove` | Reject missing removal selection. |
| `c-plugin skill target remove` | Reject missing target selection. |

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

1. Initialize both locks, add all project skills explicitly, and register cursor with `c-plugin skill target add .cursor/skills`.
2. Delete primary alpha and save lock and ownership bytes.
3. Run `c-plugin --no-input plugin add local:./plugin` on a PTY.
4. Run `c-plugin --no-input skill remove` and `c-plugin --no-input skill target remove` on separate PTYs.
5. Inspect each result and persisted state immediately.

### Expected results

- Each omitted-selection command exits nonzero without printing the selection prompt on either stream.
- Stdout diagnostics contain `--all`, `--none`, and `--skill` for plugin add, `--plugin` and `--skill` for removal, and `--target` for target removal.
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
| `c-plugin skill target add` | Populate cursor roots. |
| `c-plugin skill remove` | Reject omitted removal selection. |
| `c-plugin skill target remove` | Reject omitted target selection. |

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

1. Initialize both locks, run `c-plugin plugin add local:./plugin --all`, and run `c-plugin skill target add .cursor/skills`.
2. Delete primary alpha and save persisted bytes.
3. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin skill target remove` with a fresh input pipe each time.
4. Check each exit, captured streams, unread pipe bytes, exact persisted bytes, and absent alpha.

### Expected results

- Every missing-selection invocation exits nonzero without a selection prompt on stdout or stderr.
- Stdout diagnostics contain `--all`, `--none`, and `--skill` for plugin add, `--plugin` and `--skill` for removal, and `--target` for target removal.
- The pipe retains exactly `unconsumed-input\n` after each child exits.
- Lock and ownership bytes do not change, and missing alpha is not recreated.

### Notes

This deliberately distinguishes the required stdin-and-stderr terminal check from a stderr-only check.
The standard-library fixture remains inside the existing Go/Testcontainers execution path.

## `interactiveInterruptScenario`

### Scope

Verify Ctrl-C semantics before selection cannot rewrite state or trigger synchronization.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate project fixture skills. |
| `c-plugin skill remove` | Interrupt selection before supplying indexes. |

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
3. Run `c-plugin skill remove` and send `SIGINT` only after its selection prompt is observed, before any selection line.
4. Explicitly wait for the child and inspect persisted bytes and links.

### Expected results

- The interrupted CLI exits nonzero, and its prompt does not appear on stdout.
- Lock and ownership files remain byte-identical.
- Alpha stays absent and beta remains linked to its source skill directory.

### Notes

The signal is the Ctrl-C process signal, not an assumed raw-mode key sequence.
No sleep is used to race the signal against startup.

## `interactiveEOFScenario`

### Scope

Verify canonical-terminal EOF cancels each selection successfully without writes or implicit synchronization.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate skills and cancel add selection with EOF. |
| `c-plugin skill target add` | Populate cursor links. |
| `c-plugin skill remove` | Cancel skill selection with EOF. |
| `c-plugin skill target remove` | Cancel target selection with EOF. |

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
- A real canonical-mode PTY uses `TERM=xterm`, separate stdout, and disabled input echo.

### Execution flow

1. Initialize both locks, run `c-plugin plugin add local:./plugin --all`, then `c-plugin skill target add .cursor/skills` from the project.
2. Remove primary and cursor alpha links and capture persisted bytes.
3. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin skill target remove` on separate PTYs.
4. At each observed prompt, write canonical EOF byte `0x04` without a preceding line.
5. After each child exits, compare persisted bytes, both missing alpha links, and the retained beta link.

### Expected results

- All three EOF cancellations exit 0 with `Cancelled; no changes.` on stdout, with no prompt on stdout.
- Lock and ownership bytes remain exact.
- Alpha links remain missing and beta stays correctly linked.

### Notes

Writing terminal EOF after the prompt is deterministic and does not close the PTY master before stderr is drained.
The fixture explicitly waits for the child and propagates its exit status through JSON.
