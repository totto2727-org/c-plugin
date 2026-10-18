# CLI reference

This reference is for users who already have the CLI and a local plugin or skill directory.
See [README.md](../README.md) for setup and a minimal example.

## Commands

```text
c-plugin init [-g]
c-plugin list [-g]
c-plugin plugin add local:./plugin [--skill alpha ... | --all | --none] [-g] [-f]
c-plugin plugin list [-g]
c-plugin plugin remove [--plugin demo ...] [-g]
c-plugin plugin skill enable [PLUGIN] [--skill alpha ... | --all] [-g]
c-plugin plugin skill disable [PLUGIN] [--skill alpha ... | --all] [-g]
c-plugin skill add local:./solo [-g] [-f]
c-plugin skill list [-g]
c-plugin skill remove [--skill demo/alpha ...] [--skill solo ...] [-g]
c-plugin sync [-g] [-r]
c-plugin update [-g] [-r]
c-plugin plugin add github:OWNER/REPO[/PATH] [--ref REF] [--skill alpha ... | --all | --none] [-g] [-f]
c-plugin skill add github:OWNER/REPO[/PATH] [--ref REF] [-g] [-f]
c-plugin target add PATH [-g]
c-plugin target remove [--target PATH ...] [-g]
```

| Command | Behavior |
| --- | --- |
| `init` | Create an empty lock exclusively. Reject an existing path without overwriting it. |
| `list` | Show registered plugins and enabled plugin or standalone skills without changing state. |
| `plugin add` | Load one explicit plugin root, set its enabled skills, save a changed lock, and reconcile links. |
| `plugin list` | Show registered plugins, their sources, and their enabled skill sets, including disabled plugins. |
| `plugin remove` | Remove selected plugin registrations and reconcile their owned skill links. |
| `plugin skill enable` | Add selected available skills to a registered plugin's enabled set and reconcile links. |
| `plugin skill disable` | Remove selected skills from that enabled set and reconcile links, keeping the plugin registered. |
| `skill add` | Register one explicit skill directory containing `SKILL.md`, without requiring `plugin.json`, and reconcile links. |
| `skill list` | Show enabled plugin skills and registered standalone skills with their owner and source. |
| `skill remove` | Disable qualified plugin skills or remove standalone registrations, then reconcile owned links. |
| `sync` | Reconcile plugin and standalone links from pinned sources without network access or changing selections. |
| `update` | Refresh all GitHub plugin and standalone sources at their requested refs, validate the complete candidate, then reconcile links. |
| `target add` | Register an additional relative target and reconcile links. An already registered target is a no-op. |
| `target remove` | Remove selected target registrations and their unchanged owned links. Unknown targets are a no-op. |

Both add commands accept one directory, not a parent to scan or a list of roots.
There is no collection discovery, recursive source search, or bulk `--plugins` or `--skills` option.
Supply exactly one positional `SOURCE`: `local:./PATH` or `github:OWNER/REPO[/PATH]`.
The prefixes are mandatory; raw paths, raw repository names, unknown prefixes, and retired `--local`, `--github`, or `--path` options are errors.
`github:https://github.com/OWNER/REPO[/PATH]` is also accepted, with an optional `.git` suffix on the repository component.
Other hosts, URL credentials, queries, fragments, and traversal components are rejected.
`--ref` accepts a branch, tag, or commit; omission requests remote HEAD.
`--ref` with a local source is an error.
The path suffix identifies one explicit directory within the repository; `github:OWNER/REPO` means that repository's root.
GitHub `tree/BRANCH` URLs are not interpreted: path components are literal directories, never inferred refs.
There is no source-kind inference, collection scan, alternative directory fallback, or custom completion.
Missing required source data, incompatible options, and missing source manifests or markers fail before configuration changes.
Local paths resolve against the owning lock root; GitHub path suffixes resolve within the fetched snapshot.
GitHub transport uses libgit2 without a Git executable or subprocess fallback.
Non-Nix builds require libgit2 development headers and pkg-config; the Nix environment provides them.
Installed Git credential helpers are not supported, so private-repository authentication is unavailable.
Cancellation is cooperative and can wait for DNS or TLS operations between transport callbacks.

```sh
c-plugin plugin add github:totto2727-org/agent/plugins/totto2727-coding --all
c-plugin skill add github:totto2727-org/agent/plugins/totto2727-coding/skills/share-coding
c-plugin sync
c-plugin update
```

