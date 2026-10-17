# Unified command hierarchy and plugin policy

Source: [unified_api_test.go](./unified_api_test.go)

## `unifiedHelpHierarchyScenario`

### Scope

Verify help for the unified hierarchy, selector placement, and non-mutating rejection of retired aliases.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin` | Inspect top-level help. |
| `c-plugin plugin` | Inspect plugin command help. |
| `c-plugin skill` | Inspect skill command help without retired children. |
| `c-plugin target` | Inspect top-level target help. |
| `c-plugin plugin add` | Prepare one owned link. |
| `c-plugin sync` | Inspect help and reject misplaced selectors. |
| `c-plugin update` | Inspect help and reject misplaced selectors. |
| `c-plugin list` | Inspect help and reject selectors. |
| `c-plugin plugin list` | Inspect help and reject selectors. |
| `c-plugin skill list` | Inspect help and reject selectors. |
| `c-plugin plugin remove` | Verify plugin-only removal option. |
| `c-plugin skill remove` | Verify skill-only removal option. |
| `c-plugin plugin skill enable` | Inspect enable help. |
| `c-plugin plugin skill disable` | Inspect disable help. |
| `c-plugin target add` | Inspect target-add help. |
| `c-plugin target remove` | Inspect target-remove help and reject unrelated selectors. |
| `c-plugin skill sync` | Reject the retired alias. |
| `c-plugin skill update` | Reject the retired alias. |
| `c-plugin skill target add` | Reject the retired alias. |
| `c-plugin skill target remove` | Reject the retired alias. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Prepare demo/alpha. |
| `--help` | Inspect each supported node without changing state. |
| `--plugin demo` | Legal only for whole-plugin removal, not skill/target removal, list, or update. |
| `--skill alpha`, `--skill demo/alpha` | Illegal on unrelated command paths. |
| `.cursor/skills`, `--target .cursor/skills` | Ensure retired target aliases cannot mutate targets. |

### Preconditions and fixtures

- A disposable container has synthetic `HOME=/tmp/c-plugin-standard-unified-help/home` and `project=$HOME/project`.
- The executable is `/sandbox/.local/bin/c-plugin`.
- The standard fixture initializes a project lock and a demo plugin containing alpha, then adds alpha and records desired/ownership digests.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --all` and capture lock/state digests.
2. Run `c-plugin --help`, then append `--help` to these ordered paths: `plugin`, `skill`, `target`, `sync`, `update`, `list`, `plugin list`, `plugin remove`, `skill list`, `skill remove`, `plugin skill enable`, `plugin skill disable`, `target add`, `target remove`.
3. Inspect `c-plugin plugin remove --help`, `c-plugin skill --help`, and `c-plugin skill remove --help` for separated selectors and absent retired children.
4. Run, in order, `c-plugin skill sync`, `c-plugin skill update`, `c-plugin skill target add .cursor/skills`, `c-plugin skill target remove --target .cursor/skills`, `c-plugin skill remove --plugin demo`, and `c-plugin plugin remove --skill demo/alpha`.
5. Run, in order, `c-plugin target remove --plugin demo`, `c-plugin target remove --skill alpha`, `c-plugin list --skill alpha`, `c-plugin plugin list --plugin demo`, `c-plugin skill list --skill alpha`, `c-plugin sync --skill alpha`, and `c-plugin update --plugin demo`.
6. After every rejected argv, compare digests, verify the alpha link, and verify `.cursor` is absent.

### Expected results

- Every supported help path exits 0 and includes `Available options:`.
- Plugin removal advertises `--plugin` without `--skill`; skill removal advertises `--skill` without `--plugin`.
- Skill help has no sync, update, or target child.
- Every retired alias or misplaced selector exits nonzero without changing desired/ownership bytes or links.

### Notes

The invalid commands in the command table are deliberate rejection coverage, not supported usage examples.
These assertions do not establish product execution until the caller runs the Docker scenario.

## `pluginToggleScenario`

### Scope

