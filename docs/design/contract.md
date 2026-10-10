# Design contract

This contract is for contributors who change c-plugin.
The [CLI reference](../cli.md) owns user-facing command details.
The [Japanese translation](contract.ja.md) has the same scope and requirements.

## Scope

c-plugin is a local, skills-only installer for the Agent Plugins 1.0 package format.
It uses Haskell, Cabal, Iris, and a pinned Nix environment.
It does not manage marketplaces, vendor-specific packages, Git remotes, MCP servers, hooks, or interactive selection.
Do not treat those exclusions as future command placeholders.

## Input boundaries

Use validated path and identity values after parsing CLI strings, JSON, and filesystem input.
Resolve local sources and additional targets against the owning lock root.
Reject parent traversal and physical containment escapes.
Output roots and their ancestors must be physical directories inside the lock root, not symlink redirects.

Apply the locally supported Agent Plugins 1.0 manifest rules:

- Require `plugin.json` at the plugin root and the exact supported `$schema` identifier.
- Validate required names and permitted metadata types. Do not add URL, email, SPDX, or semantic-version constraints where the specification requires only strings.
- Report and ignore unknown top-level manifest fields.
- Treat a non-object `extensions` field as a non-fatal ignored field.
- Reject other manifest violations before discovering skills.
- Do not retrieve schemas at runtime or fall back to vendor formats.

Discover skills only from immediate child directories of `skills/`.
Each `SKILL.md` must resolve to a regular file within the resolved plugin root.
Validate its frontmatter against the Agent Skills format, including directory/name agreement.
Report invalid skills and skip them without disabling valid siblings.
Reject an explicitly selected unavailable skill.
Ignore unsupported component types without executing their content.
This contract does not establish a complete conformance certification.

## State

The desired lock is `c-plugin-lock.json`:

```json
{
  "version": "3",
  "targets": [],
  "plugins": [
    {"source": "./demo", "name": "demo", "skills": ["alpha"]}
  ]
}
```

Require the exact string version `"3"` and all required fields.
Reject unsupported versions without conversion or mutation.
Reject duplicate sources, plugin identities, selected skills, and target entries.
Encode normalized relative paths and deterministic ordering.
Keep project and global locks independent.

Machine-local ownership state is `.agents/c-plugin-state.json`, with version `"1"`.
It is not portable desired configuration.
Each entry records the absolute link path, managed root, exact literal symlink target, resolved target, and source/plugin/skill identity.
The literal target must round-trip unchanged, separately from the resolved path.

## Persistence and reconciliation

`init` creates a new lock exclusively and does not synchronize links.
For a changed existing lock:

1. Resolve and validate the complete candidate.
2. Save the lock through a temporary sibling file and atomic rename.
3. Reconcile exactly that persisted candidate.

Rejected candidates and semantic no-ops do not rewrite the lock or trigger reconciliation.
Ordinary collisions and unavailable plugins can produce partial success.
A terminal checkpoint, durability, or verification failure returns failure without pretending that the lock was rolled back.
A later sync can retry the persisted desired state.

For each link mutation:

1. Check physical containment and ownership or explicit force eligibility.
2. Perform only the exact authorized mutation.
3. Verify a new link before recording ownership.
4. Save an ownership checkpoint before the next mutation.

Stop on checkpoint failure.
Atomic replacement does not eliminate the crash window between a filesystem mutation and its ownership checkpoint.
Do not promise automatic recovery or ownership adoption across that window.

## Safety rules

- Delete or replace an owned link only when its filesystem kind, literal target, resolved target, and containment still match its record.
- Preserve replaced paths and report ownership loss.
- Missing or corrupt ownership state never authorizes cleanup or adoption of existing paths.
- Do not adopt an existing unrecorded link merely because it points to the desired destination.
- Explicit add force may replace only the exact contained regular file or symlink collision.
- Never delete a real directory, special file, neighboring path, or path outside a managed root.
- Keep stale owned entries for removed target roots available for safe cleanup.
- Preserve links for unavailable plugin sources rather than deleting them because resolution failed.
- Keep recursive lock ownership isolated and do not follow symlink directories during discovery.

These checks reduce accidental scope escape. They are not a sandbox against a concurrent hostile filesystem writer.

## Implementation boundaries

| File/module | Responsibility |
| --- | --- |
| `app/Main.hs` | Iris command parser and process entrypoint |
| `CPlugin.Types` | Validated paths, identities, locks, and ownership values |
| `CPlugin.Codec` | Strict codecs and atomic state persistence |
| `CPlugin.Paths` | Runtime scopes, discovery, and physical containment checks |
| `CPlugin.Plugin` | Standard manifest and skill discovery/validation |
| `CPlugin.Reconcile` | Desired links, ownership-safe mutations, and checkpoints |
| `CPlugin.Commands` | Init, add, remove, sync, and target workflows |

Keep GHC 9.4.8 and Iris 0.1 within their published dependency bounds.
Do not substitute dependency probes for product tests.

## Validation

Native tests must use isolated temporary roots and exercise real product boundaries.
Go/Testcontainers scenarios must use a caller-built image and one disposable container per registered case.
Check source-linked scenario documents against the real Go directory.
Report native tests, real Docker E2E, and Nix package builds as separate results.
Documentation examples describe expected behavior, not evidence that a test passed.

## Sources

- [Agent Plugins 1.0 specification](https://agent-plugins.org/specification)
- [Plugin manifest schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json)
- [Agent Skills specification](https://agentskills.io/specification)
- [Iris package](https://hackage.haskell.org/package/iris)
