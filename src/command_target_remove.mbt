///|
let target_remove_global_option : @admiral.OptionDef[Bool] = @admiral.bool(
  "global",
  short='g',
  description="Use the user-level lock file",
)

///|
let target_remove_target_option : @admiral.OptionDef[Array[String]] = @admiral.strings(
  "target",
  description="Additional skill-link root to remove",
)

///|
struct TargetRemoveOptions {
  global : Bool
  targets : ReadOnlyArray[Target]
}

///|
enum TargetRemoveResult {
  Removed(targets~ : ReadOnlyArray[Target], sync_result~ : SyncLockResult)
  Unchanged(lock_path~ : @path.Path)
}

///|
pub(all) suberror TargetRemoveError {
  Discovery(cause~ : LockDiscoveryError)
  Store(cause~ : StateStoreError)
  InvalidInput(reason~ : String)
  SyncAfterPersist(cause~ : SyncError)
} derive(Debug)

///|
fn target_remove_options(
  context : @admiral.Context,
) -> TargetRemoveOptions raise {
  let targets = []
  for value in context.get_strings(target_remove_target_option) {
    let target = Target::Target(value) catch {
      error => raise TargetRemoveError::InvalidInput(reason=error.to_string())
    }
    targets.push(target)
  }
  {
    global: context.get_bool(target_remove_global_option),
    targets: ReadOnlyArray::from_array(targets),
  }
}

///|
fn target_remove_discovery_options(global : Bool) -> LockDiscoveryOptions {
  if global {
    LockDiscoveryOptions::Global
  } else {
    LockDiscoveryOptions::Project(recursive=false)
  }
}

///|
fn build_target_remove_candidate(
  current_lock : Lock,
  targets : ReadOnlyArray[Target],
) -> Lock? raise TargetRemoveError {
  guard targets.length() > 0 else { return None }
  for target in targets {
    guard current_lock.targets.contains(target) else { return None }
  }
  let remaining_targets = current_lock.targets
    .iter()
    .filter(target => !targets.contains(target))
    .to_array()
  let repositories = current_lock.repositories.to_array().map(entry => entry.1)
  let candidate = Lock::Lock(remaining_targets, repositories) catch {
    error => raise InvalidInput(reason=error.to_string())
  }
  Some(candidate)
}

///|
async fn target_remove(
  runtime : Runtime,
  options : TargetRemoveOptions,
) -> TargetRemoveResult raise TargetRemoveError {
  let lock_paths = runtime.discover_locks(
    target_remove_discovery_options(options.global),
  ) catch {
    error => raise Discovery(cause=error)
  }
  guard lock_paths.length() == 1 else {
    raise InvalidInput(reason="target remove requires exactly one lock file")
  }
  let lock_path = lock_paths[0]
  let current_lock = runtime.load_lock(lock_path) catch {
    error => raise Store(cause=error)
  }
  let candidate = build_target_remove_candidate(current_lock, options.targets)
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
        Some(sync_result) => Removed(targets=options.targets, sync_result~)
        None =>
          raise InvalidInput(
            reason="target remove sync completed without a result",
          )
      }
  }
}

///|
async fn run_target_remove(
  runtime : Runtime,
  context : @admiral.Context,
) -> Unit {
  match target_remove(runtime, target_remove_options(context)) {
    Unchanged(lock_path~) => println("No target changes for \{lock_path}")
    Removed(targets~, sync_result~) => {
      let paths = targets.map(target => target.path.to_string()).join(", ")
      println(
        "Removed targets \{paths} from \{sync_result.lock_path}: \{sync_status_text(sync_result.reconciliation.status)} (\{sync_result.reconciliation.notices.length()} notices, \{sync_result.unavailable_repositories.length()} unavailable repositories)",
      )
    }
  }
}

///|
fn target_remove_command_def(
  run : async (@admiral.Context) -> Unit,
) -> @admiral.CommandDef {
  @admiral.CommandDef::CommandDef(
    name="remove",
    description="Remove additional skill-link roots",
    options=[target_remove_global_option, target_remove_target_option],
    run=Some(run),
  )
}
