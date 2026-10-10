# Standard plugin skills and containment

Source: [standard_plugin_test.go](./standard_plugin_test.go)

## `standardMinimalScenario`

### Scope

Verify that a minimal standard manifest discovers all valid immediate skills when add has no selections, and plugin removal cleans up their owned links.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project lock. |
| `c-plugin skill add` | Add all discovered skills. |
| `c-plugin skill remove` | Remove the plugin. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Load the local standard plugin. |
| `--plugin demo` | Remove the manifest-named plugin. |

### Preconditions and fixtures

- A fresh disposable container uses `HOME=/tmp/c-plugin-standard-minimal/home` and `project=$HOME/project`.
- The executable is `/sandbox/.local/bin/c-plugin`; all invocations use the helper's direct argv and isolated HOME.
- `plugin/plugin.json` contains only canonical `$schema: https://agent-plugins.org/schemas/1.0.0/plugin.schema.json` and `name: demo`.
- Immediate alpha and beta skill directories have regular `SKILL.md` files with matching YAML names and nonempty descriptions.

### Execution flow

1. Write fixtures and run `c-plugin init` from `project`.
2. Run `c-plugin skill add --local ./plugin` from `project` with no `--skill` selections.
3. Inspect lock, links, and ownership, then run `c-plugin skill remove --plugin demo` from `project`.
4. Inspect empty lock, missing links, and empty ownership state.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit status | Both mutations exit 0. |
| Output | Add contains `Added <project>/plugin to <lock>: partial`; removal contains `Removed plugins demo from <lock>:`. |
| Lock | Add yields version `3`, targets `[]`, and plugin `{source:"./plugin",name:"demo",skills:["alpha","beta"]}`. Removal yields `{"version":"3","targets":[],"plugins":[]}`. |
| Filesystem/state | Both links resolve to their plugin skill directories and are recorded as owned after add. Removal removes both links and yields `{"version":"1","entries":[]}`. |

### Notes

- These are assertions, not test-run results. Notice counts are not fixed.

## `standardEmptyScenario`

### Scope

Verify that a plugin without a skills location is valid and can be registered with no selected skills.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Register an empty plugin. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the local plugin. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-empty/home` and `project=$HOME/project`.
- `plugin/plugin.json` is the canonical minimal demo manifest. No `skills` directory exists.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write the manifest and run `c-plugin init` from `project`.
2. Run `c-plugin skill add --local ./plugin` from `project`.
3. Inspect the lock and missing skill links.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit/output | Exit 0; output contains `Added <project>/plugin`. |
| Lock | Version `3`, targets `[]`, plugin `{source:"./plugin",name:"demo",skills:[]}`. |
| Filesystem/state | No alpha or beta link exists; ownership is exactly `{"version":"1","entries":[]}`. |

### Notes

- A missing skills component is not an invalid plugin. These are assertions, not execution results.

## `standardUnknownFieldScenario`

### Scope

Verify every unknown top-level manifest field is reported and ignored, without redirecting fixed skill discovery.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Load a manifest with unknown fields. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the local plugin. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-unknown/home` and `project=$HOME/project`.
- Canonical demo manifest additionally contains `skills:"./elsewhere"` and `custom:true`.
- A valid alpha is in `skills/alpha`; valid beta is only in `elsewhere/beta`.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write the minimal fixture and run `c-plugin init` from `project`.
2. Replace the manifest with unknown fields and write the alternative beta fixture.
3. Run `c-plugin skill add --local ./plugin` from `project`.
4. Inspect both warnings, the selected alpha, and absent beta.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit/output | Exit 0; output contains `Warning: unknown top-level field: skills` and `Warning: unknown top-level field: custom`. |
| Lock | Version `3`, targets `[]`, demo source `./plugin`, skills `["alpha"]`. |
| Filesystem | Alpha links to `<project>/plugin/skills/alpha`; no beta link exists. |

### Notes

- Unknown fields have no discovery semantics. Warning ordering is not asserted. These are expected assertions.

## `standardWrongSchemaScenario`

### Scope

Verify an unsupported schema rejects the plugin before persisting or managing skills.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Attempt invalid schema loading. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the invalid local plugin. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-wrong-schema/home` and `project=$HOME/project`.
- Alpha is valid, but the demo manifest declares `$schema: https://example.invalid/plugin.schema.json`.
- A foreign target file contains `foreign\n`; the initialized lock's digest is recorded.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write the valid fixture and run `c-plugin init` from `project`.
2. Replace the schema, write the foreign target file, and record the lock digest.
3. Run `c-plugin skill add --local ./plugin` from `project`.
4. Compare the lock digest, missing state/link, and foreign content.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit/output | Nonzero exit containing `totto2727/c-plugin.AddLocalError.InvalidInput`. |
| Non-mutation | Lock digest is unchanged; no ownership state or alpha link is created; foreign contents stay `foreign\n`. |

### Notes

- Component discovery must not turn a fatal manifest violation into a persisted partial candidate. These are expected assertions.

## `standardInvalidSkillScenario`

### Scope

