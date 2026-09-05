///|
struct LinkReconciliationIO {
  mkdir : async (@path.Path) -> Unit
  kind : async (@path.Path) -> @fs.FileKind
  realpath : async (@path.Path) -> @path.Path
  symlink : async (@path.Path, @path.Path) -> Unit
  remove : async (@path.Path) -> Unit
  checkpoint : async (@path.Path, OwnershipState) -> Unit raise StateStoreError
}

///|
enum StaleLinkRecheck {
  Matching
  Missing
  Replaced
  Failed(operation~ : LinkReconciliationOperation, reason~ : String)
}

///|
fn production_link_reconciliation_io(
  checkpoint : async (@path.Path, OwnershipState) -> Unit raise StateStoreError,
) -> LinkReconciliationIO {
  {
    mkdir: async fn(path) {
      @fs.mkdir(path.to_string(), recursive=true) catch {
        @os_error.OSError(_) as error if error.is_EEXIST() => ()
        error => raise error
      }
    },
    kind: async fn(path) { @fs.kind(path.to_string(), follow_symlink=false) },
    realpath: async fn(path) { @path.Path(@fs.realpath(path.to_string())) },
    symlink: async fn(target, link) {
      @fs.symlink(target=target.to_string(), link.to_string())
    },
    remove: async fn(path) { @fs.remove(path.to_string()) },
    checkpoint,
  }
}

///|
async fn classify_link(
  io : LinkReconciliationIO,
  path : @path.Path,
) -> @fs.FileKind? {
  try (io.kind)(path) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    error => raise error
  } noraise {
    kind => Some(kind)
  }
}

///|
async fn is_physically_contained(
  io : LinkReconciliationIO,
  entry : OwnershipEntry,
) -> Bool {
  let physical_root = (io.realpath)(entry.managed_root.path.path).normalize()
  let physical_parent = (io.realpath)(entry.link.path.path.dirname()).normalize()
  physical_parent == physical_root
}

///|
async fn recheck_stale_link(
  io : LinkReconciliationIO,
  entry : OwnershipEntry,
) -> StaleLinkRecheck {
  let root_kind = (io.kind)(entry.managed_root.path.path) catch {
    error =>
      return Failed(operation=VerifyContainment, reason=error.to_string())
  }
  guard root_kind == @fs.FileKind::Directory else {
    return Failed(
      operation=VerifyContainment,
      reason="recorded managed root must be a physical directory",
    )
  }
  let contained = is_physically_contained(io, entry) catch {
    error =>
      return Failed(operation=VerifyContainment, reason=error.to_string())
  }
  guard contained else {
    return Failed(
      operation=VerifyContainment,
      reason="physical containment changed",
    )
  }
  let kind = classify_link(io, entry.link.path.path) catch {
    error => return Failed(operation=ClassifyLink, reason=error.to_string())
  }
  match kind {
    None => Missing
    Some(@fs.FileKind::SymLink) =>
      try (io.realpath)(entry.link.path.path) catch {
        @os_error.OSError(_) as error if error.is_ENOENT() => Replaced
        error => Failed(operation=ClassifyLink, reason=error.to_string())
      } noraise {
        target =>
          if target.normalize() == entry.resolved_target.path.path {
            Matching
          } else {
            Replaced
          }
      }
    Some(_) => Replaced
  }
}
