///|
async fn with_init_test_runtime(
  body : async (Runtime, @path.Path) -> Unit,
) -> Unit {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-init-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let home = root.join("home")
    let cwd = root.join("project")
    let cache_root = root.join("cache")
    @fs.mkdir(home.to_string(), recursive=true)
    @fs.mkdir(cwd.to_string(), recursive=true)
    @fs.mkdir(cache_root.to_string(), recursive=true)
    let runtime = runtime_for_init(
      RuntimePaths::RuntimePaths(home, cwd, cache_root),
    )
    body(runtime, root)
  }
}

///|
fn init_command_test_runtime(
  paths : RuntimePaths,
  create_lock_exclusive : async (@path.Path, Lock) -> Unit raise StateStoreError,
) -> Runtime {
  Runtime::Runtime(
    paths~,
    discover_locks_api=discover_locks,
    load_lock~,
    create_lock_exclusive~,
    write_lock_atomic~,
    load_ownership_state~,
    write_ownership_state_atomic~,
  )
}

///|
async test "Init init_lock - creates the project lock in cwd" {
  with_init_test_runtime(async fn(runtime, root) {
    let lock_path = init_lock(runtime, { global: false })
    inspect(
      lock_path == root.join("project").join("c-plugin-lock.json"),
      content="true",
    )
    inspect(load_lock(lock_path) == Lock::Lock([], []), content="true")
    let original = @fs.read_file(lock_path.to_string()).text()
    inspect(original, content=Lock::Lock([], []).to_pretty_json())
    try init_lock(runtime, { global: false }) catch {
      StateStoreError::AlreadyExists(path=error_path) =>
        inspect(error_path == lock_path, content="true")
      _ => fail("expected AlreadyExists")
    } noraise {
      _ => fail("repeated init must fail")
    }
    inspect(@fs.read_file(lock_path.to_string()).text(), content=original)
  })
}

///|
async test "Init init_lock - creates the global lock in home" {
  with_init_test_runtime(async fn(runtime, root) {
    let lock_path = init_lock(runtime, { global: true })
    inspect(
      lock_path == root.join("home").join("c-plugin-lock.json"),
      content="true",
    )
    inspect(load_lock(lock_path) == Lock::Lock([], []), content="true")
  })
}

///|
async test "Init init_lock - rejects an invalid existing lock without changing bytes" {
  with_init_test_runtime(async fn(runtime, root) {
    let lock_path = root.join("project").join("c-plugin-lock.json")
    let original = "existing bytes\n"
    @fs.write_file(lock_path.to_string(), original, create_mode=CreateNew)
    try init_lock(runtime, { global: false }) catch {
      StateStoreError::AlreadyExists(path=error_path) =>
        inspect(error_path == lock_path, content="true")
      _ => fail("expected AlreadyExists")
    } noraise {
      _ => fail("existing lock must fail")
    }
    inspect(@fs.read_file(lock_path.to_string()).text(), content=original)
  })
}

///|
async test "Init command - routes the short global option to the home lock" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home", "/synthetic/project", "/synthetic/cache",
  )
  let mut created_path = None
  let runtime = init_command_test_runtime(paths, fn(path, _lock) {
    created_path = Some(path)
  })
  let cli = @admiral.CliApp::CliApp(
    name="c-plugin",
    version="test",
    description="test",
    commands=[
      init_command_def(async fn(context) { run_init(runtime, context) }),
    ],
  )

  cli.run(argv=Some(["init", "-g"]), env=Map([]))

  debug_inspect(
    created_path,
    content="Some(Path(\"/synthetic/home/c-plugin-lock.json\"))",
  )
}

///|
async test "Init command - rejects an unknown option before lock creation" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home", "/synthetic/project", "/synthetic/cache",
  )
  let mut created_path = None
  let runtime = init_command_test_runtime(paths, fn(path, _lock) {
    created_path = Some(path)
  })
  let cli = @admiral.CliApp::CliApp(
    name="c-plugin",
    version="test",
    description="test",
    commands=[
      init_command_def(async fn(context) { run_init(runtime, context) }),
    ],
  )

  try cli.run(argv=Some(["init", "--unknown"]), env=Map([])) catch {
    _ => ()
  } noraise {
    _ => fail("unknown option must fail")
  }

  debug_inspect(created_path, content="None")
}
