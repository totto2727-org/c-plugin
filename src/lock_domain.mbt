///|
pub struct GitHubOwner {
  value : String
} derive(Eq, Hash)

///|
pub fn GitHubOwner::GitHubOwner(value : String) -> GitHubOwner raise {
  guard value != "" &&
    value.length() <= 39 &&
    !value.has_prefix("-") &&
    !value.has_suffix("-") &&
    !value.contains("--") &&
    value.all(char => {
      char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '-'
    }) else {
    fail("GitHub owner must be a valid GitHub account component")
  }
  { value: value.to_lower() }
}

///|
pub struct GitHubRepositoryName {
  value : String
} derive(Eq, Hash)

///|
pub fn GitHubRepositoryName::GitHubRepositoryName(
  value : String,
) -> GitHubRepositoryName raise {
  guard value != "" &&
    value.length() <= 100 &&
    value != "." &&
    value != ".." &&
    value.all(char => {
      char.is_ascii_alphabetic() ||
      char.is_ascii_digit() ||
      char == '-' ||
      char == '_' ||
      char == '.'
    }) else {
    fail("GitHub repository name contains an unsupported character")
  }
  { value: value.to_lower() }
}

///|
pub struct GitHubRepository {
  owner : GitHubOwner
  name : GitHubRepositoryName
} derive(Eq, Hash)

///|
pub impl Compare for GitHubRepository with fn compare(self, other) {
  self.route().lexical_compare(other.route())
}

///|
pub fn GitHubRepository::GitHubRepository(
  owner : GitHubOwner,
  name : GitHubRepositoryName,
) -> GitHubRepository {
  { owner, name }
}

///|
pub fn GitHubRepository::from_route(route : String) -> GitHubRepository raise {
  let components = route
    .split("/")
    .map(fn(component) { component.to_owned() })
    .collect()
  guard components.length() == 2 else {
    fail("GitHub repository route must be owner/name")
  }
  GitHubRepository(
    GitHubOwner(components[0]),
    GitHubRepositoryName(components[1]),
  )
}

///|
pub fn GitHubRepository::route(self : GitHubRepository) -> String {
  "\{self.owner.value}/\{self.name.value}"
}

///|
pub struct Target {
  path : @x_path.RelativePath
} derive(Eq)

///|
pub impl Compare for Target with fn compare(self, other) {
  @x_path.Path::to_string(self.path).lexical_compare(
    @x_path.Path::to_string(other.path),
  )
}

///|
pub impl Hash for Target with fn hash_combine(self, hasher) {
  Hash::hash_combine(@x_path.Path::to_string(self.path), hasher)
}

///|
pub fn Target::Target(path : @path.Path) -> Target raise {
  Target::from_relative(restricted_relative_path(path, "target path"))
}

///|
fn Target::from_relative(path : @x_path.RelativePath) -> Target {
  { path, }
}

///|
pub struct RelativeSourcePath {
  path : @x_path.RelativePath
} derive(Eq)

///|
pub impl Compare for RelativeSourcePath with fn compare(self, other) {
  @x_path.Path::to_string(self.path).lexical_compare(
    @x_path.Path::to_string(other.path),
  )
}

///|
pub impl Hash for RelativeSourcePath with fn hash_combine(self, hasher) {
  Hash::hash_combine(@x_path.Path::to_string(self.path), hasher)
}

///|
pub fn RelativeSourcePath::RelativeSourcePath(
  path : @path.Path,
) -> RelativeSourcePath raise {
  RelativeSourcePath::from_relative(
    restricted_relative_path(path, "local repository path"),
  )
}

///|
fn RelativeSourcePath::from_relative(
  path : @x_path.RelativePath,
) -> RelativeSourcePath {
  { path, }
}

///|
pub struct RelativePluginPath {
  path : @x_path.RelativePath
} derive(Eq)

///|
pub impl Hash for RelativePluginPath with fn hash_combine(self, hasher) {
  Hash::hash_combine(@x_path.Path::to_string(self.path), hasher)
}

///|
pub fn RelativePluginPath::RelativePluginPath(
  path : @path.Path,
) -> RelativePluginPath raise {
  RelativePluginPath::from_relative(
    restricted_relative_path(path, "plugin path"),
  )
}

///|
fn RelativePluginPath::from_relative(
  path : @x_path.RelativePath,
) -> RelativePluginPath {
  { path, }
}

///|
fn restricted_relative_path(
  path : @path.Path,
  kind : String,
) -> @x_path.RelativePath raise {
  let value = path.to_string()
  validate_restricted_relative_path_value(value, kind)
  @x_path.RelativePath::RelativePath(path) catch {
    _ => fail("\{kind} must be a relative path")
  }
}

///|
fn validate_restricted_relative_path_value(
  value : String,
  kind : String,
) -> Unit raise {
  guard value != "" && !value.contains("\\") else {
    fail("\{kind} must be a relative path")
  }
  let segments = value
    .split("/")
    .map(fn(segment) { segment.to_owned() })
    .collect()
  guard !segments.contains("..") else {
    fail("\{kind} must not traverse parent directories")
  }
}

///|
pub struct PluginName {
  value : String
} derive(Eq, Hash)

///|
pub impl Compare for PluginName with fn compare(self, other) {
  self.value.lexical_compare(other.value)
}

///|
pub fn PluginName::PluginName(value : String) -> PluginName raise {
  validate_item_name(value, "plugin name")
  { value, }
}

///|
pub struct SkillName {
  value : String
} derive(Eq, Hash)

