# Shared E2E fixtures

Source: [Fixtures.hs](./Fixtures.hs).
The complete module is exported for the sibling Hspec modules.

## Scope

Provide synthetic lock, standard manifest, and skill fixtures without accessing real user state.

## Commands under test

| Command path | Purpose |
| --- | --- |
| `c-plugin init` | Initialize the project in `standardEnvironment`. |

## Arguments and options

`standardEnvironment env name skills` runs `c-plugin init` without extra options.
`writePlugin s root skills` places the manifest under `root/plugin` and each skill under `root/plugin/skills/<skill>/SKILL.md`.
`localLock targets repository skills` uses plugin identity `demo`, the supplied relative source and selections, a null origin, and an empty standalone map.

## Preconditions and fixtures

- `emptyLock` is `{"targets":[],"plugins":{},"standaloneSkills":{}}`.
- `soloLock` contains no targets or plugins and one standalone `solo` registration with source `standalone/solo` and a null origin.
- `pluginSchema` is `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`.
- `pluginJSON` contains `$schema`, name `demo`, and a trailing newline.
- `skillMarkdown name` contains YAML frontmatter with name and `description: Fixture <name> skill.`.
- `standardEnvironment` uses `/tmp/c-plugin-standard-<name>/home` and its `project` child.

## Execution flow

1. Call `newScenario` with the public Caseyard environment and synthetic home to install the trusted driver from host `C_PLUGIN_E2E_DRIVER` once.
2. Write the exact standard manifest and requested skill frontmatter.
3. Initialize the project lock and require success.
4. Return the scenario and project path to the owning Hspec example.

## Expected results

No fixture builds an image, opens a second environment, or creates a separately registered example.
All text files use the Support UTF-8 writer.
Lock object key order is irrelevant because `requireJSON` compares Aeson values.
Checksum and exact-byte snapshots are recorded after fixture creation.

## Notes

`standardEnvironment` is a shared setup helper, not an additional registry case.
Empty skill lists create no `skills` directory, which is required by the symlink-escape fixtures.
