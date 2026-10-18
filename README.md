# c-plugin

c-plugin installs skills from local or pinned GitHub [Agent Plugins 1.0](https://agent-plugins.org/specification) packages into `.agents/skills` and optional additional targets.
It is a Haskell CLI built with Cabal and Iris.
It supports skills only, not MCP servers, hooks, vendor-specific formats, marketplaces, or non-GitHub remotes.

## Usage

Given a local directory with this layout:

```text
plugins/
└── demo/
    ├── plugin.json
    └── skills/
        └── alpha/
            └── SKILL.md
```

`plugins/demo/plugin.json`:

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "demo"
}
```

`plugins/demo/skills/alpha/SKILL.md`:

```markdown
---
name: alpha
description: Help with a specific task.
---
Instructions for the task.
```

Run these commands from the project root:

```sh
c-plugin init
c-plugin plugin add local:./plugins/demo
```

The plugin command loads exactly the supplied root and offers a skill selection in a terminal.
Use Up/Down to move, Space to select skills, and Enter to confirm.
Esc or `q` cancels without changing the configuration.
Repeating `plugin add` replaces that plugin's enabled skill set; confirming an empty selection disables all its skills.
The command does not scan other plugin roots.

Inspect registrations and control an installed plugin:

```sh
c-plugin list
c-plugin plugin list
c-plugin skill list
c-plugin plugin skill disable demo --skill alpha
c-plugin plugin skill enable demo --skill alpha
```

Listing is read-only and does not fetch sources or repair links.
Enable and disable preserve the plugin registration and its pinned source.
Omit the plugin name to choose a registered plugin interactively, then choose its skills.
Outside a terminal, supply the plugin name and an explicit `--skill` or `--all` selection.
Use `--all` to control every skill, or omit the selector for terminal selection.
Use `c-plugin plugin remove --plugin demo` to unregister the plugin and remove its owned skill links.
Additional link roots use top-level `c-plugin target add PATH` and `c-plugin target remove --target PATH`.

For scripts, choose explicitly:

```sh
c-plugin --no-input plugin add local:./plugins/demo --skill alpha
c-plugin --no-input plugin add local:./plugins/demo --all
c-plugin --no-input plugin add local:./plugins/demo --none
```

To install just one skill without a plugin manifest, supply its own directory:

```sh
c-plugin skill add local:./plugins/demo/skills/alpha
```

Only a valid `SKILL.md` directly in that directory is required.
Use either the plugin workflow or the standalone workflow for a given enabled skill name, not both.
The commands create `c-plugin-lock.json` and link `.agents/skills/alpha` to the skill directory.
Use `-g` for the lock and skill links in `HOME`.
See [interactive selection](docs/cli.md#interactive-selection) for removal, cancellation, and non-terminal behavior.

> [!IMPORTANT]
> Internal lock and ownership files use the default JSON representation of their Haskell types. Legacy wire formats are not converted.
> Existing paths are preserved unless explicit add force can safely replace an exact file or symlink collision.

## Setup

Build the CLI from this checkout with [Nix](https://nixos.org/download/):

```sh
nix build .#c-plugin
./result/bin/c-plugin --help
```

The CLI requires a POSIX filesystem with symlink support and write access to the lock and target directories.
GitHub transport uses the official gitlib and gitlib-cmdline packages with the Git executable.
To build and run with hpack and Cabal, use the pinned Nix toolchain:

```sh
nix develop
hpack
cabal build exe:c-plugin
"$(cabal list-bin exe:c-plugin)" --help
"$(cabal list-bin exe:c-plugin)" sync
```

No package registry release or hosted binary distribution is claimed.
Git is a runtime dependency, not just a build tool.
The Nix package supplies Git through its executable wrapper, and the development shell includes Git.

## Reference

See the [CLI reference](docs/cli.md) for commands, scopes, and safety behavior.
Use `c-plugin --help` or `c-plugin plugin add --help` for command help.

## GitHub sources

Specify one repository and one explicit plugin directory:

```sh
c-plugin plugin add github:totto2727-org/agent/plugins/totto2727-coding --all
c-plugin sync
c-plugin update
```

The repository is `totto2727-org/agent`, not `totto2727-org/agents`.
For an individual skill instead of the whole plugin, use `skill add github:OWNER/REPO/path/to/skill`.
Do not enable the same skill through both a plugin and a standalone registration.
A source prefix is mandatory: `github:OWNER/REPO/path/to/root` or `local:./path/to/root`.
Raw repository names and paths are errors, not guessed sources.
`--ref` selects a branch, tag, or commit, and defaults to remote HEAD.
Fetches use fixed GitHub HTTPS URLs at shallow depth one.
Network operations use installed Git configuration and credential helpers without interactive prompts.
For private repositories, configure credentials that work noninteractively before running c-plugin.
`sync` reconciles both plugins and standalone skills from pinned snapshots offline.
`update` refreshes both kinds at their configured refs, then synchronizes links.
Use `-r` to include descendant project locks, or `-g` for the independent HOME lock, but not both.
See [CLI reference](docs/cli.md) for the original discovery-library ignore rules and cache safety constraints.
See [Git transport](docs/design/git-transport.md) for offline configuration isolation, authentication boundaries, and cache safety.

## Development

See [AGENTS.md](AGENTS.md) for repository tasks and the [design contract](docs/design/contract.md) for implementation constraints.

## License

[MIT](LICENSE).
