///|
let add_global_option : @admiral.OptionDef[Bool] = @admiral.bool(
  "global",
  short='g',
  description="Use the user-level lock file",
)

///|
let add_force_option : @admiral.OptionDef[Bool] = @admiral.bool(
  "force",
  short='f',
  description="Replace existing non-directory skill paths",
)

///|
let add_local_option : @admiral.OptionDef[String] = @admiral.string(
  "local",
  description="Local marketplace root beginning with ./",
  required=true,
)

///|
let add_kind_option : @admiral.OptionDef[String] = @admiral.string(
  "kind",
  description="Marketplace kind: claude, cursor, or codex",
  required=true,
)

///|
let add_skill_option : @admiral.OptionDef[Array[String]] = @admiral.strings(
  "skill",
  description="Plugin and skill selection as plugin/skill",
  required=true,
)

///|
struct AddLocalOptions {
  global : Bool
  force : Bool
  source : RelativeSourcePath
  kind : MarketplaceKind
  selections : ReadOnlyArray[String]
}

///|
struct AddLocalResult {
  repository_root : RepositoryRoot
  sync_result : SyncLockResult
}

///|
struct AddSkillSelection {
  plugin_name : PluginName
  skill_name : SkillName
}

///|
pub(all) suberror AddLocalError {
  Discovery(cause~ : LockDiscoveryError)
  Store(cause~ : StateStoreError)
  InvalidInput(reason~ : String)
  SyncAfterPersist(cause~ : SyncError)
} derive(Debug)

///|
fn add_marketplace_kind(value : String) -> MarketplaceKind raise AddLocalError {
  match value {
    "claude" => MarketplaceKind::claude()
    "cursor" => MarketplaceKind::cursor()
    "codex" => MarketplaceKind::codex()
    _ => raise InvalidInput(reason="unsupported marketplace kind: " + value)
  }
}

///|
fn add_local_options(context : @admiral.Context) -> AddLocalOptions raise {
  let source = context.get_string_required(add_local_option)
  guard source.has_prefix("./") else {
    raise AddLocalError::InvalidInput(reason="--local path must begin with ./")
  }
  let normalized_source = @x_path.RelativePath::from_string(source) catch {
    error => raise AddLocalError::InvalidInput(reason=error.to_string())
  }
  let source_path = RelativeSourcePath::RelativeSourcePath(
    normalized_source.path,
  ) catch {
    error => raise AddLocalError::InvalidInput(reason=error.to_string())
  }
  {
    global: context.get_bool(add_global_option),
    force: context.get_bool(add_force_option),
    source: source_path,
    kind: add_marketplace_kind(context.get_string_required(add_kind_option)),
    selections: context.get_strings_required(add_skill_option).all,
  }
}

///|
fn resolve_add_repository_root(
  lock_path : @path.Path,
  source : RelativeSourcePath,
) -> RepositoryRoot raise AddLocalError {
  RepositoryRoot::RepositoryRoot(lock_path.dirname().join(source.path.path)) catch {
    error =>
      raise AddLocalError::InvalidInput(
        reason=repository_root_error_reason(error),
      )
  }
}

///|
fn parse_add_skill_selection(
  value : String,
) -> AddSkillSelection raise AddLocalError {
  let parts : Array[String] = value
    .split("/")
    .map(part => part.to_owned())
    .collect()
  guard parts.length() == 2 else {
    raise InvalidInput(reason="skill selection must be plugin/skill: " + value)
  }
  {
    plugin_name: PluginName::PluginName(parts[0]) catch {
      error => raise InvalidInput(reason=error.to_string())
    },
    skill_name: SkillName::SkillName(parts[1]) catch {
      error => raise InvalidInput(reason=error.to_string())
    },
  }
}

