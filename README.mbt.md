# c-plugin

<!-- Temporary: this feature PR intentionally precedes complete command integration.
Remove this availability note in S17 after the bit adapter and all eight Go cases are integrated. -->
**Current feature stage: S2.**
Available CLI entrypoints: help/version.
Later-stage commands and their examples below are specifications, not executable claims for this checkout.

c-plugin is a native MoonBit command-line project for managing agent skills across project and global scopes.
The complete feature stack introduces initialization, local skill lifecycle, recursive sync, additional targets, and the bit adapter.
GitHub leaf workflows, interactive selection, marketplace authoring, and a supported standalone release remain unavailable.

## Usage

Once S7 introduces `init`, initialize the current project before adding local skills (local add enters in S13):

```bash
c-plugin init
```

Expected result: a new `c-plugin-lock.json` containing the empty version-2 lock and `Created <absolute lock path>` followed by a newline.
An existing lock is rejected without being overwritten.
The [CLI reference](./docs/cli.md) describes local add, synchronization, removal, additional targets, and their fixture-dependent results.
See the [capability status](./docs/cli.md#capability-status) for implemented commands and planned features.

## Key features

- Project/global initialization and explicit local skill selection.
- Ownership-aware synchronization, recursive project synchronization, and additional skill targets.
- Strict versioned locks and preservation of foreign paths, with a narrowly scoped explicit force option.

GitHub installation and updates, interactive selection, and marketplace authoring remain planned rather than available features.

## Prerequisites

The native CLI requires filesystem permissions for its project/global lock, cache, and managed links.
Reading the documentation requires no toolchain.

## Setup

No supported standalone release or installation route is documented yet.
Mooncakes publication, release artifacts, and standalone Nix acquisition commands will be added only after their actual availability has been verified.
Source availability is not evidence of a published package.

## API

The [CLI reference](./docs/cli.md) documents the implemented command subset, observable results, duplicate rejection, and safety constraints.
The [design contract](./docs/design/contract.md) separately records intended behavior and future milestones.
Neither source claims that the complete design is implemented.

## Development

For repository development and validation, see [AGENTS.md](./AGENTS.md).

## License

[MIT](./LICENSE)

_This README was generated from the [share-artifact skill](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/SKILL.md) and [README template](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/readme/template.md)._
