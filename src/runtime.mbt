///|
/// Injectable composition root for runtime paths, persistence, and discovery.
pub struct Runtime {
  paths : RuntimePaths
  discover_locks_api : async (RuntimePaths, LockDiscoveryOptions) -> ReadOnlyArray[
    @path.Path,
  ] raise LockDiscoveryError
  load_lock : async (@path.Path) -> Lock raise StateStoreError
  create_lock_exclusive : async (@path.Path, Lock) -> Unit raise StateStoreError
  write_lock_atomic : async (@path.Path, Lock) -> Unit raise StateStoreError
  load_ownership_state : async (@path.Path) -> OwnershipState raise StateStoreError
  write_ownership_state_atomic : async (@path.Path, OwnershipState) -> Unit raise StateStoreError
}

///|
/// Create a runtime from explicit path, storage, and discovery callbacks.
pub fn Runtime::Runtime(
  paths~ : RuntimePaths,
  discover_locks_api~ : async (RuntimePaths, LockDiscoveryOptions) -> ReadOnlyArray[
    @path.Path,
  ] raise LockDiscoveryError,
  load_lock~ : async (@path.Path) -> Lock raise StateStoreError,
  create_lock_exclusive~ : async (@path.Path, Lock) -> Unit raise StateStoreError,
  write_lock_atomic~ : async (@path.Path, Lock) -> Unit raise StateStoreError,
  load_ownership_state~ : async (@path.Path) -> OwnershipState raise StateStoreError,
  write_ownership_state_atomic~ : async (@path.Path, OwnershipState) -> Unit raise StateStoreError,
) -> Runtime {
  {
    paths,
    discover_locks_api,
    load_lock,
    create_lock_exclusive,
    write_lock_atomic,
    load_ownership_state,
    write_ownership_state_atomic,
  }
}

///|
/// Return the lock path for the runtime working directory.
pub fn Runtime::project_lock_path(
  self : Runtime,
) -> @path.Path raise RuntimePathsError {
  self.paths.project_lock_path(self.paths.cwd.path)
}

///|
/// Return the lock path for the runtime home directory.
pub fn Runtime::global_lock_path(self : Runtime) -> @path.Path {
  self.paths.global_lock_path()
}

///|
/// Discover lock files with the injected runtime paths.
pub async fn Runtime::discover_locks(
  self : Runtime,
  options : LockDiscoveryOptions,
) -> ReadOnlyArray[@path.Path] raise LockDiscoveryError {
  (self.discover_locks_api)(self.paths, options)
}

///|
/// Load a lock through the injected state store.
pub async fn Runtime::load_lock(
  self : Runtime,
  path : @path.Path,
) -> Lock raise StateStoreError {
  (self.load_lock)(path)
}

///|
/// Exclusively create a lock through the injected state store.
pub async fn Runtime::create_lock_exclusive(
  self : Runtime,
  path : @path.Path,
  lock : Lock,
) -> Unit raise StateStoreError {
  (self.create_lock_exclusive)(path, lock)
}

///|
/// Atomically write a lock through the injected state store.
pub async fn Runtime::write_lock_atomic(
  self : Runtime,
  path : @path.Path,
  lock : Lock,
) -> Unit raise StateStoreError {
  (self.write_lock_atomic)(path, lock)
}

///|
/// Load ownership state through the injected state store.
pub async fn Runtime::load_ownership_state(
  self : Runtime,
  path : @path.Path,
) -> OwnershipState raise StateStoreError {
  (self.load_ownership_state)(path)
}

///|
/// Atomically write ownership state through the injected state store.
pub async fn Runtime::write_ownership_state_atomic(
  self : Runtime,
  path : @path.Path,
  state : OwnershipState,
) -> Unit raise StateStoreError {
  (self.write_ownership_state_atomic)(path, state)
}