Do not install a standalone skill with the same name as an enabled plugin skill.
GitHub sources are pinned to a full commit in the lock, with an immutable snapshot under `.agents/c-plugin/sources/OWNER/REPO/COMMIT/tree`.
`sync` verifies the pinned cache offline; it does not fetch missing snapshots or update branches.
Unavailable or modified caches produce a partial sync and preserve trusted source ownership.
`update` refreshes both plugin and standalone registrations before saving a validated per-lock candidate.
A failed refresh leaves that lock unchanged.
An unchanged successful update still synchronizes links, but does not rewrite the lock.
Re-adding the same repository, requested ref, and subpath can refresh the source and replace the plugin enabled set.
Changing that source identity under an installed name is a conflict.
Cancellation may leave a fetched cache snapshot, but does not save configuration or alter skill links.
Cache garbage collection, submodules, and non-GitHub remotes are not supported.

For `plugin add`, repeat `--skill` to enable specific skill names, use `--all` to enable all valid skills, or use `--none` to disable all skills while retaining the plugin registration.
These choices are mutually exclusive.
Adding the same plugin source and identity replaces its enabled skill set.
An unchanged set is a no-op and does not synchronize or rewrite state.
A different source with an existing plugin identity, or an existing source with a different identity, is an error.

`skill add` requires only the explicit source path, with no skill-selection prompt.
Its name comes from the validated `SKILL.md` frontmatter and must agree with the directory name.
Adding the same standalone name and source is a no-op.
A standalone name cannot refer to two sources or collide with an enabled plugin skill.

Use `plugin remove --plugin demo` for a whole plugin.
Use `skill remove --skill demo/alpha` for a plugin skill and `skill remove --skill solo` for a standalone skill.
Removing a plugin's last enabled skill keeps its registration with an empty enabled set.
A remove request that contains an unknown selector is a no-op for the entire request.
`--skill`, `--plugin`, and `--target` selectors can be repeated where shown.
`-g` means `--global`, `-r` means `--recursive`, and `-f` means `--force`.
Global and recursive mode cannot be combined.
`sync -r` and `update -r` first find the nearest regular project lock between the working directory and HOME, then process that lock and descendant project locks in deterministic order.
A missing nearest lock is an error even when descendant locks exist.
Unignored hidden directories are included; symlink directories are never followed.
Ignore behavior preserves the original Admiral 0.6.2 discovery library's limited directory-pattern rules, not full Git ignore semantics: whitespace is trimmed, leading/trailing slashes are removed, `*` matches within one path segment, multi-segment patterns can match contiguous segments, and comments and negation lines are ignored.
Ignore rules prune directory traversal only; a discovered directory's own lock is included even if a rule names `c-plugin-lock.json`.
As safety exclusions, `.git` and implementation-owned `.agents/c-plugin/sources` snapshots are not traversed.
Each lock remains an independent persistence and reconciliation boundary.

Missing commands, required arguments, and option values keep the standard parser error and nonzero exit status, followed by the complete help for that command context.
`--help` itself exits successfully.

## Lists

```sh
c-plugin list
c-plugin plugin list
c-plugin skill list
c-plugin list -g
```

`list` prints both plugin and skill sections.
`plugin list` includes registrations with no enabled skills.
`skill list` includes enabled plugin skills and standalone registrations, with each skill's owner.
Sections use headings and tab-separated columns in deterministic order.
An empty section still prints its heading and column names.
Sources use `local:./PATH` or `github:OWNER/REPO[/PATH]@COMMIT`, not internal cache paths.
These commands read only the selected lock.
They do not fetch sources, verify or repair links, save state, or synchronize.
Unavailable sources and missing links do not prevent listing valid registrations.
A missing or invalid lock is an error, not an empty list or implicit initialization.

## Registered plugin skills

```sh
c-plugin plugin skill disable demo --skill alpha
c-plugin plugin skill enable demo --skill alpha
c-plugin plugin skill disable demo --all
c-plugin plugin skill enable demo --all
```

These commands require an existing plugin registration and a valid available source.
They control the selected plugin only and preserve its identity, source, and pinned GitHub commit.
They do not fetch or refresh a GitHub source.
Enable adds selected names to the enabled set; disable removes selected names.
Disabling every skill keeps the plugin registered with an empty enabled set.
An unknown plugin, unavailable source, unknown skill, or enabled-name collision fails before state changes.
`--skill` and `--all` are mutually exclusive.
Without either option, a terminal offers skill selection.
When `PLUGIN` is omitted, select one registered plugin first, then select its skills.
The explicit source operand for `plugin add` remains required.
Cancellation and an unchanged enabled set do not save or synchronize.
Use `plugin remove` to unregister the plugin itself.

## Interactive selection

When stdin and stderr support terminal interaction, commands with no explicit selectors show a keyboard-operated list:

