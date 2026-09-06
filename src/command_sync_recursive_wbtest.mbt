///|
fn recursive_sync_test_cli(runtime : Runtime) -> @admiral.CliApp {
  @admiral.CliApp::CliApp(name="c-plugin", version="test", description="test", commands=[
    @admiral.CommandDef::CommandDef(name="skill", subcommands=[
      sync_command_def(async fn(context) { run_sync(runtime, context) }),
    ]),
  ])
}

///|
async test "Sync command recursive 1 - routes the short recursive option to recursive project discovery" {
  with_sync_test_runtime(async fn(_fixture_runtime, root) {
    let paths = RuntimePaths::RuntimePaths(
      root.join("home"),
      root.join("project"),
      root.join("cache"),
    )
    let empty_lock = Lock::Lock([], [])
    let project_lock = paths.project_lock_path(paths.cwd.path)
    let mut discovered_options = None
    let runtime = Runtime::Runtime(
      paths~,
      discover_locks_api=(_paths, options) => {
        discovered_options = Some(options)
        ReadOnlyArray::from_array([project_lock])
      },
      load_lock=_path => empty_lock,
      create_lock_exclusive~,
      write_lock_atomic~,
      load_ownership_state=path => raise StateStoreError::NotFound(path~),
      write_ownership_state_atomic~,
    )

    recursive_sync_test_cli(runtime).run(
      argv=Some(["skill", "sync", "-r"]),
      env=Map([]),
    )

    debug_inspect(discovered_options, content="Some(Project(recursive=true))")
  })
}

///|
async test "Sync command recursive 2 - rejects global recursive sync before discovery" {
  with_sync_test_runtime(async fn(_fixture_runtime, root) {
    let paths = RuntimePaths::RuntimePaths(
      root.join("home"),
      root.join("project"),
      root.join("cache"),
    )
    let mut discovery_called = false
    let runtime = Runtime::Runtime(
      paths~,
      discover_locks_api=(_paths, _options) => {
        discovery_called = true
        ReadOnlyArray::from_array([])
      },
      load_lock~,
      create_lock_exclusive~,
      write_lock_atomic~,
      load_ownership_state~,
      write_ownership_state_atomic~,
    )

    try
      recursive_sync_test_cli(runtime).run(
        argv=Some(["skill", "sync", "-g", "-r"]),
        env=Map([]),
      )
    catch {
      SyncError::Planning(reason~) =>
        inspect(reason, content="--global cannot be combined with --recursive")
      _ => fail("expected recursive global validation error")
    } noraise {
      _ => fail("recursive global sync must fail")
    }
    inspect(discovery_called, content="false")
  })
}

///|
async test "Sync command recursive 3 - keeps completed lock ownership isolated when a later lock fails" {
  with_sync_test_runtime(async fn(_fixture_runtime, root) {
    let paths = RuntimePaths::RuntimePaths(
      root.join("home"),
      root.join("project"),
      root.join("cache"),
    )
    let project = paths.cwd.path
    create_sync_marketplace(project.join("marketplace"))
    let parent_lock_path = project.join("c-plugin-lock.json")
    let child_lock_path = project.join("child").join("c-plugin-lock.json")
    create_lock_exclusive(parent_lock_path, sync_test_lock(["alpha"]))
    let parent_state_path = project.join(".agents").join("c-plugin-state.json")
    let child_state_path = child_lock_path
      .dirname()
      .join(".agents")
      .join("c-plugin-state.json")
    let foreign = project.join(".agents").join("skills").join("foreign")
    @fs.mkdir(foreign.dirname().to_string(), recursive=true)
    @fs.write_file(foreign.to_string(), "foreign\n", create_mode=CreateNew)
    let mut discovered_options = None
    let runtime = Runtime::Runtime(
      paths~,
      discover_locks_api=(_paths, options) => {
        discovered_options = Some(options)
        ReadOnlyArray::from_array([parent_lock_path, child_lock_path])
      },
      load_lock=path => {
        if path == child_lock_path {
          raise StateStoreError::Decode(path~, reason="invalid child lock")
        }
        load_lock(path)
      },
      create_lock_exclusive~,
      write_lock_atomic~,
      load_ownership_state~,
      write_ownership_state_atomic~,
    )

    try
      sync_locks(runtime, { global: false, recursive: true }) |> ignore
    catch {
      SyncError::Store(
        cause=StateStoreError::Decode(path~, reason="invalid child lock")
      ) => inspect(path == child_lock_path, content="true")
      _ => fail("expected child lock decode failure")
    } noraise {
      _ => fail("recursive sync must report the child failure")
    }

    debug_inspect(discovered_options, content="Some(Project(recursive=true))")
    inspect(@fs.exists(parent_state_path.to_string()), content="true")
    inspect(@fs.exists(child_state_path.to_string()), content="false")
    inspect(@fs.read_file(foreign.to_string()).text(), content="foreign\n")
    debug_inspect(
      @fs.kind(
        project.join(".agents").join("skills").join("alpha").to_string(),
        follow_symlink=false,
      ),
      content="SymLink",
    )
  })
}
