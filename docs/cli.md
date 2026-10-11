# CLI reference

This reference is for users who already have the CLI and a local plugin or skill directory.
See [README.md](../README.md) for setup and a minimal example.

## Commands

```text
c-plugin init [-g]
c-plugin plugin add --local ./plugin [--skill alpha ... | --all | --none] [-g] [-f]
c-plugin skill add --local ./solo [-g] [-f]
c-plugin skill remove [--plugin demo ...] [--skill demo/alpha ...] [--skill solo ...] [-g]
c-plugin skill sync [-g] [-r]
c-plugin skill target add PATH [-g]
c-plugin skill target remove [--target PATH ...] [-g]
```

| Command | Behavior |
| --- | --- |
| `init` | Create an empty version-3 lock exclusively. Reject an existing path without overwriting it. |
| `plugin add` | Load one explicit plugin root, set its enabled skills, save a changed lock, and reconcile links. |
| `skill add` | Register one explicit skill directory containing `SKILL.md`, without requiring `plugin.json`, and reconcile links. |
| `skill remove` | Remove whole plugins, qualified plugin skills, or standalone skills, then reconcile owned links. |
| `skill sync` | Reconcile links from the existing lock without changing selections. |
| `skill target add` | Register an additional relative target and reconcile links. An already registered target is a no-op. |
| `skill target remove` | Remove selected target registrations and their unchanged owned links. Unknown targets are a no-op. |

Both add commands accept one directory, not a parent to scan or a list of roots.
There is no collection discovery, recursive source search, or bulk `--plugins` or `--skills` option.
Remote installation is not provided.

For `plugin add`, repeat `--skill` to enable specific skill names, use `--all` to enable all valid skills, or use `--none` to disable all skills while retaining the plugin registration.
These choices are mutually exclusive.
Adding the same plugin source and identity replaces its enabled skill set.
An unchanged set is a no-op and does not synchronize or rewrite state.
A different source with an existing plugin identity, or an existing source with a different identity, is an error.

`skill add` requires only the explicit source path, with no skill-selection prompt.
Its name comes from the validated `SKILL.md` frontmatter and must agree with the directory name.
Adding the same standalone name and source is a no-op.
A standalone name cannot refer to two sources or collide with an enabled plugin skill.

Removal uses `--plugin demo` for a whole plugin, `--skill demo/alpha` for a plugin skill, and `--skill solo` for a standalone skill.
A remove request that contains an unknown selector is a no-op for the entire request.
`--skill`, `--plugin`, and `--target` selectors can be repeated where shown.
`-g` means `--global`, `-r` means `--recursive`, and `-f` means `--force`.
Global and recursive mode cannot be combined.

## Interactive selection

When stdin and stderr support terminal interaction, commands with no explicit selectors show a numbered list:

| Command | Choices |
| --- | --- |
| `plugin add --local ./plugin` | Available skills in that plugin, with enabled entries marked |
| `skill remove` | Installed plugins, enabled plugin skills, and standalone skills |
| `skill target remove` | Registered additional targets, excluding the primary target |

Enter one or more 1-based numbers separated by spaces or commas, or enter `all`.
For plugin configuration, the selected set replaces the enabled set rather than adding to it.
Enter `none` to configure a plugin with no enabled skills.
For removal, `none` removes nothing.
Invalid text, duplicate numbers, and out-of-range numbers produce an error message and another prompt before any write.
An empty line, `q`, `cancel`, or end-of-input cancels without changing the lock, ownership state, or links.
Ctrl-C interrupts the process before selection and does not save a candidate.
No entries are implicitly selected for removal.

The interface uses line input, not arrow-key navigation or a full-screen terminal UI.
Prompts use stderr; command results use stdout.
Use explicit selectors when stderr is redirected.

Iris supplies the global `--no-input` option and terminal-input detection.
Place `--no-input` before the subcommand:

```sh
c-plugin --no-input plugin add --local ./plugin --all
c-plugin --no-input plugin add --local ./plugin --none
c-plugin --no-input skill add --local ./solo
c-plugin --no-input skill remove --skill solo
c-plugin --no-input skill target remove --target extra-skills
```

