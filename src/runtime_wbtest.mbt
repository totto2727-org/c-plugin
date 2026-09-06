///|
async test "Runtime discover_locks - injects synthetic runtime paths" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home", "/synthetic/work/project", "/synthetic/cache",
  )
  let lock = Lock::Lock([], [])
  let ownership_state = OwnershipState::OwnershipState([])
  let mut received = []
  let runtime = Runtime::Runtime(
    paths~,
    discover_locks_api=fn(runtime_paths, _options) {
      received = [
        runtime_paths.home.path,
        runtime_paths.cwd.path,
        runtime_paths.cache_root.path,
      ]
      ReadOnlyArray::from_array([
        runtime_paths.cwd.path.join("c-plugin-lock.json"),
      ])
    },
    load_lock=fn(_path) { lock },
    create_lock_exclusive=fn(_path, _lock) { () },
    write_lock_atomic=fn(_path, _lock) { () },
    load_ownership_state=fn(_path) { ownership_state },
    write_ownership_state_atomic=fn(_path, _state) { () },
  )

  let discovered = runtime.discover_locks(
    LockDiscoveryOptions::Project(recursive=false),
  )

  inspect(received[0].to_string(), content="/synthetic/home")
  inspect(received[1].to_string(), content="/synthetic/work/project")
  inspect(received[2].to_string(), content="/synthetic/cache")
  inspect(
    discovered[0].to_string(),
    content="/synthetic/work/project/c-plugin-lock.json",
  )
  inspect(
    runtime.project_lock_path().to_string(),
    content="/synthetic/work/project/c-plugin-lock.json",
  )
  inspect(
    runtime.global_lock_path().to_string(),
    content="/synthetic/home/c-plugin-lock.json",
  )
}

///|
async test "Runtime storage callbacks - forward synthetic paths and typed values" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home", "/synthetic/work/project", "/synthetic/cache",
  )
  let lock = Lock::Lock([], [])
  let ownership_state = OwnershipState::OwnershipState([])
  let lock_path : @path.Path = "/synthetic/work/project/c-plugin-lock.json"
  let ownership_path : @path.Path = "/synthetic/work/project/.agents/c-plugin-state.json"
  let mut received_paths = []
  let mut received_lock = None
  let mut received_ownership_state = None
  let runtime = Runtime::Runtime(
    paths~,
    discover_locks_api=fn(_paths, _options) { ReadOnlyArray::from_array([]) },
    load_lock=fn(path) {
      received_paths = [..received_paths, path]
      lock
    },
    create_lock_exclusive=fn(path, received) {
      received_paths = [..received_paths, path]
      received_lock = Some(received)
    },
    write_lock_atomic=fn(path, received) {
      received_paths = [..received_paths, path]
      received_lock = Some(received)
    },
    load_ownership_state=fn(path) {
      received_paths = [..received_paths, path]
      ownership_state
    },
    write_ownership_state_atomic=fn(path, received) {
      received_paths = [..received_paths, path]
      received_ownership_state = Some(received)
    },
  )

  let loaded_lock = runtime.load_lock(lock_path)
  runtime.create_lock_exclusive(lock_path, lock)
  runtime.write_lock_atomic(lock_path, lock)
  let loaded_ownership_state = runtime.load_ownership_state(ownership_path)
  runtime.write_ownership_state_atomic(ownership_path, ownership_state)

  assert_true(loaded_lock == lock)
  assert_true(loaded_ownership_state == ownership_state)
  assert_true(received_lock == Some(lock))
  assert_true(received_ownership_state == Some(ownership_state))
  inspect(received_paths.length(), content="5")
  inspect(
    received_paths[0].to_string(),
    content="/synthetic/work/project/c-plugin-lock.json",
  )
  inspect(
    received_paths[3].to_string(),
    content="/synthetic/work/project/.agents/c-plugin-state.json",
  )
}
