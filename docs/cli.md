# CLI reference

<!-- Temporary: this feature PR intentionally precedes complete command integration.
Remove this availability note in S17 after the bit adapter and all eight Go cases are integrated. -->
**Current feature stage: S6.**
Available CLI entrypoints: help/version.
Later-stage commands and their examples below are specifications, not executable claims for this checkout.
Registered Go/Testcontainers cases in this checkout: 0.

This reference describes the complete feature-stack contract. The [current CLI entrypoint](../src/main.mbt) exposes only the commands listed in the stage note above.
It is not an installation guide.
The public executable name is `c-plugin`.
No supported standalone release is asserted here.

## Capability status

| Capability | Complete feature-stack contract |
| --- | --- |
| Help/version, project/global init | Command wiring and tests exist |
| Local add, remove, sync, recursive sync | Explicit non-interactive commands exist |
| Additional target add/remove | Commands and isolated tests exist |
| Bit repository adapter | Typed adapter exists |
| GitHub add/update and cache lifecycle | Not implemented as leaf workflows; GitHub sync resolution reports unavailable |
| TTY selection and cancellation UI | Not implemented |
| Developer marketplace conversion | Not implemented |
| Automatic v1 lock conversion | Not provided |

This stage registers 0 Go cases. The complete S17 suite registers eight cases in seven files.
That is not complete coverage of every leaf in the broader design, and source presence is not test-pass evidence.

## Representative workflow

With the CLI and a local marketplace already available, a project can initialize a lock and select one local skill:

```bash
c-plugin init
c-plugin skill add --local ./marketplace --kind claude --skill demo/alpha
c-plugin skill sync
```

`init` creates `c-plugin-lock.json` containing the empty version-2 lock and prints `Created <absolute lock path>` followed by a newline.
A successful first local add persists the selected skill and synchronizes its link under `.agents/skills` when no collision prevents it.
Sync reconciles links without rewriting the lock.
See the [add scenario](../go/e2e/c-plugin/add_test.md) for exact fixture-dependent output, partial results, and force behavior.

## Command reference

| Command | Behavior |
| --- | --- |
| `c-plugin --help` / `c-plugin --version` | Discover the available parser tree and version in the installed CLI |
| `c-plugin init [-g]` | Create only a new project or exact-home lock; an existing lock is rejected without overwrite |
| `c-plugin skill add --local <./path> --kind <kind> --skill <plugin/skill>... [-g] [-f \| --force]` | Resolve the explicit local marketplace relative to the discovered lock scope, validate selections, persist once, and synchronize |
| `c-plugin skill remove [-g] [--skill <repository/plugin/skill>...]` | Remove explicit installed selections; empty, unknown, or repeated removals can be successful no-ops |
| `c-plugin skill sync [-g \| -r]` | Reconcile the selected lock or recursive project locks without changing pins or lock bytes |
| `c-plugin skill target add <path> [-g]` | Register and synchronize a normalized additional target; an already registered target is a no-op |
| `c-plugin skill target remove [-g] [--target <path>...]` | Remove additional target registrations and only safely owned links; never remove the primary target |

Use `c-plugin skill --help` and the relevant nested command's `--help` to inspect that installed parser rather than assuming the planned command tree is available.
Global and recursive flags are mutually exclusive.
The current local add workflow is explicit and non-interactive, not an automatic selection UI.

## Duplicate and failure behavior

A local add containing a duplicate repository, plugin, or skill identity is rejected at the domain boundary.
Repeating the same add is not an implicit no-op, union merge, or force-triggered sync-only operation.
The [accepted local-add contract](https://linear.app/totto2727/issue/TOT-121) requires duplicate rejection, and the [force contract](https://linear.app/totto2727/issue/TOT-157) changes eligible filesystem collision handling rather than that identity rule.
A rejected duplicate preserves the lock and existing managed state, as asserted by the product tests.
A broader idempotence goal is not an implemented guarantee and is tracked separately in [TOT-224](https://linear.app/totto2727/issue/TOT-224).

Errors before lock persistence preserve previous state.
If persistence succeeds but synchronization fails, the command reports failure rather than claiming success; the persisted desired state can be reconciled by a later sync.
Do not infer that every filesystem side effect is rolled back after persistence or a failed checkpoint.

## Safety constraints

Project locks are discovered from the nearest ancestor within the home boundary; global mode uses `~/c-plugin-lock.json` exactly.
Ownership is stored separately in `.agents/c-plugin-state.json` and is not portable desired configuration.
Default reconciliation preserves foreign files, directories, and unowned or unverifiable links.
Explicit add force may replace only an eligible regular file or symlink at the exact physically contained desired path.
It does not delete real directories, neighbors, or paths outside managed roots.
A pre-existing link is not automatically adopted merely because it resolves to the desired target.
Interrupted filesystem mutations do not guarantee ownership recovery across a failed or missing durability checkpoint.
See the [complete safety contract](./design/contract.md#symlink-ownership-state).