Verify an invalid skill is skipped without preventing a valid sibling from loading.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Discover valid and invalid siblings. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the local plugin. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-invalid-skill/home` and `project=$HOME/project`.
- The manifest is canonical demo; alpha is valid; beta has YAML `name: beta` but lacks required `description`.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write valid alpha and run `c-plugin init` from `project`.
2. Write beta's invalid `SKILL.md`.
3. Run `c-plugin skill add --local ./plugin` from `project`.
4. Inspect the warning, selected alpha, skipped beta, and ownership state.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit/output | Exit 0; output contains `Warning: invalid skill beta:`. |
| Lock/filesystem | Version `3`, demo source `./plugin`, skills `["alpha"]`; alpha links to its plugin directory and beta has no link. |
| Ownership | No beta entry is recorded. |

### Notes

- The invalid fixture violates the [Agent Skills specification](https://agentskills.io/specification) required description field. These are expected assertions.

## `standardShallowDiscoveryScenario`

### Scope

Verify fixed skill discovery examines immediate directories only, not deep descendants.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Discover immediate skills. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the local plugin. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-shallow/home` and `project=$HOME/project`.
- The canonical demo plugin has valid `skills/alpha/SKILL.md` and valid `skills/group/beta/SKILL.md`, but no `skills/group/SKILL.md`.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write alpha and run `c-plugin init` from `project`.
2. Write the nested beta fixture.
3. Run `c-plugin skill add --local ./plugin` from `project`.
4. Inspect the exact selection and missing deep-discovery links.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit | Exit 0. |
| Lock/filesystem | Version `3`, demo source `./plugin`, skills `["alpha"]`; alpha links to its plugin directory; beta and group links are absent. |

### Notes

- This is component discovery depth, not recursive project lock discovery. These are expected assertions.

## `standardManifestEscapeScenario`

### Scope

Verify a physically escaping root manifest rejects the entire plugin without changing lock or foreign paths.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Attempt loading an escaping manifest. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the plugin with an escaping manifest symlink. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-manifest-escape/home` and `project=$HOME/project`.
- Valid alpha remains inside the plugin, but `plugin/plugin.json` symlinks to valid `<project>/outside/plugin.json`, physically outside the plugin root.
- The outside manifest and initialized lock digests are recorded. A foreign managed-root file contains `foreign\n`.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write valid alpha and run `c-plugin init` from `project`.
2. Write the outside manifest, replace the root manifest with its symlink, write foreign content, and record digests.
3. Run `c-plugin skill add --local ./plugin` from `project`.
4. Inspect rejection, both digests, absent state/alpha, and foreign content.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit/output | Nonzero exit containing `outside plugin root`. |
| Non-mutation | Lock and outside manifest digests are unchanged; ownership state and alpha link are absent; foreign content remains `foreign\n`. |

### Notes

- Containment is physical, not a lexical check of the plugin-relative manifest path. These are expected assertions.

## `standardSkillsEscapeScenario`

### Scope

Verify physically escaping fixed skills location is rejected as a component, while the otherwise valid plugin can be registered empty.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Load the manifest and reject the escaping component. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the plugin with an escaping skills symlink. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-skills-escape/home` and `project=$HOME/project`.
- The canonical demo plugin's `skills` path symlinks to `<project>/outside`, containing valid alpha outside the plugin root.
- The outside `SKILL.md` digest is recorded.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write the minimal empty plugin and run `c-plugin init` from `project`.
2. Write outside alpha, record its digest, and create the escaping skills symlink.
3. Run `c-plugin skill add --local ./plugin` from `project`.
4. Inspect containment output, empty plugin selection, missing alpha link, and outside digest.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit/output | Exit 0 with output containing `outside plugin root`. |
| Lock | Version `3`, demo source `./plugin`, skills `[]`. |
| Safety | Alpha is not linked; outside `SKILL.md` digest is unchanged; ownership is exactly `{"version":"1","entries":[]}`. |

### Notes

- The [Agent Plugins specification](https://agent-plugins.org/specification) requires the narrow component failure boundary, not fatal rejection of the manifest. These are expected assertions.

## `standardSkillFileEscapeScenario`

### Scope

Verify a physically escaping discovered `SKILL.md` is skipped while a valid immediate sibling remains installable.

### Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the lock. |
| `c-plugin skill add` | Discover skills and reject the escaping file. |

### Arguments and options

| Argument or option | Purpose |
| --- | --- |
| `--local ./plugin` | Select the local plugin. |

### Preconditions and fixtures

- A fresh container uses `HOME=/tmp/c-plugin-standard-skill-file-escape/home` and `project=$HOME/project`.
- Alpha is valid inside the canonical demo plugin; `skills/beta/SKILL.md` symlinks to valid `<project>/outside/SKILL.md` outside the plugin root.
- The outside file's digest is recorded.
- The executable is `/sandbox/.local/bin/c-plugin` with direct argv and isolated HOME.

### Execution flow

1. Write alpha and run `c-plugin init` from `project`.
2. Write outside beta, record its digest, and create beta's escaping `SKILL.md` symlink.
3. Run `c-plugin skill add --local ./plugin` from `project`.
4. Inspect the invalid-skill warning, containment reason, selected alpha, skipped beta, and outside digest.

### Expected results

| Observation | Expected result |
| --- | --- |
| Exit/output | Exit 0; output contains `Warning: invalid skill beta:` and `outside plugin root`. |
| Lock/filesystem | Version `3`, demo source `./plugin`, skills `["alpha"]`; alpha links to its plugin directory and beta has no link. |
| Safety | The outside `SKILL.md` digest is unchanged. |

### Notes

- The narrow failure boundary is one skipped skill, not rejection of the valid sibling or entire manifest. These are expected assertions.
