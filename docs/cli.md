# CLI reference

This reference is for users who already have the CLI and a local plugin.
See [README.md](../README.md) for setup and a minimal plugin example.

## Commands

```text
c-plugin init [-g]
c-plugin skill add --local ./plugin [--skill alpha ...] [-g] [-f]
c-plugin skill remove [--plugin demo ...] [--skill demo/alpha ...] [-g]
c-plugin skill sync [-g] [-r]
c-plugin skill target add PATH [-g]
c-plugin skill target remove [--target PATH ...] [-g]
```

| Command | Behavior |
| --- | --- |
| `init` | Create an empty version-3 lock exclusively. Reject an existing path without overwriting it. |
| `skill add` | Validate a local plugin, register selected skills, save the lock, and reconcile links. Without `--skill`, select all valid skills. |
| `skill remove` | Remove selected plugin names or `plugin/skill` pairs, save a changed lock, and reconcile owned links. |
| `skill sync` | Reconcile links from the existing lock without changing skill selections. |
| `skill target add` | Register an additional relative target and reconcile links. An already registered target is a no-op. |
| `skill target remove` | Remove selected target registrations and their unchanged owned links. Unknown targets are a no-op. |

`--skill`, `--plugin`, and `--target` selectors can be repeated where shown.
Remove with no selection is a no-op, not an implicit remove-all operation.
A remove request that contains an unknown selector is a no-op for the entire request.
Repeated local source, plugin name, or enabled skill entries are rejected rather than merged.
`-g` means `--global`, `-r` means `--recursive`, and `-f` means `--force`.
Global and recursive mode cannot be combined.
There is no interactive selection or remote installation command.

## Scope and paths

| Scope | Lock | Default skill root | Ownership state |
| --- | --- | --- | --- |
| Project | Nearest ancestor `c-plugin-lock.json`, with `HOME` as the search boundary | `<lock-root>/.agents/skills` | `<lock-root>/.agents/c-plugin-state.json` |
| Global (`-g`) | `$HOME/c-plugin-lock.json` | `$HOME/.agents/skills` | `$HOME/.agents/c-plugin-state.json` |

Project `init` uses the current directory.
Other project commands require an existing lock.
Local plugin sources and additional targets are relative to the discovered lock root, not the command's working directory.
Parent traversal and paths that escape physical containment are rejected.
Additional target roots must remain inside that lock root.

`skill sync -r` starts at the nearest project lock root and includes descendant locks.
It skips `.git`, applies supported `.gitignore` patterns, and does not traverse symlink directories.
It is not a complete Git ignore engine.

## Plugin inputs

The plugin root must contain `plugin.json` with the canonical Agent Plugins 1.0 schema identifier and a valid name.
Skills are immediate children of `skills/` with a regular `SKILL.md` and valid Agent Skills frontmatter.
Invalid skills are reported and skipped. An explicitly selected missing or invalid skill fails add.
No nested skill discovery or vendor fallback is provided.
Manifest schema validation uses local rules, not network schema retrieval.
MCP, hooks, and extension content are not installed or executed.
This product supports the skills subset and does not claim a complete conformance certification.

## Lock format

```json
{
  "version": "3",
  "targets": ["extra-skills"],
  "plugins": [
    {
      "source": "./demo",
      "name": "demo",
      "skills": ["alpha"]
    }
  ]
}
```

Plugin sources must begin with `./` and are stored in normalized relative form with that prefix.
Additional targets use normalized relative paths.
Version must be the exact string `"3"`.
Missing fields, invalid types, invalid identities, duplicate entries, and unsupported versions are errors.
There is no conversion from version 2 or other versions.
Do not delete an existing lock to work around an error unless you intend to replace its configuration.

## Collisions and recovery

By default, c-plugin preserves unowned files, directories, and symlinks, even when a symlink already points to the desired skill.
Only `skill add -f` can replace an exact contained regular file or symlink collision.
It cannot delete a real directory or a neighboring path.

Cleanup requires a valid ownership record, physical containment, and the exact recorded literal symlink target and resolved destination.
A replaced path or a path without proven ownership is preserved.
Missing or corrupt ownership state does not authorize deletion or automatic adoption.

A changed lock is saved before reconciliation.
Ordinary collisions and unavailable plugins produce a partial result while preserving unaffected paths.
A terminal checkpoint, durability, or verification failure stops reconciliation and fails the command.
The saved lock remains the desired state.
After fixing the reported cause, run `c-plugin skill sync` in the same scope.
Each filesystem mutation has an ownership checkpoint.
A crash between a mutation and its checkpoint can leave an unowned link. Automatic adoption is not guaranteed.
