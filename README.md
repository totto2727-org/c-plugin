# c-plugin

c-plugin installs skills from local [Agent Plugins 1.0](https://agent-plugins.org/specification) packages into `.agents/skills` and optional additional targets.
It is a Haskell CLI built with Cabal and Iris.
It supports skills only, not MCP servers, hooks, vendor-specific formats, marketplaces, or remote repository management.

## Usage

Given a local plugin with this layout:

```text
demo/
├── plugin.json
└── skills/
    └── alpha/
        └── SKILL.md
```

`plugin.json`:

```json
{
  "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "demo"
}
```

`skills/alpha/SKILL.md`:

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
c-plugin skill add --local ./demo
```

The commands create `c-plugin-lock.json` and link `.agents/skills/alpha` to the skill directory.
Add `--skill alpha` to install only that skill, or repeat `--skill` to select several skills.
Without a selection, add installs all valid skills.
Use `-g` for the lock and skill links in `HOME`.

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
No package registry release or hosted binary distribution is claimed.

## Reference

See the [CLI reference](docs/cli.md) for commands, scopes, and safety behavior.
Use `c-plugin --help` or `c-plugin skill add --help` for command help.

## Development

See [AGENTS.md](AGENTS.md) for repository tasks and the [design contract](docs/design/contract.md) for implementation constraints.

## License

[MIT](LICENSE).
