# Interactive selection in real terminals

Source: [InteractiveSpec.hs](./InteractiveSpec.hs).
Terminal helpers: [Pty.hs](./Pty.hs), using the public Caseyard scoped-terminal API.
Each named Hspec example creates its own `withEnvironment "c-plugin-e2e:local"` container.
Hspec schedules the parallel examples with the caller's two-job limit.
The executable is `/sandbox/.local/bin/c-plugin`.
Every terminal call has a ten-second Caseyard child watchdog, five-second prompt expectations, and a bounded ten-second final wait.
Caseyard uses a real Linux stdin/stderr PTY, independently captured stdout, `TERM=xterm`, and a 40-row, 120-column terminal.
The shared scenario installs the caller-supplied static Caseyard driver from `C_PLUGIN_E2E_DRIVER` once per environment.
Key sequences wait for a new alternate-screen entry and `Space: toggle`, so a nested menu cannot match a previous menu's incremental redraw.
The tiny-terminal flow waits for `Enlarge terminal` before testing Enter and persistence.
Every call verifies normalized termios equality at child exit, alternate-screen exit, cursor restoration, no prompt on stdout, and no retired numbered-input UI.
The result retains cumulative raw stdout and terminal bytes, typed exit or signal status, and unread pipe bytes.
Text assertions decode UTF-8 with replacement but do not strip ANSI sequences.
Display assertions require each entered or hidden mode's final transition to restore it, not a rendered-screen snapshot.
Caseyard normalizes kernel bookkeeping and equivalent standard baud-rate encodings, rather than reproducing the former Python driver's exact termios representation.

## `interactive_selection`

### Scope

Verify project add, skill removal, and target removal without global mutation.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize isolated scopes. |
| `c-plugin plugin add` | Select plugin skills. |
| `c-plugin skill remove` | Remove a selected skill. |
| `c-plugin target add` | Add target roots. |
| `c-plugin target remove` | Remove a selected root. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--global` | Initialize HOME state. |
| `local:./plugin` | Select the explicit local root. |
| `.claude/skills`, `.cursor/skills` | Additional targets. |

### Preconditions and fixtures

Synthetic HOME is `/tmp/c-plugin-standard-interactive-selection/home`.
Project and global demo plugins contain alpha, beta, and gamma.

### Execution flow

1. Run `c-plugin init`, then `c-plugin init --global`, and save the global lock digest.
2. Run `c-plugin plugin add local:./plugin` with Space, Down, Down, Space, Enter.
3. Run `c-plugin skill remove` with Down, Space, Enter.
4. Run `c-plugin target add .claude/skills`, then `c-plugin target add .cursor/skills`.
5. Run `c-plugin target remove` with Down, Space, Enter.

### Expected results

Add displays all three disabled labels, reports `Added `, and installs only alpha/gamma.
Skill removal displays demo/alpha and demo/gamma without an entire-plugin row, reports gamma removal, and removes gamma's link and ownership.
Target removal displays both additional roots, retains only Claude in the lock, removes cursor alpha and cursor ownership, and retains primary/Claude alpha links.
Global lock digest is unchanged and global ownership remains absent.

### Notes

Assertions cover JSON, filesystem links, ownership membership, and SHA-256 checksums.

## `interactive_global`

### Scope

Verify nested-directory global operations preserve all project state.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize both scopes. |
| `c-plugin plugin add` | Populate both scopes. |
| `c-plugin skill remove` | Remove global skills. |
| `c-plugin target add` | Add a global target. |
| `c-plugin target remove` | Remove that target. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin` | Scope-relative plugin source. |
| `--all` | Populate project links. |
| `--global` | Select HOME state. |
| `.cursor/skills` | Additional global target. |

### Preconditions and fixtures