///|
pub impl Compare for SkillName with fn compare(self, other) {
  self.value.lexical_compare(other.value)
}

///|
pub fn SkillName::SkillName(value : String) -> SkillName raise {
  validate_item_name(value, "skill name")
  { value, }
}

///|
fn validate_item_name(value : String, kind : String) -> Unit raise {
  guard value != "" &&
    value != "." &&
    value != ".." &&
    !value.contains("/") &&
    !value.contains("\\") else {
    fail("\{kind} must be a non-path name")
  }
}

///|
pub struct CommitId {
  value : String
} derive(Eq)

///|
pub fn CommitId::CommitId(value : String) -> CommitId raise {
  guard value.length() == 40 && value.all(is_ascii_hexadecimal) else {
    fail("commit ID must be a 40-character hexadecimal object ID")
  }
  { value: value.to_lower() }
}

///|
fn is_ascii_hexadecimal(char : Char) -> Bool {
  char.is_ascii_digit() ||
  (char >= 'a' && char <= 'f') ||
  (char >= 'A' && char <= 'F')
}

///|
pub enum MarketplaceKind {
  Claude
  Cursor
  Codex
} derive(Eq)

///|
pub fn MarketplaceKind::claude() -> MarketplaceKind {
  Claude
}

///|
pub fn MarketplaceKind::cursor() -> MarketplaceKind {
  Cursor
}

///|
pub fn MarketplaceKind::codex() -> MarketplaceKind {
  Codex
}

///|
pub struct Plugin {
  name : PluginName
  path : RelativePluginPath
  enabled_skills : @immut_hashset.HashSet[SkillName]
} derive(Eq)

///|
pub fn Plugin::Plugin(
  name : PluginName,
  path : RelativePluginPath,
  enabled_skills : Array[SkillName],
) -> Plugin raise {
  let stored_skills = @immut_hashset.HashSet(enabled_skills)
  guard stored_skills.length() == enabled_skills.length() else {
    fail("plugin enabled skills must be unique")
  }
  { name, path, enabled_skills: stored_skills }
}

///|
pub struct GitHubLockRepository {
  repository : GitHubRepository
  marketplace_kind : MarketplaceKind
  commit : CommitId
  plugins : @immut_hashmap.HashMap[PluginName, Plugin]
} derive(Eq)

///|
pub fn GitHubLockRepository::GitHubLockRepository(
  repository : GitHubRepository,
  marketplace_kind : MarketplaceKind,
  commit : CommitId,
  plugins : Array[Plugin],
) -> GitHubLockRepository raise {
  let stored_plugins = @immut_hashmap.HashMap(
    plugins.map(plugin => (plugin.name, plugin)),
  )
  guard stored_plugins.length() == plugins.length() else {
    fail("repository plugin names must be unique")
  }
  { repository, marketplace_kind, commit, plugins: stored_plugins }
}

///|
pub struct LocalLockRepository {
  path : RelativeSourcePath
  marketplace_kind : MarketplaceKind
  plugins : @immut_hashmap.HashMap[PluginName, Plugin]
} derive(Eq)

///|
pub fn LocalLockRepository::LocalLockRepository(
  path : RelativeSourcePath,
  marketplace_kind : MarketplaceKind,
  plugins : Array[Plugin],
) -> LocalLockRepository raise {
  let stored_plugins = @immut_hashmap.HashMap(
    plugins.map(plugin => (plugin.name, plugin)),
  )
  guard stored_plugins.length() == plugins.length() else {
    fail("repository plugin names must be unique")
  }
  { path, marketplace_kind, plugins: stored_plugins }
}

///|
pub enum LockRepository {
  GitHub(GitHubLockRepository)
  Local(LocalLockRepository)
} derive(Eq)

///|
pub fn LockRepository::github(
  repository : GitHubLockRepository,
) -> LockRepository {
  GitHub(repository)
}

///|
pub fn LockRepository::from_local(
  repository : LocalLockRepository,
) -> LockRepository {
  Local(repository)
}

///|
pub struct Lock {
  version : Int
  targets : @immut_hashset.HashSet[Target]
  repositories : @immut_hashmap.HashMap[RepositoryIdentity, LockRepository]
} derive(Eq)

///|
pub fn Lock::Lock(
  targets : Array[Target],
  repositories : Array[LockRepository],
) -> Lock raise {
  let stored_targets = @immut_hashset.HashSet(targets)
  guard stored_targets.length() == targets.length() else {
    fail("lock targets must be unique")
  }
  let stored_repositories = @immut_hashmap.HashMap(
    repositories.map(repository => (repository.identity(), repository)),
  )
  guard stored_repositories.length() == repositories.length() else {
    fail("lock repositories must be unique")
  }
  { version: 2, targets: stored_targets, repositories: stored_repositories }
}

///|
pub enum RepositoryIdentity {
  GitHubIdentity(GitHubRepository)
  LocalIdentity(RelativeSourcePath)
} derive(Eq, Hash)

///|
pub impl Compare for RepositoryIdentity with fn compare(self, other) {
  match (self, other) {
    (GitHubIdentity(left), GitHubIdentity(right)) => left.compare(right)
    (GitHubIdentity(_), LocalIdentity(_)) => -1
    (LocalIdentity(_), GitHubIdentity(_)) => 1
    (LocalIdentity(left), LocalIdentity(right)) => left.compare(right)
  }
}

///|
pub fn LockRepository::identity(self : LockRepository) -> RepositoryIdentity {
  match self {
    GitHub(repository) => GitHubIdentity(repository.repository)
    Local(repository) => LocalIdentity(repository.path)
  }
}
