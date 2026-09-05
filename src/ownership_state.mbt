///|
pub struct GitHubOwnershipSource {
  repository : GitHubRepository
  plugin : PluginName
  skill : SkillName
} derive(Eq)

///|
pub fn GitHubOwnershipSource::GitHubOwnershipSource(
  repository : GitHubRepository,
  plugin : PluginName,
  skill : SkillName,
) -> GitHubOwnershipSource {
  { repository, plugin, skill }
}

///|
pub impl Compare for GitHubOwnershipSource with fn compare(self, other) {
  let repository = Compare::compare(self.repository, other.repository)
  if repository != 0 {
    repository
  } else {
    let plugin = Compare::compare(self.plugin, other.plugin)
    if plugin != 0 {
      plugin
    } else {
      Compare::compare(self.skill, other.skill)
    }
  }
}

///|
pub struct LocalOwnershipSource {
  repository : RelativeSourcePath
  plugin : PluginName
  skill : SkillName
} derive(Eq)

///|
pub fn LocalOwnershipSource::LocalOwnershipSource(
  repository : RelativeSourcePath,
  plugin : PluginName,
  skill : SkillName,
) -> LocalOwnershipSource {
  { repository, plugin, skill }
}

///|
pub impl Compare for LocalOwnershipSource with fn compare(self, other) {
  let repository = Compare::compare(self.repository, other.repository)
  if repository != 0 {
    repository
  } else {
    let plugin = Compare::compare(self.plugin, other.plugin)
    if plugin != 0 {
      plugin
    } else {
      Compare::compare(self.skill, other.skill)
    }
  }
}

///|
pub enum OwnershipSource {
  GitHub(GitHubOwnershipSource)
  Local(LocalOwnershipSource)
} derive(Eq)

///|
pub impl Compare for OwnershipSource with fn compare(self, other) {
  match (self, other) {
    (GitHub(left), GitHub(right)) => Compare::compare(left, right)
    (GitHub(_), Local(_)) => -1
    (Local(_), GitHub(_)) => 1
    (Local(left), Local(right)) => Compare::compare(left, right)
  }
}

///|
pub fn OwnershipSource::from_github(
  source : GitHubOwnershipSource,
) -> OwnershipSource {
  GitHub(source)
}

///|
pub fn OwnershipSource::from_local(
  source : LocalOwnershipSource,
) -> OwnershipSource {
  Local(source)
}

///|
pub(all) suberror OwnershipStatePathError {
  OwnershipStatePathConstructionFailed(path~ : @path.Path, cause~ : Error)
}

///|
pub(all) suberror OwnershipLinkError {
  OwnershipLinkConstructionFailed(path~ : @path.Path, cause~ : Error)
}

///|
pub(all) suberror OwnershipResolvedTargetError {
  OwnershipResolvedTargetConstructionFailed(path~ : @path.Path, cause~ : Error)
}

///|
pub(all) suberror OwnershipManagedRootError {
  OwnershipManagedRootConstructionFailed(path~ : @path.Path, cause~ : Error)
}

///|
pub(all) suberror OwnershipEntryError {
  OwnershipLinkOutsideManagedRoot(
    link~ : OwnershipLink,
    managed_root~ : OwnershipManagedRoot
  )
}

///|
pub(all) suberror OwnershipStateError {
  DuplicateOwnershipLink(identity~ : OwnershipLinkIdentity)
}

///|
pub struct OwnershipStatePath {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub fn OwnershipStatePath::OwnershipStatePath(
  path : @path.Path,
) -> OwnershipStatePath raise OwnershipStatePathError {
  // The shared path constructor has an open error effect. Preserve its cause
  // at this boundary instead of duplicating its absolute-path validation.
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    cause => raise OwnershipStatePathConstructionFailed(path~, cause~)
  }
  { path: absolute }
}

///|
pub struct OwnershipLink {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub fn OwnershipLink::OwnershipLink(
  path : @path.Path,
) -> OwnershipLink raise OwnershipLinkError {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    cause => raise OwnershipLinkConstructionFailed(path~, cause~)
  }
  { path: absolute }
}

///|
pub impl Compare for OwnershipLink with fn compare(self, other) {
  @x_path.Path::to_string(self.path).lexical_compare(
    @x_path.Path::to_string(other.path),
  )
}

