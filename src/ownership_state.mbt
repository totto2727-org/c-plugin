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
  let repository = self.repository.compare(other.repository)
  if repository != 0 {
    repository
  } else {
    let plugin = self.plugin.compare(other.plugin)
    if plugin != 0 {
      plugin
    } else {
      self.skill.compare(other.skill)
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
  let repository = self.repository.compare(other.repository)
  if repository != 0 {
    repository
  } else {
    let plugin = self.plugin.compare(other.plugin)
    if plugin != 0 {
      plugin
    } else {
      self.skill.compare(other.skill)
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
    (GitHub(left), GitHub(right)) => left.compare(right)
    (GitHub(_), Local(_)) => -1
    (Local(_), GitHub(_)) => 1
    (Local(left), Local(right)) => left.compare(right)
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
pub struct OwnershipStatePath {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub fn OwnershipStatePath::OwnershipStatePath(
  path : @path.Path,
) -> OwnershipStatePath raise {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    _ => fail("ownership state path must be absolute")
  }
  { path: absolute }
}

///|
pub struct OwnershipLink {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub fn OwnershipLink::OwnershipLink(path : @path.Path) -> OwnershipLink raise {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    _ => fail("ownership link must be absolute")
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
) -> OwnershipResolvedTarget raise {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    _ => fail("ownership resolved target must be absolute")
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
) -> OwnershipManagedRoot raise {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    _ => fail("ownership managed root must be absolute")
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
) -> OwnershipEntry raise {
  guard link.path.path.dirname() == managed_root.path.path else {
    fail("ownership link must be a direct child of its managed root")
  }
  { link, symlink_target, resolved_target, managed_root, source }
}

///|
pub impl Compare for OwnershipEntry with fn compare(self, other) {
  let link = self.link.compare(other.link)
  if link != 0 {
    link
  } else {
    let symlink_target = self.symlink_target
      .to_string()
      .lexical_compare(other.symlink_target.to_string())
    if symlink_target != 0 {
      symlink_target
    } else {
      let resolved_target = self.resolved_target.compare(other.resolved_target)
      if resolved_target != 0 {
        resolved_target
      } else {
        let managed_root = self.managed_root.compare(other.managed_root)
        if managed_root != 0 {
          managed_root
        } else {
          self.source.compare(other.source)
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
) -> OwnershipState raise {
  let stored_entries = @immut_hashmap.HashMap(
    entries.map(entry => (OwnershipLinkIdentity(entry.link.path), entry)),
  )
  guard stored_entries.length() == entries.length() else {
    fail("ownership links must be unique")
  }
  { version: 1, entries: stored_entries }
}

///|
pub fn OwnershipState::empty() -> OwnershipState {
  { version: 1, entries: @immut_hashmap.HashMap([]) }
}
