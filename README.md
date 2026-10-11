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

The plugin command loads exactly the supplied root and offers a numbered skill selection in a terminal.
Enter a number such as `1`, several numbers separated by spaces or commas, or `all`.
An empty line or `q` cancels without changing the configuration.
Repeating `plugin add` configures that plugin's enabled skill set; `none` disables all its skills.
The command does not scan other plugin roots.

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
> Lock version `"3"` is required. Other versions are rejected without conversion.
> Existing paths are preserved unless explicit add force can safely replace an exact file or symlink collision.

## Setup

Build the CLI from this checkout with [Nix](https://nixos.org/download/):

```sh
nix build .#c-plugin
./result/bin/c-plugin --help
```

The CLI requires a POSIX filesystem with symlink support and write access to the lock and target directories.
Git must be available on PATH for GitHub fetches and pinned-source verification.
With GHC 9.4.8 and Cabal installed without Nix, build and run:

```sh
cabal build exe:c-plugin
"$(cabal list-bin exe:c-plugin)" --help
"$(cabal list-bin exe:c-plugin)" sync
```

No package registry release or hosted binary distribution is claimed.

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
`sync` reconciles both plugins and standalone skills from pinned snapshots offline.
`update` refreshes both kinds at their configured refs, then synchronizes links.
Use `-r` to include descendant project locks, or `-g` for the independent HOME lock, but not both.
See [CLI reference](docs/cli.md) for the original discovery-library ignore rules and cache safety constraints.

## Development

See [AGENTS.md](AGENTS.md) for repository tasks and the [design contract](docs/design/contract.md) for implementation constraints.

## License

[MIT](LICENSE).