///|
pub struct OwnershipResolvedTarget {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub fn OwnershipResolvedTarget::OwnershipResolvedTarget(
  path : @path.Path,
) -> OwnershipResolvedTarget raise OwnershipResolvedTargetError {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    cause => raise OwnershipResolvedTargetConstructionFailed(path~, cause~)
  }
  { path: absolute }
}

///|
pub impl Compare for OwnershipResolvedTarget with fn compare(self, other) {
  @x_path.Path::to_string(self.path).lexical_compare(
    @x_path.Path::to_string(other.path),
  )
}

///|
pub struct OwnershipManagedRoot {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub fn OwnershipManagedRoot::OwnershipManagedRoot(
  path : @path.Path,
) -> OwnershipManagedRoot raise OwnershipManagedRootError {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    cause => raise OwnershipManagedRootConstructionFailed(path~, cause~)
  }
  { path: absolute }
}

///|
pub impl Compare for OwnershipManagedRoot with fn compare(self, other) {
  @x_path.Path::to_string(self.path).lexical_compare(
    @x_path.Path::to_string(other.path),
  )
}

///|
pub struct OwnershipEntry {
  link : OwnershipLink
  symlink_target : @path.Path
  resolved_target : OwnershipResolvedTarget
  managed_root : OwnershipManagedRoot
  source : OwnershipSource
} derive(Eq)

///|
pub fn OwnershipEntry::OwnershipEntry(
  link : OwnershipLink,
  symlink_target : @path.Path,
  resolved_target : OwnershipResolvedTarget,
  managed_root : OwnershipManagedRoot,
  source : OwnershipSource,
) -> OwnershipEntry raise OwnershipEntryError {
  guard link.path.path.dirname() == managed_root.path.path else {
    raise OwnershipLinkOutsideManagedRoot(link~, managed_root~)
  }
  { link, symlink_target, resolved_target, managed_root, source }
}

///|
pub impl Compare for OwnershipEntry with fn compare(self, other) {
  let link = Compare::compare(self.link, other.link)
  if link != 0 {
    link
  } else {
    let symlink_target = self.symlink_target
      .to_string()
      .lexical_compare(other.symlink_target.to_string())
    if symlink_target != 0 {
      symlink_target
    } else {
      let resolved_target = Compare::compare(
        self.resolved_target,
        other.resolved_target,
      )
      if resolved_target != 0 {
        resolved_target
      } else {
        let managed_root = Compare::compare(
          self.managed_root,
          other.managed_root,
        )
        if managed_root != 0 {
          managed_root
        } else {
          Compare::compare(self.source, other.source)
        }
      }
    }
  }
}

///|
pub struct OwnershipState {
  version : Int
  entries : @immut_hashmap.HashMap[OwnershipLinkIdentity, OwnershipEntry]
} derive(Eq)

///|
pub struct OwnershipLinkIdentity {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub impl Compare for OwnershipLinkIdentity with fn compare(self, other) {
  @x_path.Path::to_string(self.path).lexical_compare(
    @x_path.Path::to_string(other.path),
  )
}

///|
pub fn OwnershipLinkIdentity::OwnershipLinkIdentity(
  path : @x_path.AbsolutePath,
) -> OwnershipLinkIdentity {
  { path, }
}

///|
pub impl Hash for OwnershipLinkIdentity with fn hash_combine(self, hasher) {
  Hash::hash_combine(@x_path.Path::to_string(self.path), hasher)
}

///|
pub fn OwnershipState::OwnershipState(
  entries : Array[OwnershipEntry],
) -> OwnershipState raise OwnershipStateError {
  let mut stored_entries : @immut_hashmap.HashMap[
    OwnershipLinkIdentity,
    OwnershipEntry,
  ] = @immut_hashmap.HashMap([])
  for entry in entries {
    let identity = OwnershipLinkIdentity(entry.link.path)
    guard stored_entries.get(identity) is None else {
      raise DuplicateOwnershipLink(identity~)
    }
    stored_entries = stored_entries.add(identity, entry)
  }
  { version: 1, entries: stored_entries }
}

///|
pub fn OwnershipState::empty() -> OwnershipState {
  { version: 1, entries: @immut_hashmap.HashMap([]) }
}
