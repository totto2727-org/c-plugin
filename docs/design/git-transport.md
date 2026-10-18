# Git transport decision

## Decision

Use `CPlugin.Source.Libgit2`, a small direct C FFI to nixpkgs libgit2 1.9.7, for all default commands.
There is no production Git subprocess fallback.
The exported `CPlugin.Source.GitHub.runGit` remains available only for injected tests and fixtures.
Keep repository, ref, subpath, commit, origin, validation, and JSON conversion in `CPlugin.Types.GitHub`.
Keep staging, cache validation, and transport orchestration in `CPlugin.Source.GitHub`, and native operations in `CPlugin.Source.Libgit2` and `cbits/libgit2.c`.

## Alternatives examined

The upstream [gitlib repository](https://github.com/jwiegley/gitlib/tree/master/gitlib) provides typed Git objects and repository abstractions with interchangeable backends.
Its published [gitlib 3.1.3 metadata](https://hackage.haskell.org/package/gitlib-3.1.3) permits `base >= 3 && < 5`.
That bound does not establish a GHC 9.4 incompatibility, and no such incompatibility is claimed here.

The [gitlib-cmdline backend source](https://github.com/jwiegley/gitlib/blob/master/gitlib-cmdline/Git/CmdLine.hs) implements `doRunGit` through Shelly and the Git executable.
Its pull helper runs a merging `git pull` and changes repository user configuration, rather than implementing this installer's immutable pinned fetch.
The lower-level command wrapper still needs a product-specific layer for environment isolation, hook disabling, fixed-URL verification, and cache provenance.
Using that backend would retain the Git runtime dependency while adding a broader object/monad and dependency surface.

The published [gitlib-libgit2 dependency declaration](https://hackage.haskell.org/package/gitlib-libgit2-3.1.2.1) adds `hlibgit2` and `text-icu` native bindings.
Published [hlibgit2 0.18.0.16 metadata](https://hackage.haskell.org/package/hlibgit2-0.18.0.16) and its [Cabal source](https://hackage.haskell.org/package/hlibgit2-0.18.0.16/hlibgit2.cabal) show that it unconditionally builds an old bundled libgit2, without a system-library flag or pkg-config integration.
Its published `base >= 3 && < 5` bound does not establish a GHC 9.4 incompatibility.
The direct FFI experiment instead targets the current system libgit2 API without that bundled library or the broader gitlib abstraction.

The upstream [Git.Repository helpers](https://github.com/jwiegley/gitlib/blob/master/gitlib/Git/Repository.hs) also include `withNewRepository`, which removes an existing supplied directory.
Do not apply that helper to persistent cache locations or user directories.
The product instead creates unique staging directories and never replaces or deletes an existing cache entry.

## Required behavior

The adapter accepts only the installer's internal argv-shaped operation protocol, not shell commands or arbitrary Git CLI operations.
Public network operations accept only fixed HTTPS GitHub URLs and validated refs/subpaths, and request shallow depth one.
Use only repository-local configuration plus an in-memory policy overlay, without global, system, or XDG configuration, and reject local configuration includes.
Disable interactive authentication, hooks, submodule recursion, URL rewriting, and HTTP redirects.
Offline synchronization verifies the locked commit and cache provenance without contacting the remote.
Preserve validation of physical cache directories, origin URL, HEAD, metadata indirections, tracked content hashes, and contained tracked symlinks without adopting or replacing an existing cache entry.
An explicit update fetches the configured refs for both plugins and standalone skills, validates the complete per-lock candidate, and then synchronizes links.
A snapshot containing submodules is rejected rather than recursively fetching another repository.
The CLI's `-r` means recursive project-lock discovery, not Git clone recursion and not a shorthand for `--ref`.

## Limitations

Installed credential helpers and private-repository authentication are not supported.
Cancellation is cooperative through callbacks and waits for the native worker to finish; DNS or TLS operations can delay it between callbacks.
The internal `fsck` operation validates objects and references but omits dangling-object stdout, and the status operation rejects conflicts instead of rendering conflict status.
This adapter is not a general Git CLI implementation.

## Build and packaging

The Nix development shell supplies libgit2, pkg-config, and native dependencies.
Non-Nix Cabal builds require libgit2 `>= 1.9 && < 1.10` development headers and pkg-config, not Git as a runtime transport dependency.
Root `package.yaml` and `e2e/package.yaml` are the hpack sources of truth; check in the generated `.cabal` files and let hpack discover module lists automatically.
The Docker sandbox-base builder runs an ordinary Cabal build inside `nix develop`, not `nix build`.
The Ubuntu 26.04 runtime copies only the actually linked Nix library closure, not the development toolchain.
Git and Python in that runtime support tests and probes, not product transport.
There is no Cabal `static` flag.

## Discovery compatibility

The original implementation delegates recursive discovery to Admiral 0.6.2's `target-file-discovery` utility.
The current [lock discovery implementation](../../lib/CPlugin/Paths.hs) preserves that discovery contract.
Preserve its nearest-parent requirement, directory-only ignore matching, included own lock, hidden-directory behavior, and refusal to traverse symlink directories.
The limited ignore matcher is not a full implementation of Git ignore semantics.
Prune `.git` metadata and installer-owned source snapshots as explicit safety exclusions, so source repositories cannot become projects during recursive update or sync.
The [CLI reference](../cli.md) defines these externally visible rules.
