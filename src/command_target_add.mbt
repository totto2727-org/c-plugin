///|
let target_add_global_option : @admiral.OptionDef[Bool] = @admiral.bool(
  "global",
  short='g',
  description="Use the user-level lock file",
)

///|
let target_add_path_argument : @admiral.PositionDef[String] = @admiral.position_string(
  "path",
  description="Additional skill-link root relative to the lock file",
)

///|
struct TargetAddOptions {
  global : Bool
  target : Target
}

///|
enum TargetAddResult {
  Added(target~ : Target, sync_result~ : SyncLockResult)
  AlreadyPresent(target~ : Target, lock_path~ : @path.Path)
}

///|
pub(all) suberror TargetAddError {
  Discovery(cause~ : LockDiscoveryError)
  Store(cause~ : StateStoreError)
  InvalidInput(reason~ : String)
  SyncAfterPersist(cause~ : SyncError)
} derive(Debug)

///|
fn target_add_options(context : @admiral.Context) -> TargetAddOptions raise {
  let path : @path.Path = context.get_string_required(target_add_path_argument)
  let target = Target::Target(path) catch {
    error => raise TargetAddError::InvalidInput(reason=error.to_string())
  }
  { global: context.get_bool(target_add_global_option), target }
}

///|
fn target_add_discovery_options(global : Bool) -> LockDiscoveryOptions {
  if global {
    LockDiscoveryOptions::Global
  } else {
    LockDiscoveryOptions::Project(recursive=false)
  }
}

///|
fn build_target_add_candidate(
  current_lock : Lock,
  target : Target,
) -> Lock raise TargetAddError {
  let targets = current_lock.targets.add(target).iter().to_array()
  let repositories = current_lock.repositories.to_array().map(entry => entry.1)
  Lock::Lock(targets, repositories) catch {
    error => raise InvalidInput(reason=error.to_string())
  }
}

///|
async fn target_add(
  runtime : Runtime,
  options : TargetAddOptions,
) -> TargetAddResult raise TargetAddError {
  let lock_paths = runtime.discover_locks(
    target_add_discovery_options(options.global),
  ) catch {
    error => raise Discovery(cause=error)
  }
  guard lock_paths.length() == 1 else {
    raise InvalidInput(reason="target add requires exactly one lock file")
  }
  let lock_path = lock_paths[0]
  let current_lock = runtime.load_lock(lock_path) catch {
    error => raise Store(cause=error)
  }
  let candidate = build_target_add_candidate(current_lock, options.target)
  let mut sync_result : SyncLockResult? = None
  let result = persist_and_sync(
    current_lock~,
    candidate=Some(candidate),
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
    NoChange => AlreadyPresent(target=options.target, lock_path~)
    PersistedButSyncFailed(cause~) => raise SyncAfterPersist(cause~)
    Synced =>
      match sync_result {
        Some(sync_result) => Added(target=options.target, sync_result~)
        None =>
          raise InvalidInput(
            reason="target add sync completed without a result",
          )
      }
  }
}

///|
async fn run_target_add(runtime : Runtime, context : @admiral.Context) -> Unit {
  match target_add(runtime, target_add_options(context)) {
    AlreadyPresent(target~, lock_path~) =>
      println(
        "Target \{@x_path.Path::to_string(target.path)} already registered in \{lock_path}",
      )
    Added(target~, sync_result~) =>
      println(
        "Added target \{@x_path.Path::to_string(target.path)} to \{sync_result.lock_path}: \{sync_status_text(sync_result.reconciliation.status)} (\{sync_result.reconciliation.notices.length()} notices, \{sync_result.unavailable_repositories.length()} unavailable repositories)",
      )
  }
}

///|
fn target_add_command_def(
  run : async (@admiral.Context) -> Unit,
) -> @admiral.CommandDef {
  @admiral.CommandDef::CommandDef(
    name="add",
    description="Add an additional skill-link root",
    positionals=[target_add_path_argument],
    options=[target_add_global_option],
    run=Some(run),
  )
}

///|
fn target_command_def(
  run_add : async (@admiral.Context) -> Unit,
  run_remove : async (@admiral.Context) -> Unit,
) -> @admiral.CommandDef {
  @admiral.CommandDef::CommandDef(
    name="target",
    description="Manage additional skill-link roots",
    subcommands=[
      target_add_command_def(run_add),
      target_remove_command_def(run_remove),
    ],
  )
}