Verify incremental enable/disable, disabled-plugin retention, atomic failures, project/global isolation, and real-PTY selection and nonterminal behavior.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize global state. |
| `c-plugin plugin add` | Register local project/global plugins disabled. |
| `c-plugin plugin skill enable` | Union selected valid skills into existing registrations. |
| `c-plugin plugin skill disable` | Subtract selected skills without deleting registrations. |
| `c-plugin skill add` | Prepare a standalone name collision. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--none` | Create an installed plugin with an empty enabled set. |
| `demo` | Optional positional installed-plugin name; omission on a terminal requests exactly one registered plugin. |
| `--skill alpha`, `--skill beta`, `--skill gamma` | Select incremental changes. |
| `--all` | Select all valid registered-source skills, unioning or subtracting them. |
| `-g`, `--global` | Select HOME state independently of project state. |
| `--no-input` | Require an explicit selector even on a PTY. |
| `missing`, `unknown`, `--none`, conflicting selectors | Exercise atomic rejection. |
| `local:./standalone/alpha` | Prepare a conflicting standalone registration. |

### Preconditions and fixtures

- A disposable container has synthetic `HOME=/tmp/c-plugin-standard-plugin-toggle/home`, project demo skills alpha/beta/gamma, and global demo skill gamma.
- The executable is `/sandbox/.local/bin/c-plugin`.
- The shared terminal driver uses actual stdin/stderr PTYs, independently captured stdout, and raw keys after each `Space: toggle` footer.
- Each menu starts with focus on its first sorted row and no selected rows. Enabled markers do not preselect skills.
- Every terminal invocation checks restoration of the original terminal settings.
- Lock assertions use Generic plugin records keyed by name, with enabledSkills and null local pluginOrigin.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --none`, `c-plugin plugin skill enable demo --skill beta`, `c-plugin plugin skill enable demo --skill alpha`, and `c-plugin plugin skill disable demo --skill beta`.
2. Delete alpha's link, record digests, then run `c-plugin plugin skill enable demo --skill alpha` and `c-plugin plugin skill disable demo --skill beta`; verify semantic no-ops do not repair alpha.
3. Run `c-plugin plugin skill enable demo`, then `c-plugin plugin skill disable demo`, each on a real PTY with q. Repeat each command with Enter alone and with Space, Space, Enter. Compare bytes and missing alpha after cancellation and empty-selection no-ops.
4. Run `c-plugin --no-input plugin skill enable demo` on a PTY, then `c-plugin plugin skill enable demo` with piped input; repeat with `c-plugin --no-input plugin skill disable demo` on a PTY and `c-plugin plugin skill disable demo` with piped input; verify missing-selector failure and unconsumed pipe input.
5. Run `c-plugin plugin skill disable demo --all`; then run `c-plugin plugin skill enable demo` on a PTY and press Down, Space, Enter to enable only beta.
6. Run `c-plugin plugin skill disable demo` on a PTY and press Space, Down, Space, Down, Space, Enter to select all skills. Verify the plugin record remains disabled and beta is removed.
7. Run `c-plugin init --global` and `c-plugin plugin add local:./plugin --none --global`; from `project/nested` run `c-plugin plugin skill enable demo --all -g`, then `c-plugin plugin skill disable demo --skill gamma -g`.
8. Check project digests remain unchanged during global operations.
9. Run `c-plugin plugin skill enable missing --all`, `c-plugin plugin skill disable missing --all`, `c-plugin plugin skill enable demo --skill unknown`, `c-plugin plugin skill disable demo --skill unknown`, `c-plugin plugin skill enable --all`, `c-plugin plugin skill disable --all`, `c-plugin plugin skill enable demo --none`, `c-plugin plugin skill disable demo --none`, and `c-plugin plugin skill enable demo --all --skill alpha`; compare digests after every failure.
10. Add `local:./standalone/alpha` with `c-plugin skill add`, then reject `c-plugin plugin skill enable demo --skill alpha` without replacing its standalone link.
11. Write a second plugin named other with valid beta, register it with `c-plugin plugin add local:./other --all`, and capture desired/ownership digests. Reject `c-plugin plugin skill enable demo --skill beta` because beta is enabled by other; verify unchanged bytes and the surviving other/beta link.
12. Run `c-plugin plugin skill enable` on a PTY. Press Space, Down, Space, Enter to select both plugins. After rejection, press Space, Enter in the fresh menu to choose demo. In the skill menu press Down, Down, Space, Enter to choose gamma. Verify sorted demo/other rows, the exact single-plugin retry diagnostic, gamma enabled, and standalone alpha unchanged.
13. Run `c-plugin plugin skill disable` on a PTY. Press Space, Enter to choose demo, then Down, Down, Space, Enter to choose gamma. Verify gamma is removed and desired bytes return exactly to the prior digest.
14. Run `c-plugin --no-input plugin skill enable --all` on a PTY and `c-plugin plugin skill enable --all` with piped input, then the equivalent disable argv; verify missing-PLUGIN errors without prompting, consuming input, or changing bytes.
15. Run `c-plugin plugin skill enable` and `c-plugin plugin skill disable` on separate PTYs. Choose demo with Space, Enter, then cancel the nested skill menu with q, Escape, and Ctrl+D in separate invocations. Compare digests and both collision-fixture links after each cancellation.
16. Remove the synthetic demo plugin source. Run `c-plugin plugin skill enable` and `c-plugin plugin skill disable` on separate PTYs with q, Escape, Ctrl+D, and Enter at the plugin stage. Verify cancellation before any skill prompt or source resolution.
17. Reject `c-plugin plugin skill enable demo --all` and `c-plugin plugin skill disable demo --all` with the missing source, and compare bytes without fallback.