| Command | Choices |
| --- | --- |
| `plugin add local:./plugin` | Available skills in that plugin, with enabled entries marked |
| `plugin remove` | Registered plugins only |
| `skill remove` | Enabled plugin skills and standalone skills only |
| `plugin skill enable [PLUGIN]` | One registered plugin if omitted, then valid skills in that plugin |
| `plugin skill disable [PLUGIN]` | One registered plugin if omitted, then valid skills in that plugin |
| `target remove` | Registered additional targets, excluding the primary target |

Use Up/Down to move and Space to toggle the focused item.
Press `a` to select all items or `n` to clear the selection.
Press Enter to confirm the selected set. No items are selected initially.
For `plugin add`, the selected set replaces the enabled set rather than adding to it.
For `plugin skill enable` and `disable`, it adds or removes only the selected skills.
For `plugin add`, confirming an empty selection configures the plugin with no enabled skills.
For `plugin skill enable`, `plugin skill disable`, and removal, confirming an empty selection makes no changes.
If a command requires exactly one plugin, selecting more than one repeats the plugin prompt before any write.
Esc, `q`, or Ctrl-D cancels without changing the lock, ownership state, or links.
Ctrl-C interrupts the process and does not save a candidate.
No entries are implicitly selected for removal.

The selection interface uses Brick and restores the terminal on completion, cancellation, or interruption.
The selection screen uses stderr; command results use stdout.
Use explicit selectors when stderr is redirected.

Iris supplies the global `--no-input` option and terminal-input detection.
Place `--no-input` before the subcommand:

```sh
c-plugin --no-input plugin add local:./plugin --all
c-plugin --no-input plugin add local:./plugin --none
c-plugin --no-input skill add local:./solo
c-plugin --no-input skill remove --skill solo
c-plugin --no-input plugin remove --plugin demo
c-plugin --no-input plugin skill enable demo --skill alpha
c-plugin --no-input plugin skill disable demo --all
c-plugin --no-input target remove --target extra-skills
```

Non-terminal input and `--no-input` disable prompts.
In that mode, plugin add requires `--skill`, `--all`, or `--none`.
Plugin skill enable and disable require a plugin name and `--skill` or `--all`.
Plugin removal requires `--plugin`, skill removal requires `--skill`, and target removal requires `--target`.
Missing selectors fail without changing configuration; pipe input is not interpreted as a selection.
Explicit skill options bypass skill selection, but an omitted plugin name still requires terminal plugin selection.

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

`sync -r` starts at the nearest project lock root and includes descendant locks.
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
  "targets": ["extra-skills"],
  "plugins": {
    "demo": {"pluginName": "demo", "pluginSource": "plugin", "enabledSkills": ["alpha"], "pluginOrigin": null}
  },
  "standaloneSkills": {
    "solo": {"installedSkillName": "solo", "installedSkillSource": "solo", "installedSkillOrigin": null}
  }
}
```

Internal JSON uses Aeson's default derived representation of the Haskell types: record field names stay unchanged, maps are objects, and absent origins are `null`.
The `plugins` and `standaloneSkills` maps use the registered name as the key.
Each key must match the name in its record.
Plugin and standalone sources are stored as normalized relative paths without adding the CLI's `local:` or `./` prefix.
Additional targets use normalized relative paths.
Decoded data is validated before filesystem use; invalid paths, identities, duplicate selections, and conflicting registrations are errors.
Legacy lock, ownership, and cache-provenance shapes are not converted or used as fallback formats.
External `plugin.json` and `SKILL.md` retain their standard schema and frontmatter formats.
Do not delete an existing lock to work around an error unless you intend to replace its configuration.

## Collisions and recovery

By default, c-plugin preserves unowned files, directories, and symlinks, even when a symlink already points to the desired skill.
Explicit add `-f` can replace an exact contained regular file or symlink collision.
This permission covers only the skills selected by that add operation, across the default and additional targets, not other registered plugins or standalone skills.
It cannot delete a real directory or a neighboring path.

Cleanup requires a valid ownership record, physical containment, and the exact recorded literal symlink target and resolved destination.
A replaced path or a path without proven ownership is preserved.
Missing or corrupt ownership state does not authorize deletion or automatic adoption.

A changed lock is saved before reconciliation.
Ordinary collisions and unavailable sources produce a partial result while preserving unaffected paths.
Unavailable plugin or standalone sources retain their owned links rather than authorizing cleanup.
A terminal checkpoint, durability, or verification failure stops reconciliation and fails the command.
The saved lock remains the desired state.
After fixing the reported cause, run `c-plugin sync` in the same scope.
Each filesystem mutation has an ownership checkpoint.
A crash between a mutation and its checkpoint can leave an unowned link. Automatic adoption is not guaranteed.