///|
fn build_local_add_candidate(
  current_lock : Lock,
  source : RelativeSourcePath,
  kind : MarketplaceKind,
  marketplace : Marketplace,
  resolved_skills : ReadOnlyArray[ResolvedSkill],
  selections : ReadOnlyArray[String],
) -> Lock raise AddLocalError {
  let selected = selections.map(parse_add_skill_selection)
  for selection in selected {
    guard resolved_skills.any(skill => {
      skill.plugin_name == selection.plugin_name &&
      skill.skill_name == selection.skill_name
    }) else {
      raise InvalidInput(
        reason="unknown marketplace skill: {selection.plugin_name.value}/{selection.skill_name.value}",
      )
    }
  }
  let plugins : Array[Plugin] = []
  for marketplace_plugin in marketplace.plugins {
    let enabled = selected
      .filter(selection => selection.plugin_name == marketplace_plugin.name)
      .map(selection => selection.skill_name)
      .iter()
      .to_array()
    if enabled.length() > 0 {
      plugins.push(
        Plugin::Plugin(
          marketplace_plugin.name,
          marketplace_plugin.path,
          enabled,
        ) catch {
          error => raise InvalidInput(reason=error.to_string())
        },
      )
    }
  }
  let repository = LocalLockRepository::LocalLockRepository(
    source, kind, plugins,
  ) catch {
    error => raise InvalidInput(reason=error.to_string())
  }
  let repositories = current_lock.repositories.to_array().map(entry => entry.1)
  repositories.push(LockRepository::from_local(repository))
  Lock::Lock(current_lock.targets.iter().to_array(), repositories) catch {
    error => raise InvalidInput(reason=error.to_string())
  }
}

///|
async fn add_local(
  runtime : Runtime,
  options : AddLocalOptions,
) -> AddLocalResult raise AddLocalError {
  let discovery_options = if options.global {
    LockDiscoveryOptions::Global
  } else {
    LockDiscoveryOptions::Project(recursive=false)
  }
  let lock_paths = runtime.discover_locks(discovery_options) catch {
    error => raise Discovery(cause=error)
  }
  guard lock_paths.length() == 1 else {
    raise InvalidInput(reason="add requires exactly one lock file")
  }
  let lock_path = lock_paths[0]
  let current_lock = runtime.load_lock(lock_path) catch {
    error => raise Store(cause=error)
  }
  let repository_root = resolve_add_repository_root(lock_path, options.source)
  let marketplace = read_marketplace_file(
    repository_root.path.path.join(marketplace_manifest_path(options.kind)),
    options.kind,
  ) catch {
    error => raise InvalidInput(reason=marketplace_read_error_reason(error))
  }
  let resolved_skills = resolve_marketplace_skills(repository_root, marketplace) catch {
    error => raise InvalidInput(reason=skill_resolution_error_reason(error))
  }
  let candidate = build_local_add_candidate(
    current_lock,
    options.source,
    options.kind,
    marketplace,
    resolved_skills,
    options.selections,
  )
  let mut sync_result : SyncLockResult? = None
  let result = persist_and_sync(
    current_lock~,
    candidate=Some(candidate),
    persist=lock => runtime.write_lock_atomic(lock_path, lock),
    sync=lock => {
      try {
        sync_result = Some(
          sync_loaded_lock(
            runtime,
            lock_path,
            lock,
            collision_policy=if options.force {
              ReplaceNonDirectory
            } else {
              PreserveExisting
            },
          ),
        )
      } catch {
        SyncError::Store(cause~) => raise SyncError::Store(cause~)
        SyncError::InvalidPath(path~, reason~) =>
          raise SyncError::InvalidPath(path~, reason~)
        SyncError::Planning(reason~) => raise SyncError::Planning(reason~)
        error => raise SyncError::Planning(reason=error.to_string())
      }
    },
  ) catch {
    error => raise Store(cause=error)
  }
  match result {
    PersistedButSyncFailed(cause~) => raise SyncAfterPersist(cause~)
    NoChange =>
      raise InvalidInput(reason="add candidate did not change the lock")
    Synced => ()
  }
  let synchronized = match sync_result {
    Some(result) => result
    None => raise InvalidInput(reason="add sync completed without a result")
  }
  { repository_root, sync_result: synchronized }
}

///|
async fn run_add_local(runtime : Runtime, context : @admiral.Context) -> Unit {
  let result = add_local(runtime, add_local_options(context))
  println(
    "Added " +
    result.repository_root.path.to_string() +
    " to " +
    result.sync_result.lock_path.to_string() +
    ": " +
    sync_status_text(result.sync_result.reconciliation.status) +
    " (" +
    result.sync_result.reconciliation.notices.length().to_string() +
    " notices, " +
    result.sync_result.unavailable_repositories.length().to_string() +
    " unavailable repositories)",
  )
}

///|
fn add_local_command_def(
  run : async (@admiral.Context) -> Unit,
) -> @admiral.CommandDef {
  @admiral.CommandDef::CommandDef(
    name="add",
    description="Add a local plugin marketplace",
    options=[
      add_global_option, add_force_option, add_local_option, add_kind_option, add_skill_option,
    ],
    run=Some(run),
  )
}