Non-terminal input and `--no-input` disable prompts.
In that mode, plugin add requires `--skill`, `--all`, or `--none`, remove requires `--plugin` or `--skill`, and target removal requires `--target`.
Missing selectors fail without changing configuration; pipe input is not interpreted as a selection.
Explicit options bypass the prompt in both terminal and script execution.

## Scope and paths

| Scope | Lock | Default skill root | Ownership state |
| --- | --- | --- | --- |
| Project | Nearest ancestor `c-plugin-lock.json`, with `HOME` as the search boundary | `<lock-root>/.agents/skills` | `<lock-root>/.agents/c-plugin-state.json` |
| Global (`-g`) | `$HOME/c-plugin-lock.json` | `$HOME/.agents/skills` | `$HOME/.agents/c-plugin-state.json` |

Project `init` uses the current directory.
Other project commands require an existing lock.
Local sources and additional targets are relative to the discovered lock root, not the command's working directory.
Local source arguments must begin with `./`.
Parent traversal and physical containment escapes are rejected.
Additional target roots must remain inside that lock root.

`skill sync -r` starts at the nearest project lock root and includes descendant locks.
It skips `.git`, applies supported `.gitignore` patterns, and does not traverse symlink directories.
It is not a complete Git ignore engine.

## Plugin and standalone inputs

`plugin add` requires `plugin.json` directly in the supplied root, with the canonical Agent Plugins 1.0 schema identifier and a valid name.
The [standard manifest](https://agent-plugins.org/specification#5-manifest) does not declare a skill list.
The standard fixes plugin skills at immediate child directories of `skills/`, each with a regular `SKILL.md` and valid Agent Skills frontmatter.
Invalid plugin skills are reported and skipped; an explicitly selected invalid or missing skill fails configuration.
No nested skill discovery or vendor fallback is provided.

`skill add` requires a regular `SKILL.md` directly in the supplied directory.
It validates the same frontmatter and containment rules, but does not load a plugin manifest or search for skills below that path.
An invalid standalone skill fails instead of registering an empty item.

Manifest validation uses local rules, not network schema retrieval.
MCP, hooks, and extension content are not installed or executed.
This product supports the skills subset and does not claim a complete conformance certification.

## Lock format

```json
{
  "version": "3",
  "targets": ["extra-skills"],
  "plugins": [
    {"source": "./plugin", "name": "demo", "skills": ["alpha"]}
  ],
  "skills": [
    {"source": "./solo", "name": "solo"}
  ]
}
```

The optional top-level `skills` array stores standalone skills.
It is omitted from canonical output when empty; existing version-3 locks without it remain valid.
Plugin and standalone sources are stored in normalized relative form with the `./` prefix.
Additional targets use normalized relative paths.
Version must be the exact string `"3"`.
Invalid types, identities, duplicate entries, and unsupported versions are errors.
There is no conversion from version 2 or other versions.
Do not delete an existing lock to work around an error unless you intend to replace its configuration.

## Collisions and recovery

By default, c-plugin preserves unowned files, directories, and symlinks, even when a symlink already points to the desired skill.
Explicit add `-f` can replace an exact contained regular file or symlink collision.
It cannot delete a real directory or a neighboring path.

Cleanup requires a valid ownership record, physical containment, and the exact recorded literal symlink target and resolved destination.
A replaced path or a path without proven ownership is preserved.
Missing or corrupt ownership state does not authorize deletion or automatic adoption.

A changed lock is saved before reconciliation.
Ordinary collisions and unavailable sources produce a partial result while preserving unaffected paths.
Unavailable plugin or standalone sources retain their owned links rather than authorizing cleanup.
A terminal checkpoint, durability, or verification failure stops reconciliation and fails the command.
The saved lock remains the desired state.
After fixing the reported cause, run `c-plugin skill sync` in the same scope.
Each filesystem mutation has an ownership checkpoint.
A crash between a mutation and its checkpoint can leave an unowned link. Automatic adoption is not guaranteed.
