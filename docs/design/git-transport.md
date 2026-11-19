# Git transport decision

This document is for contributors who change GitHub transport, cache validation, or packaging.
For source syntax and user-facing behavior, see the [CLI reference](../cli.md).

## Decision

Use the official gitlib and gitlib-cmdline packages for all default GitHub commands.
Both packages use version 3.3.0 from unchanged upstream commit [`25dcef2e4f09e571f71c795f5b32267038258cea`](https://github.com/jwiegley/gitlib/commit/25dcef2e4f09e571f71c795f5b32267038258cea), dated 2026-08-08.
Pin that revision through Cabal `source-repository-package` and matching Nix overrides.
Do not patch upstream source or introduce custom C, FFI, or bindings.

`CPlugin.Source.Gitlib.runGitlib` is a small adapter to upstream `Git.CmdLine.doRunGit`, `CliRepo`, and `RepositoryOptions`.
Its execution callback uses standard `process` functions with explicit arguments, environment, and working directory.
The adapter preserves output and cancellation cleanup without constructing shell commands.
The Git executable performs fetch, checkout, status, `fsck`, and other Git operations.
This is a subprocess backend, not a replacement Git implementation or an implementation of every operation through high-level typed Git objects.
The exported `CPlugin.Source.GitHub.runGit` uses the same backend for injected tests and fixtures.

Keep repository, ref, subpath, commit, origin, validation, and JSON conversion in `CPlugin.Types.GitHub`.
Keep staging, cache validation, and transport orchestration in `CPlugin.Source.GitHub`.
Keep command execution in `CPlugin.Source.Gitlib`.

## Upstream APIs and backend boundaries

The pinned [gitlib package](https://github.com/jwiegley/gitlib/blob/25dcef2e4f09e571f71c795f5b32267038258cea/gitlib/gitlib.cabal) and [gitlib-cmdline package](https://github.com/jwiegley/gitlib/blob/25dcef2e4f09e571f71c795f5b32267038258cea/gitlib-cmdline/gitlib-cmdline.cabal) declare version 3.3.0.
Use the pinned [command-line backend](https://github.com/jwiegley/gitlib/blob/25dcef2e4f09e571f71c795f5b32267038258cea/gitlib-cmdline/Git/CmdLine.hs) rather than assuming that published gitlib-cmdline 3.1.0.2 has the same APIs and dependency compatibility.
Published [gitlib-cmdline 3.1.0.2](https://hackage.haskell.org/package/gitlib-cmdline-3.1.0.2/src/Git/CmdLine.hs) calls `textToSha` without the `MonadFail` constraint required by [gitlib 3.1.3](https://hackage.haskell.org/package/gitlib-3.1.3/src/Git/Types.hs).
It also uses `parseTime`, which is absent from the [time 1.12.2 formatting API](https://hackage.haskell.org/package/time-1.12.2/docs/Data-Time-Format.html).
The pinned upstream source adds the required `MonadFail` constraints and uses `parseTimeM False`.
These are specific compatibility gaps, not proof that every historical dependency plan fails.
`doRunGit` accepts an execution callback, so the product can preserve its environment and process-lifecycle policy without changing upstream code.
The backend also uses Shelly internally, but the product callback does not use `Shelly.run` for command execution.

Do not use upstream pull helpers for immutable source refreshes.
They perform a merging pull and can change repository user configuration.
The upstream [repository helpers](https://github.com/jwiegley/gitlib/blob/25dcef2e4f09e571f71c795f5b32267038258cea/gitlib/Git/Repository.hs) include `withNewRepository`, which removes an existing supplied directory.
Never apply that helper to persistent cache locations or user directories.
Use unique staging directories and never replace or delete an existing cache entry.

The separate [gitlib-libgit2 backend](https://github.com/jwiegley/gitlib/blob/25dcef2e4f09e571f71c795f5b32267038258cea/gitlib-libgit2/gitlib-libgit2.cabal) depends on hlibgit2.
The [hlibgit2 Cabal declaration at the same upstream revision](https://github.com/jwiegley/gitlib/blob/25dcef2e4f09e571f71c795f5b32267038258cea/hlibgit2/hlibgit2.cabal) still builds bundled libgit2 0.18 without a system-library switch or pkg-config integration.
Its [Setup.hs](https://github.com/jwiegley/gitlib/blob/25dcef2e4f09e571f71c795f5b32267038258cea/hlibgit2/Setup.hs) uses `defaultMain` and does not add such a switch.
It is not the selected backend.
A broad `base >= 3 && < 5` bound alone does not establish GHC 9.4 compatibility or incompatibility.

## Required behavior

The adapter accepts the installer's internal argument lists, not shell command strings.
Network operations accept only fixed HTTPS GitHub URLs and validated refs and subpaths, and request shallow depth one.
Network operations use installed Git configuration and credential helpers with interactive prompts disabled.
Do not add a product-specific authentication flow.
Reject URL rewriting and disable HTTP redirects, hooks, and submodule recursion.
Offline verification excludes global, system, and XDG configuration, rejects local configuration includes, and does not contact remotes.

Preserve validation of physical cache directories, origin URL, HEAD, provenance, metadata indirections, tracked content hashes, and contained tracked symlinks.
Do not adopt, overwrite, or delete an existing corrupt cache entry.
Cleanup is restricted to staging directories created by the current fetch.
An explicit update fetches configured refs for plugins and standalone skills, validates the complete per-lock candidate, and then synchronizes links.
Reject snapshots containing submodules rather than recursively fetching another repository.
The CLI's `-r` means recursive project-lock discovery, not Git clone recursion or a shorthand for `--ref`.

Keep the process-wide eight-slot leaf-effect gate, deterministic reporting order, and sequential mutation/checkpoint policy.
Cancellation must cancel and join dependent workers and clean up subprocesses before control returns.
These checks are not a sandbox against a concurrent hostile filesystem writer.

## Authentication and verification limits

Private repositories require installed credentials that work without prompts.
Credential availability, helper behavior, permissions, and network access remain external prerequisites.
Do not claim real private-repository acceptance from synthetic tests or without running against an authorized repository with working credentials.
Installed credential helpers are part of the selected backend's authentication path.

## Build and packaging

Git is a runtime dependency.
The Nix development shell includes Git, and the installed Nix package wraps the executable with Git on `PATH`.
Non-Nix builds require Git, not libgit2 development headers or custom binding code.
Root `package.yaml` and `e2e/package.yaml` are the hpack sources of truth.
Check in the generated `.cabal` files and let hpack discover module lists automatically.

The Docker sandbox-base builder runs an ordinary Cabal build inside `nix develop`, not `nix build`.
The Ubuntu 26.04 runtime copies only the actually linked Nix library closure, not the development toolchain.
Git supports product transport and fixtures, while Python supports test probes.
Keep the runtime lean and do not enable a Cabal `static` flag.
A dependency-heavy cold build is not inherently faster.
Make performance claims only from measurements.

## Discovery compatibility

The original implementation delegates recursive discovery to Admiral 0.6.2's `target-file-discovery` utility.
The current [lock discovery implementation](../../lib/CPlugin/Paths.hs) preserves that discovery contract.
Preserve its nearest-parent requirement, directory-only ignore matching, included own lock, hidden-directory behavior, and refusal to traverse symlink directories.
The limited ignore matcher is not a full implementation of Git ignore semantics.
Prune `.git` metadata and installer-owned source snapshots as explicit safety exclusions, so source repositories cannot become projects during recursive update or sync.
The [CLI reference](../cli.md) defines these externally visible rules.