### Expected results

- Enable unions rather than replaces skills; disable subtracts skills.
- Removing the last enabled skill preserves the installed plugin with skills `[]`.
- No-ops and cancellations preserve lock/state bytes and do not repair missing links.
- Empty skill selections report `No skill changes for ` without writes or synchronization. Cancellation remains distinct from Enter confirmation.
- Explicit nonterminal rejection prints `--skill` and `--all` guidance without a prompt or consumption of pipe input.
- Optional-plugin menus contain sorted bare registered names and accept exactly one plugin. A multiple-plugin selection reports `Invalid selection: choose exactly one registered plugin.` and opens a fresh menu before the skill menu.
- Plugin-stage q, Escape, Ctrl+D, and empty Enter cancellation succeeds even when the registration's source is unavailable. It preserves bytes without a skill prompt.
- Cancellation at the nested skill stage also preserves bytes and existing collision-fixture links.
- Missing PLUGIN in noninteractive or `--no-input` mode fails without consuming input.
- Global commands affect only HOME's registration and links.
- Unknown/missing identities, selector mistakes, unavailable source, and name collisions fail atomically.

### Notes

No product build or Docker execution is performed by documentation validation.
The shared helper invokes the executable directly and never touches real user state.

## `separatedRemovalScenario`

### Scope

Verify real-PTY plugin-only and skill-only menus, final-skill disabled retention, cancellation, and preservation of exact-target links without ownership.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin plugin add` | Prepare enabled demo/alpha. |
| `c-plugin skill add` | Prepare standalone solo. |
| `c-plugin sync` | Refuse adoption after ownership loss. |
| `c-plugin skill remove` | Disable the final plugin skill or remove standalone solo. |
| `c-plugin plugin remove` | Delete the disabled whole-plugin registration only. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `local:./plugin`, `--all` | Prepare a single plugin skill. |
| `local:./standalone/solo` | Prepare a standalone skill. |
| `--plugin demo` | Repeat whole-plugin deletion as a no-op. |
| `--skill solo` | Remove only the standalone registration. |

### Preconditions and fixtures

- A disposable container uses synthetic `HOME=/tmp/c-plugin-standard-separated-removal/home` and an initialized project fixture.
- The executable is `/sandbox/.local/bin/c-plugin`.
- Actual managed links initially exist, but their synthetic ownership file is removed before sync, making both links unrecorded.
- The shared terminal driver waits for the real stderr PTY keyboard footer and captures stdout independently.
- It sends raw key bytes without appended newlines and checks terminal settings after each child exits.

### Execution flow

1. Run `c-plugin plugin add local:./plugin --all`, then `c-plugin skill add local:./standalone/solo`.
2. Remove only the synthetic ownership file and run `c-plugin sync`; verify links survive and ownership entries stay empty.
3. Run `c-plugin plugin remove` on separate PTYs with q, Escape, and Ctrl+D. Inspect plugin-only rows and compare desired/ownership digests after each cancellation.
4. Repeat `c-plugin plugin remove` with Enter alone and with Space, Space, Enter. Verify empty-selection no-ops preserve digests and both unowned links.
5. Run `c-plugin skill remove` on a PTY and press Space, Enter. Inspect demo/alpha and standalone solo rows with no entire-plugin row.
6. Verify plugins.demo remains installed with enabledSkills `[]` and pluginOrigin `null`. Verify standaloneSkills.solo retains its installedSkillName, installedSkillSource, and null installedSkillOrigin, while both unowned links survive.
7. Run `c-plugin plugin remove` on a PTY and press Space, Enter. Verify the disabled demo is still selectable and the menu contains no solo row.
8. Verify only standaloneSkills.solo remains registered, all unowned links survive, and ownership stays `{"ownershipEntries":{}}`.
9. Run `c-plugin plugin remove --plugin demo` and compare lock bytes for an unknown-plugin no-op.
10. Run `c-plugin skill remove --skill solo`. Verify an empty desired lock while the unowned solo link survives.

### Expected results

- Every cancellation exits 0 with `Cancelled; no changes.` and unchanged bytes.
- Enter with no selected plugin reports `No selection; no changes.` without changes to bytes or unowned links.
- Skill removal never offers whole-plugin rows and retains the disabled plugin registration.
- Plugin removal offers only whole-plugin rows, including disabled plugins, and does not remove standalone registrations.
- Matching a desired literal link target without ownership does not authorize adoption or deletion.

### Notes

Existing migrated removal scenarios separately cover deletion of genuinely owned links and global last-skill retention.
The unowned-link fixture is entirely inside the disposable container's synthetic HOME.
