# c-plugin

c-plugin is a native MoonBit command-line project for managing agent skills across project and global scopes.
The independent repository introduces the saved implementation through reviewable feature layers.

<!-- migration-stage:start -->
**Current stage: S17, saved implementation integrated.**
Initialization, local skill lifecycle, recursive sync, additional targets, and the bit adapter are present.
GitHub leaf workflows, interactive selection, marketplace authoring, and a supported standalone release remain unavailable.
<!-- migration-stage:end -->

## Usage

On an implementation stage that provides `init`, initialize the current project before adding local skills:

```bash
c-plugin init
```

Expected result: a new `c-plugin-lock.json` containing the empty version-2 lock and `Created <absolute lock path>` followed by a newline.
An existing lock is rejected without being overwritten.
The [CLI reference](./docs/cli.md) describes local add, synchronization, removal, additional targets, and their fixture-dependent results.
Check the current stage above and the [capability status](./docs/cli.md#capability-status) before relying on a command.

## Key features

- Project/global initialization and explicit local skill selection in the saved implementation.
- Ownership-aware synchronization, recursive project synchronization, and additional skill targets.
- Strict versioned locks and preservation of foreign paths, with a narrowly scoped explicit force option.

GitHub installation and updates, interactive selection, and marketplace authoring remain planned rather than available features of the saved implementation.

## Prerequisites

A stage that provides the native CLI requires filesystem permissions for its project/global lock, cache, and managed links.
Reading the documentation requires no toolchain.
No published installation route is asserted by this migration baseline.

## Setup

No supported standalone release or installation route is documented yet.
Mooncakes publication, release artifacts, and standalone Nix acquisition commands will be added only after their actual availability has been verified.
The repository and its saved implementation snapshot are not evidence of a published package.

## API

The [CLI reference](./docs/cli.md) documents the saved command subset, observable results, duplicate rejection, and safety constraints.
The [design contract](./docs/design/contract.md) separately records intended behavior and future milestones.
Neither source claims that the complete design is implemented.

## Development

For repository development and validation, see [AGENTS.md](./AGENTS.md).

## License

[MIT](./LICENSE)

_This README was generated from the [share-artifact skill](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/SKILL.md) and [README template](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/readme/template.md)._
