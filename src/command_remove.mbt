///|
let remove_global_option : @admiral.OptionDef[Bool] = @admiral.bool(
  "global",
  short='g',
  description="Use the user-level lock file",
)

///|
let remove_skill_option : @admiral.OptionDef[Array[String]] = @admiral.strings(
  "skill",
  description="Installed local skill as repository/plugin/skill",
)

///|
struct RemoveSkillSelection {
  repository : RepositoryIdentity
  plugin_name : PluginName
  skill_name : SkillName
}

///|
struct RemoveOptions {
  global : Bool
  selections : ReadOnlyArray[RemoveSkillSelection]
}

///|
enum RemoveResult {
  Removed(
    selections~ : ReadOnlyArray[RemoveSkillSelection],
    sync_result~ : SyncLockResult
  )
  Unchanged(lock_path~ : @path.Path)
}

///|
pub(all) suberror RemoveError {
  Discovery(cause~ : LockDiscoveryError)
  Store(cause~ : StateStoreError)
  InvalidInput(reason~ : String)
  SyncAfterPersist(cause~ : SyncError)
} derive(Debug)

///|
fn parse_remove_skill_selection(
  value : String,
) -> RemoveSkillSelection raise RemoveError {
  let parts : Array[String] = value
    .split("/")
    .map(part => part.to_owned())
    .collect()
  guard parts.length() >= 3 else {
    raise InvalidInput(
      reason="skill selection must be repository/plugin/skill: " + value,
    )
  }
  let repository_path = parts[0:parts.length() - 2].join("/")
  let repository = RepositoryIdentity::LocalIdentity(
    RelativeSourcePath::RelativeSourcePath(repository_path) catch {
      error => raise InvalidInput(reason=error.to_string())
    },
  )
  {
    repository,
    plugin_name: PluginName::PluginName(parts[parts.length() - 2]) catch {
      error => raise InvalidInput(reason=error.to_string())
    },
    skill_name: SkillName::SkillName(parts[parts.length() - 1]) catch {
      error => raise InvalidInput(reason=error.to_string())
    },
  }
}

///|
fn remove_skill_selection_text(selection : RemoveSkillSelection) -> String {
  match selection.repository {
    LocalIdentity(source) =>
      "\{@x_path.Path::to_string(source.path)}/\{selection.plugin_name.value}/\{selection.skill_name.value}"
    GitHubIdentity(repository) =>
      "\{repository.route()}/\{selection.plugin_name.value}/\{selection.skill_name.value}"
  }
}

///|
fn remove_options(context : @admiral.Context) -> RemoveOptions raise {
  let selections = []
  for value in context.get_strings(remove_skill_option) {
    selections.push(parse_remove_skill_selection(value))
  }
  {
    global: context.get_bool(remove_global_option),
    selections: ReadOnlyArray::from_array(selections),
  }
}

///|
fn remove_selection_exists(
  current_lock : Lock,
  selection : RemoveSkillSelection,
) -> Bool {
  match current_lock.repositories.get(selection.repository) {
    Some(Local(repository)) =>
      match repository.plugins.get(selection.plugin_name) {
        Some(plugin) => plugin.enabled_skills.contains(selection.skill_name)
        None => false
      }
    _ => false
  }
}

///|
fn rebuild_local_repository_after_remove(
  repository : LocalLockRepository,
  selections : ReadOnlyArray[RemoveSkillSelection],
) -> LockRepository? raise RemoveError {
  let plugins = []
  for entry in repository.plugins.to_array() {
    let plugin = entry.1
    let selected = selections.filter(selection => {
      selection.plugin_name == plugin.name
    })
    if selected.length() == 0 {
      plugins.push(plugin)
    } else {
      let remaining_skills = plugin.enabled_skills
        .iter()
        .filter(skill => {
          !selected.any(selection => selection.skill_name == skill)
        })
        .to_array()
      if remaining_skills.length() > 0 {
        plugins.push(
          Plugin::Plugin(plugin.name, plugin.path, remaining_skills) catch {
            error => raise InvalidInput(reason=error.to_string())
          },
        )
      }
    }
  }
  guard plugins.length() > 0 else { return None }
  let updated = LocalLockRepository::LocalLockRepository(
    repository.path,
    repository.marketplace_kind,
    plugins,
  ) catch {
    error => raise InvalidInput(reason=error.to_string())
  }
  Some(LockRepository::from_local(updated))
}