Synthetic HOME is `/tmp/c-plugin-standard-interactive-global/home`.
Both sources have alpha/beta/gamma, and project lock/state digests are captured after installation.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --all` and create `project/nested`.
2. From nested, run `c-plugin plugin add --global local:./plugin` with Space, Down, Space, Down, Space, Enter.
3. Run `c-plugin target add --global .cursor/skills` from project.
4. From nested, run `c-plugin target remove --global` with Space, Enter.
5. From nested, run `c-plugin skill remove --global` with Space, Down, Down, Space, Enter.

### Expected results

Global add registers all three skills, then removal leaves only beta and its correct global link.
Global cursor alpha and primary alpha/gamma disappear.
Project lock/state digests and all three project links remain unchanged.

### Notes

All terminal operations must succeed and satisfy the shared restoration assertions.

## `interactive_cancel`

### Scope

Verify q and Escape do not mutate files or repair missing links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Populate and cancel replacement. |
| `c-plugin target add` | Populate cursor links. |
| `c-plugin skill remove` | Cancel skill removal. |
| `c-plugin target remove` | Cancel target removal. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Populate fixture. |
| `.cursor/skills` | Additional owned target. |

### Preconditions and fixtures

The shared fixture initializes both scopes with alpha/beta/gamma.
Primary and cursor alpha links are removed externally before exact lock/state byte snapshots.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --all`, then `c-plugin target add .cursor/skills`.
2. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin target remove`, each with q.
3. Repeat the same ordered commands with Escape.

### Expected results

Each exits 0 with `Cancelled; no changes.`.
Each preserves exact lock/state bytes, leaves both alpha links missing, and retains the correct beta link.

### Notes

`interactiveNoOp` shares this exact contract with EOF coverage, not an additional registered example.

## `interactive_empty`

### Scope

Verify empty removal selections are no-ops and plugin selection replaces the enabled set.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Register and replace enabled skills. |
| `c-plugin target add` | Add cursor target. |
| `c-plugin skill remove` | Confirm empty selection. |
| `c-plugin target remove` | Confirm empty selection. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Register fixture skills. |
| `.cursor/skills` | Additional target. |

### Preconditions and fixtures

The isolated plugin has alpha/beta/gamma.
The fixture removes both alpha links before byte-preservation checks.

### Execution flow

1. Run `c-plugin plugin add local:./plugin` with Enter and verify empty registration, ownership, and absent links.
2. Run `c-plugin plugin add local:./plugin --all`, then `c-plugin target add .cursor/skills`.
3. Run `c-plugin skill remove`, then `c-plugin target remove`, each with Enter, then repeat each with Space, Space, Enter.
4. Run `c-plugin plugin add local:./plugin` with Enter to disable all skills.
5. Run the same argv with Down, Space, Enter to enable beta.
6. Run the same argv with Space, Down, Down, Space, Enter to replace beta with alpha/gamma.

### Expected results

Empty removals report `No selection; no changes.`, preserve bytes and absent alpha links, and retain beta.
The first add registers a plugin with no enabled skills and empty ownership.
The later empty add displays all enabled labels and removes every skill link from both roots while retaining the cursor target.
Beta-only selection displays beta disabled.
Replacement displays alpha/gamma disabled and beta enabled, records only alpha/gamma, removes beta from both roots, and creates correct alpha/gamma links in both roots.

### Notes

Space twice exercises clearing a selection before confirmation.

## `interactive_invalid`

### Scope

Verify ignored non-navigation keys, arrow navigation, scrolling, and resize safety.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Select from ordinary and long menus. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin` | Explicit plugin source. |

### Preconditions and fixtures

The ordinary fixture has alpha/beta/gamma.
The source is then rewritten with 50 skills named scroll-00 through scroll-49.

### Execution flow

1. Run `c-plugin plugin add local:./plugin` with `1,199xyz`, Space, Space, Down, Space, Up, Space, Enter.
2. Rewrite the plugin with the 50 scrolling skills.
3. Run the same argv, wait for the menu, resize to 2x80 with `resizeTerminal`, and wait for `Enlarge terminal`.
4. Capture lock/state with `captureSnapshot`, send Enter, and require a 0.2-second `waitTerminal` deadline with a still-running child and empty stdout.
5. Compare lock/state to the captured snapshot, resize to 12x80, wait for the selection footer, and send 52 Down keys, Space, Enter.

### Expected results

The first invocation registers alpha/beta, links both, and leaves gamma absent.
Caseyard shrinks to 2x80, sends SIGWINCH, and proves Enter neither completes nor produces stdout during the 0.2-second observation.
Public snapshots prove lock/state bytes remain unchanged after that observation.
Caseyard enlarges to 12x80 and sends SIGWINCH before selection can complete.
The transcript includes scroll-49 disabled, only scroll-49 is registered/linked, and alpha/beta/gamma plus scroll-00 through scroll-48 are absent.

