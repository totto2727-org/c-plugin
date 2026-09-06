///|
let sync_global_option : @admiral.OptionDef[Bool] = @admiral.bool(
  "global",
  short='g',
  description="Use the user-level lock file",
)

///|
let sync_recursive_option : @admiral.OptionDef[Bool] = @admiral.bool(
  "recursive",
  short='r',
  description="Sync the nearest project lock and visible descendants",
)

///|
struct SyncOptions {
  global : Bool
  recursive : Bool
}

///|
fn sync_options(
  context : @admiral.Context,
) -> SyncOptions raise @json.JsonDecodeError {
  {
    global: context.get_bool(sync_global_option),
    recursive: context.get_bool(sync_recursive_option),
  }
}

///|
pub(all) suberror SyncError {
  Store(cause~ : StateStoreError)
  InvalidPath(path~ : @path.Path, reason~ : String)
  Planning(reason~ : String)
} derive(Debug)

///|
struct SyncLockResult {
  lock_path : @path.Path
  reconciliation : LinkReconciliationResult
  unavailable_repositories : @immut_hashmap.HashMap[
    RepositoryIdentity,
    RepositoryUnavailable,
  ]
}

///|
async fn sync_lock(runtime : Runtime, lock_path : @path.Path) -> SyncLockResult {
  let lock = runtime.load_lock(lock_path) catch {
    error => raise SyncError::Store(cause=error)
  }
  sync_loaded_lock(runtime, lock_path, lock)
}

///|
async fn sync_loaded_lock(
  runtime : Runtime,
  lock_path : @path.Path,
  lock : Lock,
  collision_policy? : DesiredLinkCollisionPolicy = PreserveExisting,
) -> SyncLockResult {
  let repositories = resolve_repositories_for_sync(lock_path, lock) catch {
    DuplicateRepositoryIdentity(_) =>
      raise Planning(reason="duplicate repository identity in lock")
    error => raise Planning(reason=error.to_string())
  }
  let managed_roots = managed_skill_roots_for_sync(lock_path, lock) catch {
    error => raise InvalidPath(path=lock_path, reason=error.to_string())
  }
  validate_managed_roots_for_sync(lock_path.dirname(), managed_roots)
  let plan = plan_desired_skill_links(managed_roots, repositories) catch {
    error => raise Planning(reason=error.to_string())
  }
  let state_path = ownership_state_path_for_sync(lock_path) catch {
    error => raise InvalidPath(path=lock_path, reason=error.to_string())
  }
  let loaded_ownership = load_previous_ownership_for_sync(runtime, state_path)
  let validated_ownership = validate_previous_ownership_for_sync(
    lock_path.dirname(),
    loaded_ownership,
  )
  let (previous_ownership, preserved_entries) = split_unavailable_ownership_for_sync(
    validated_ownership,
    plan.unavailable_repositories,
  )
  let checkpoint_ownership_state : async (@path.Path, OwnershipState) -> Unit raise StateStoreError = (
    path,
    state,
  ) => {
    runtime.write_ownership_state_atomic(
      path,
      merge_preserved_ownership_for_sync(state, preserved_entries),
    )
  }
  let reconciled = reconcile_skill_links(
    state_path~,
    desired_state=plan.ownership_state,
    previous_ownership~,
    collision_policy~,
    checkpoint_ownership_state~,
  ) catch {
    error => raise Planning(reason=error.to_string())
  }
  let reconciliation = LinkReconciliationResult::{
    status: reconciled.status,
    durable_state: merge_preserved_ownership_for_sync(
      reconciled.durable_state,
      preserved_entries,
    ),
    notices: reconciled.notices,
  }
  {
    lock_path,
    reconciliation,
    unavailable_repositories: plan.unavailable_repositories,
  }
}

///|
async fn sync_locks(
  runtime : Runtime,
  options : SyncOptions,
) -> ReadOnlyArray[SyncLockResult] {
  guard !(options.global && options.recursive) else {
    raise SyncError::Planning(
      reason="--global cannot be combined with --recursive",
    )
  }
  let discovery_options = if options.global {
    LockDiscoveryOptions::Global
  } else {
    LockDiscoveryOptions::Project(recursive=options.recursive)
  }
  let lock_paths = runtime.discover_locks(discovery_options)
  let results = []
  for lock_path in lock_paths {
    results.push(sync_lock(runtime, lock_path))
  }
  ReadOnlyArray::from_array(results)
}

///|
fn sync_status_text(status : LinkReconciliationStatus) -> String {
  match status {
    Complete => "complete"
    Partial => "partial"
  }
}

///|
async fn run_sync(runtime : Runtime, context : @admiral.Context) -> Unit {
  let results = sync_locks(runtime, sync_options(context))
  for result in results {
    println(
      "Synced \{result.lock_path}: \{sync_status_text(result.reconciliation.status)} (\{result.reconciliation.notices.length()} notices, \{result.unavailable_repositories.length()} unavailable repositories)",
    )
  }
}

///|
fn sync_command_def(
  run : async (@admiral.Context) -> Unit,
) -> @admiral.CommandDef {
  @admiral.CommandDef::CommandDef(
    name="sync",
    description="Reconcile managed skill links from the lock file",
    options=[sync_global_option, sync_recursive_option],
    run=Some(run),
  )
}
