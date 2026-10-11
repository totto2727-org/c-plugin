# Git transport decision

## Decision

Use the standard Haskell `process` package to invoke Git with explicit argv, rather than adding `gitlib` for the current GitHub snapshot installer.
Keep repository, ref, subpath, commit, origin, validation, and JSON conversion in `CPlugin.Types.GitHub`.
Keep transport and cache effects in `CPlugin.Source.GitHub`.
Git is an explicit runtime dependency for Cabal builds and is included in the Nix package wrapper.

## Alternatives examined

The upstream [gitlib repository](https://github.com/jwiegley/gitlib/tree/master/gitlib) provides typed Git objects and repository abstractions with interchangeable backends.
Its published [gitlib 3.1.3 metadata](https://hackage.haskell.org/package/gitlib-3.1.3) permits `base >= 3 && < 5`.
That bound does not establish a GHC 9.4 incompatibility, and no such incompatibility is claimed here.

The [gitlib-cmdline backend source](https://github.com/jwiegley/gitlib/blob/master/gitlib-cmdline/Git/CmdLine.hs) implements `doRunGit` through Shelly and the Git executable.
Its pull helper runs a merging `git pull` and changes repository user configuration, rather than implementing this installer's immutable pinned fetch.
The lower-level command wrapper still needs a product-specific layer for environment isolation, hook disabling, fixed-URL verification, and cache provenance.
Using that backend would retain the Git runtime dependency while adding a broader object/monad and dependency surface.

The published [gitlib-libgit2 dependency declaration](https://hackage.haskell.org/package/gitlib-libgit2-3.1.2.1) adds `hlibgit2` and `text-icu` native bindings.
That introduces additional native-library and static Linux packaging boundaries for operations that the existing Git executable already supplies.
This is a scope and maintenance decision, not a claim that those libraries cannot work.

The upstream [Git.Repository helpers](https://github.com/jwiegley/gitlib/blob/master/gitlib/Git/Repository.hs) also include `withNewRepository`, which removes an existing supplied directory.
Do not apply that helper to persistent cache locations or user directories.
The product instead creates unique staging directories and never replaces or deletes an existing cache entry.

## Required behavior

The product runner uses argv, never a shell command assembled from source inputs.
It accepts only fixed GitHub HTTPS repositories and validated refs/subpaths, uses normal installed Git credentials without prompts, disables hooks and submodule recursion, and rejects URL rewriting.
Offline synchronization verifies the locked commit and cache provenance without contacting the remote.
An explicit update fetches the configured refs for both plugins and standalone skills, validates the complete per-lock candidate, and then synchronizes links.
A snapshot containing submodules is rejected rather than recursively fetching another repository.
The CLI's `-r` means recursive project-lock discovery, not Git clone recursion and not a shorthand for `--ref`.

## Discovery compatibility

The original implementation delegates recursive discovery to Admiral 0.6.2's `target-file-discovery` utility.
The current [lock discovery implementation](../../hs/lib/CPlugin/Paths.hs) preserves that discovery contract.
Preserve its nearest-parent requirement, directory-only ignore matching, included own lock, hidden-directory behavior, and refusal to traverse symlink directories.
The limited ignore matcher is not a full implementation of Git ignore semantics.
Prune `.git` metadata and installer-owned source snapshots as explicit safety exclusions, so source repositories cannot become projects during recursive update or sync.
The [CLI reference](../cli.md) defines these externally visible rules.
