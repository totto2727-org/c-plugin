# MoonBit Simple CLI Template

A GitHub repository template for starting a small MoonBit command-line application with a dependency-free Hello World example.

## Usage

Run the sample directly from the MoonBit source package:

```console
$ moon run src
Hello, world!
```

When the optional Nix package is retained, it exposes the same command:

```console
$ nix run .
Hello, world!
```

## Key features

- Dependency-free MoonBit Hello World command-line sample
- Runs directly from MoonBit source or through the optional Nix command
- Predictable standard output and exit behavior for the starter command

## Prerequisites

- **GitHub**: Create a repository with GitHub's **Use this template** flow.
- **MoonBit**: Install the MoonBit toolchain and `moon` command for the primary `moon run src` path.
- **Nix (optional)**: Install Nix only to use the alternative packaged `nix run .` path.

## Setup

1. Create a repository with GitHub's **Use this template** button.
2. Clone the created repository.

## API

### `project`

The sample command accepts no defined options or positional arguments. Extra arguments are ignored, successful execution writes exactly `Hello, world!` followed by a newline to standard output, writes nothing to standard error, and exits with status 0. The sample has no expected runtime failure condition.

```console
$ moon run src
Hello, world!
```

## Development

For development guidance, see [AGENTS.md](./AGENTS.md).

## License

[MIT](./LICENSE)

_This README was generated from the [share-artifact skill](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/SKILL.md) and [README template](https://raw.githubusercontent.com/totto2727-org/agent/refs/heads/main/plugins/totto2727-coding/skills/share-artifact/readme/template.md)._
