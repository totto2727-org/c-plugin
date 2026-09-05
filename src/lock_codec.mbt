///|
pub impl @json.FromJson for GitHubOwner with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  GitHubOwner(value) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for GitHubOwner with fn to_json(self) -> Json {
  self.value.to_json()
}

///|
pub impl @json.FromJson for GitHubRepositoryName with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  GitHubRepositoryName(value) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for GitHubRepositoryName with fn to_json(self) -> Json {
  self.value.to_json()
}

///|
pub impl @json.FromJson for GitHubRepository with fn from_json(json, path) {
  let route : String = @json.from_json(json, path~)
  GitHubRepository::from_route(route) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for GitHubRepository with fn to_json(self) -> Json {
  self.route().to_json()
}

///|
pub impl @json.FromJson for Target with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  validate_restricted_relative_path_value(value, "target path") catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
  let relative : @x_path.RelativePath = @json.from_json(json, path~)
  Target::from_relative(relative)
}

///|
pub impl ToJson for Target with fn to_json(self) -> Json {
  self.path.to_json()
}

///|
pub impl @json.FromJson for RelativeSourcePath with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  validate_restricted_relative_path_value(value, "local repository path") catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
  let relative : @x_path.RelativePath = @json.from_json(json, path~)
  RelativeSourcePath::from_relative(relative)
}

///|
pub impl ToJson for RelativeSourcePath with fn to_json(self) -> Json {
  self.path.to_json()
}

///|
pub impl @json.FromJson for RelativePluginPath with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  validate_restricted_relative_path_value(value, "plugin path") catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
  let relative : @x_path.RelativePath = @json.from_json(json, path~)
  RelativePluginPath::from_relative(relative)
}

///|
pub impl ToJson for RelativePluginPath with fn to_json(self) -> Json {
  self.path.to_json()
}

///|
pub impl @json.FromJson for PluginName with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  PluginName(value) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for PluginName with fn to_json(self) -> Json {
  self.value.to_json()
}

///|
pub impl @json.FromJson for SkillName with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  SkillName(value) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for SkillName with fn to_json(self) -> Json {
  self.value.to_json()
}

///|
pub impl @json.FromJson for CommitId with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  CommitId(value) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for CommitId with fn to_json(self) -> Json {
  self.value.to_json()
}

///|
let lock_version_lens : @lens.Lens[Json] = @lens.root().json("version")

///|
let lock_targets_lens : @lens.Lens[Json] = @lens.root().json("targets")

///|
let lock_repositories_lens : @lens.Lens[Json] = @lens.root().json(
  "repositories",
)

///|
let repository_type_lens : @lens.Lens[String] = @lens.root().string("type")

///|
let github_repository_lens : @lens.Lens[Json] = @lens.root().json("repository")

///|
let github_marketplace_kind_lens : @lens.Lens[Json] = @lens.root().json(
  "marketplaceKind",
)

///|
let github_commit_lens : @lens.Lens[Json] = @lens.root().json("commit")

///|
let github_plugins_lens : @lens.Lens[Json] = @lens.root().json("plugins")

///|
let local_path_lens : @lens.Lens[Json] = @lens.root().json("path")

///|
let local_marketplace_kind_lens : @lens.Lens[Json] = @lens.root().json(
  "marketplaceKind",
)

///|
let local_plugins_lens : @lens.Lens[Json] = @lens.root().json("plugins")

///|
let plugin_name_lens : @lens.Lens[Json] = @lens.root().json("name")

///|
let plugin_path_lens : @lens.Lens[Json] = @lens.root().json("path")

///|
let plugin_enabled_skills_lens : @lens.Lens[Json] = @lens.root().json(
  "enabledSkills",
)

///|
pub impl @json.FromJson for MarketplaceKind with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  match value {
    "claude" => MarketplaceKind::claude()
    "cursor" => MarketplaceKind::cursor()
    "codex" => MarketplaceKind::codex()
    _ =>
      raise @json.JsonDecodeError(
        (path, "unsupported marketplace kind: \{value}"),
      )
  }
}

///|
pub impl ToJson for MarketplaceKind with fn to_json(self) -> Json {
  match self {
    Claude => "claude".to_json()
    Cursor => "cursor".to_json()
    Codex => "codex".to_json()
  }
}

///|
pub impl @json.FromJson for Plugin with fn from_json(json, path) {
  let name : PluginName = @json.from_json(
    plugin_name_lens.get_or_json_decode_error(json, path),
    path=plugin_name_lens.add_to_json_path(path),
  )
  let plugin_path : RelativePluginPath = @json.from_json(
    plugin_path_lens.get_or_json_decode_error(json, path),
    path=plugin_path_lens.add_to_json_path(path),
  )
  let enabled_skills : Array[SkillName] = @json.from_json(
    plugin_enabled_skills_lens.get_or_json_decode_error(json, path),
    path=plugin_enabled_skills_lens.add_to_json_path(path),
  )
  Plugin(name, plugin_path, enabled_skills) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for Plugin with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  let enabled_skills = self.enabled_skills.iter().to_array()
  enabled_skills.sort()
  plugin_name_lens.set_or_abort(builder, self.name.to_json())
  plugin_path_lens.set_or_abort(builder, self.path.to_json())
  plugin_enabled_skills_lens.set_or_abort(builder, enabled_skills.to_json())
  builder.to_json()
}