///|
fn build_remove_candidate(
  current_lock : Lock,
  selections : ReadOnlyArray[RemoveSkillSelection],
) -> Lock? raise RemoveError {
  guard selections.length() > 0 else { return None }
  for selection in selections {
    guard remove_selection_exists(current_lock, selection) else { return None }
  }
  let repositories = []
  for entry in current_lock.repositories.to_array() {
    let selected = selections.filter(selection => {
      selection.repository == entry.0
    })
    if selected.length() == 0 {
      repositories.push(entry.1)
    } else {
      match entry.1 {
        Local(repository) =>
          match rebuild_local_repository_after_remove(repository, selected) {
            Some(repository) => repositories.push(repository)
            None => ()
          }
        GitHub(repository) =>
          repositories.push(LockRepository::github(repository))
      }
    }
  }
  let candidate = Lock::Lock(
    current_lock.targets.iter().to_array(),
    repositories,
  ) catch {
    error => raise InvalidInput(reason=error.to_string())
  }
  Some(candidate)
}

///|
async fn remove_skills(
  runtime : Runtime,
  options : RemoveOptions,
) -> RemoveResult raise RemoveError {
  let discovery_options = if options.global {
    LockDiscoveryOptions::Global
  } else {
    LockDiscoveryOptions::Project(recursive=false)
  }
  let lock_paths = runtime.discover_locks(discovery_options) catch {
    error => raise Discovery(cause=error)
  }
  guard lock_paths.length() == 1 else {
    raise InvalidInput(reason="remove requires exactly one lock file")
  }
  let lock_path = lock_paths[0]
  let current_lock = runtime.load_lock(lock_path) catch {
    error => raise Store(cause=error)
  }
  let candidate = build_remove_candidate(current_lock, options.selections)
  let mut sync_result : SyncLockResult? = None
  let result = persist_and_sync(
    current_lock~,
    candidate~,
    persist=lock => runtime.write_lock_atomic(lock_path, lock),
    sync=lock => {
      try {
        sync_result = Some(sync_loaded_lock(runtime, lock_path, lock))
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
    NoChange => Unchanged(lock_path~)
    PersistedButSyncFailed(cause~) => raise SyncAfterPersist(cause~)
    Synced =>
      match sync_result {
        Some(sync_result) =>
          Removed(selections=options.selections, sync_result~)
        None =>
          raise InvalidInput(reason="remove sync completed without a result")
      }
  }
}

///|
async fn run_remove(runtime : Runtime, context : @admiral.Context) -> Unit {
  match remove_skills(runtime, remove_options(context)) {
    Unchanged(lock_path~) => println("No skill changes for \{lock_path}")
    Removed(selections~, sync_result~) => {
      let selected = selections.map(remove_skill_selection_text).join(", ")
      println(
        "Removed skills \{selected} from \{sync_result.lock_path}: \{sync_status_text(sync_result.reconciliation.status)} (\{sync_result.reconciliation.notices.length()} notices, \{sync_result.unavailable_repositories.length()} unavailable repositories)",
      )
    }
  }
}

///|
fn remove_command_def(
  run : async (@admiral.Context) -> Unit,
) -> @admiral.CommandDef {
  @admiral.CommandDef::CommandDef(
    name="remove",
    description="Remove installed local skills",
    options=[remove_global_option, remove_skill_option],
    run=Some(run),
  )
}