### Notes

Haskell owns the ordered resize, keyboard, bounded observation, and persistence assertions.
Caseyard owns Linux PTY transport, normalized termios observations, and process-group delivery of SIGWINCH.

## `interactive_no_input`

### Scope

Verify explicit no-input mode rejects missing selectors even on a terminal.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Reject omitted enabled-set selector. |
| `c-plugin skill remove` | Reject omitted skill selector. |
| `c-plugin target remove` | Reject omitted target selector. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--no-input` | Disable prompting. |
| `local:./plugin` | Plugin source. |
| `--all`, `--none`, `--skill`, `--target` | Required guidance in errors. |

### Preconditions and fixtures

All skills and cursor target are populated, primary alpha is removed, and lock/state bytes are saved.

### Execution flow

1. Run `c-plugin --no-input plugin add local:./plugin`.
2. Run `c-plugin --no-input skill remove`.
3. Run `c-plugin --no-input target remove`.

### Expected results

Every call fails without a prompt, preserves exact lock/state bytes, and leaves alpha absent.
Add stdout includes `--all`, `--none`, and `--skill`.
Skill and target removal stdout include `--skill` and `--target`, respectively.

### Notes

`interactiveNonTerminal` shares the setup and checks without combining registered cases.

## `interactive_pipe`

### Scope

Verify piped stdin is not consumed when selectors are absent.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Reject nonterminal selection. |
| `c-plugin skill remove` | Reject nonterminal selection. |
| `c-plugin target remove` | Reject nonterminal selection. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin` | Plugin source. |
| `--all`, `--none`, `--skill`, `--target` | Required error guidance. |

### Preconditions and fixtures

The no-input setup is repeated in a separate container with a pipe containing `unconsumed-input\n` and terminal stderr.

### Execution flow

1. Run `c-plugin plugin add local:./plugin` with pipe stdin.
2. Run `c-plugin skill remove` with pipe stdin.
3. Run `c-plugin target remove` with pipe stdin.

### Expected results

Every call fails without a prompt and retains the entire pipe payload.
Option guidance, exact lock/state byte preservation, and absent alpha checks match no-input coverage.

### Notes

This detects accidental reads, not merely failure status.

## `interactive_interrupt`

### Scope

Verify keyboard interruption, process-group SIGINT, and terminal initialization failure preserve state.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Populate fixture. |
| `c-plugin skill remove` | Interrupt or fail terminal initialization. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Populate all skills. |
| `TERM=c-plugin-no-such-terminal` | Force initialization failure. |

### Preconditions and fixtures

Primary alpha is removed externally after installation, and exact lock/state bytes are saved.

### Execution flow

1. Run `c-plugin skill remove` with Ctrl+C.
2. Run the same argv with `signalTerminal terminal Interrupt` after the prompt.
3. Run the same argv with no actions and the invalid TERM value.

### Expected results

Both interrupt paths fail without the successful cancellation message.
Invalid TERM fails without displaying the selection footer.
Every path preserves bytes, missing alpha, and the correct beta link, and satisfies termios/display restoration.

### Notes

Keyboard Ctrl+C uses `sendTerminal` with the literal byte, while external SIGINT uses the distinct public `signalTerminal` operation.
Caseyard delivers the external signal to the process group and scopes session cleanup.
Typed terminal status distinguishes ordinary nonzero exit from signal termination.

## `interactive_eof`

### Scope

Verify Ctrl+D cancellation is a non-mutating successful operation.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Cancel enabled-set replacement. |
| `c-plugin skill remove` | Cancel skill removal. |
| `c-plugin target remove` | Cancel target removal. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Populate fixture. |
| `.cursor/skills` | Additional owned target. |

### Preconditions and fixtures

Use a separate isolated fixture with missing primary/cursor alpha links and saved exact bytes.

### Execution flow

1. Populate with `c-plugin plugin add local:./plugin --all` and `c-plugin target add .cursor/skills`.
2. Run `c-plugin plugin add local:./plugin`, `c-plugin skill remove`, and `c-plugin target remove`, each with Ctrl+D.

### Expected results

Every call exits 0 with `Cancelled; no changes.`, preserves exact lock/state bytes and both absent alpha links, and retains beta's correct link.

### Notes

The EOF example reuses `interactiveNoOp` without adding a tenth case.