///|
fn sorted_plugins_for_json(
  plugins : @immut_hashmap.HashMap[PluginName, Plugin],
) -> Array[Plugin] {
  let entries = plugins.to_array()
  entries.sort_by((left, right) => left.0.compare(right.0))
  entries.map(entry => entry.1)
}

///|
pub impl @json.FromJson for GitHubLockRepository with fn from_json(json, path) {
  let type_ = repository_type_lens.get_or_json_decode_error(json, path)
  guard type_ == "github" else {
    raise repository_type_lens.json_decode_error(
      path, "expected repository type github",
    )
  }
  let repository : GitHubRepository = @json.from_json(
    github_repository_lens.get_or_json_decode_error(json, path),
    path=github_repository_lens.add_to_json_path(path),
  )
  let marketplace_kind : MarketplaceKind = @json.from_json(
    github_marketplace_kind_lens.get_or_json_decode_error(json, path),
    path=github_marketplace_kind_lens.add_to_json_path(path),
  )
  let commit : CommitId = @json.from_json(
    github_commit_lens.get_or_json_decode_error(json, path),
    path=github_commit_lens.add_to_json_path(path),
  )
  let plugins : Array[Plugin] = @json.from_json(
    github_plugins_lens.get_or_json_decode_error(json, path),
    path=github_plugins_lens.add_to_json_path(path),
  )
  GitHubLockRepository(repository, marketplace_kind, commit, plugins) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for GitHubLockRepository with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  repository_type_lens.set_or_abort(builder, "github")
  github_repository_lens.set_or_abort(builder, self.repository.to_json())
  github_marketplace_kind_lens.set_or_abort(
    builder,
    self.marketplace_kind.to_json(),
  )
  github_commit_lens.set_or_abort(builder, self.commit.to_json())
  github_plugins_lens.set_or_abort(
    builder,
    sorted_plugins_for_json(self.plugins).to_json(),
  )
  builder.to_json()
}

///|
pub impl @json.FromJson for LocalLockRepository with fn from_json(json, path) {
  let type_ = repository_type_lens.get_or_json_decode_error(json, path)
  guard type_ == "local" else {
    raise repository_type_lens.json_decode_error(
      path, "expected repository type local",
    )
  }
  let source_path : RelativeSourcePath = @json.from_json(
    local_path_lens.get_or_json_decode_error(json, path),
    path=local_path_lens.add_to_json_path(path),
  )
  let marketplace_kind : MarketplaceKind = @json.from_json(
    local_marketplace_kind_lens.get_or_json_decode_error(json, path),
    path=local_marketplace_kind_lens.add_to_json_path(path),
  )
  let plugins : Array[Plugin] = @json.from_json(
    local_plugins_lens.get_or_json_decode_error(json, path),
    path=local_plugins_lens.add_to_json_path(path),
  )
  LocalLockRepository(source_path, marketplace_kind, plugins) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for LocalLockRepository with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  repository_type_lens.set_or_abort(builder, "local")
  local_path_lens.set_or_abort(builder, self.path.to_json())
  local_marketplace_kind_lens.set_or_abort(
    builder,
    self.marketplace_kind.to_json(),
  )
  local_plugins_lens.set_or_abort(
    builder,
    sorted_plugins_for_json(self.plugins).to_json(),
  )
  builder.to_json()
}

///|
pub impl @json.FromJson for LockRepository with fn from_json(json, path) {
  let type_ = repository_type_lens.get_or_json_decode_error(json, path)
  match type_ {
    "github" => {
      let repository : GitHubLockRepository = @json.from_json(json, path~)
      LockRepository::github(repository)
    }
    "local" => {
      let repository : LocalLockRepository = @json.from_json(json, path~)
      LockRepository::from_local(repository)
    }
    _ =>
      raise repository_type_lens.json_decode_error(
        path,
        "unsupported repository type: \{type_}",
      )
  }
}

///|
pub impl ToJson for LockRepository with fn to_json(self) -> Json {
  match self {
    GitHub(repository) => repository.to_json()
    Local(repository) => repository.to_json()
  }
}

///|
pub impl @json.FromJson for Lock with fn from_json(json, path) {
  let version : String = @json.from_json(
    lock_version_lens.get_or_json_decode_error(json, path),
    path=lock_version_lens.add_to_json_path(path),
  )
  guard version == "2" else {
    raise lock_version_lens.json_decode_error(
      path,
      "unsupported lock version: \{version}",
    )
  }
  let targets : Array[Target] = @json.from_json(
    lock_targets_lens.get_or_json_decode_error(json, path),
    path=lock_targets_lens.add_to_json_path(path),
  )
  let repositories : Array[LockRepository] = @json.from_json(
    lock_repositories_lens.get_or_json_decode_error(json, path),
    path=lock_repositories_lens.add_to_json_path(path),
  )
  Lock(targets, repositories) catch {
    error => raise @json.JsonDecodeError((path, error.to_string()))
  }
}

///|
pub impl ToJson for Lock with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  let targets = self.targets.iter().to_array()
  targets.sort()
  let repository_entries = self.repositories.to_array()
  repository_entries.sort_by((left, right) => left.0.compare(right.0))
  let repositories = repository_entries.map(entry => entry.1)
  lock_version_lens.set_or_abort(builder, self.version.to_string().to_json())
  lock_targets_lens.set_or_abort(builder, targets.to_json())
  lock_repositories_lens.set_or_abort(builder, repositories.to_json())
  builder.to_json()
}

///|
pub fn Lock::to_pretty_json(self : Lock) -> String {
  self.to_json().stringify(indent=2) + "\n"
}
