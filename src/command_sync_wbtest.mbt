///|
async fn with_sync_test_runtime(
  body : async (Runtime, @path.Path) -> Unit,
) -> Unit {
  @async.with_task_group() <| group => {
    let temporary_root : @path.Path = @fs.tmpdir(prefix="c-plugin-sync-")
    group.add_defer(() => @fs.rmdir(temporary_root.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary_root.to_string())
    let home = root.join("home")
    let project = root.join("project")
    let cache_root = root.join("cache")
    @fs.mkdir(home.to_string(), recursive=true)
    @fs.mkdir(project.to_string(), recursive=true)
    @fs.mkdir(cache_root.to_string(), recursive=true)
    let runtime = runtime_for_init(
      RuntimePaths::RuntimePaths(home, project, cache_root),
    )
    body(runtime, root)
  }
}

///|
async fn create_sync_marketplace(repository_root : @path.Path) -> Unit {
  let manifest_path = repository_root
    .join(".claude-plugin")
    .join("marketplace.json")
  @fs.mkdir(manifest_path.dirname().to_string(), recursive=true)
  let manifest =
    #|{"name":"fixture","plugins":[{"name":"demo","source":"plugins/demo"}]}
  @fs.write_file(manifest_path.to_string(), manifest, create_mode=CreateNew)
  for skill in ["alpha", "beta"] {
    let skill_root = repository_root
      .join("plugins")
      .join("demo")
      .join("skills")
      .join(skill)
    @fs.mkdir(skill_root.to_string(), recursive=true)
    @fs.write_file(
      skill_root.join("SKILL.md").to_string(),
      "# \{skill}\n",
      create_mode=CreateNew,
    )
  }
}

///|
fn sync_test_lock(enabled_skills : Array[String]) -> Lock raise {
  let plugin = Plugin::Plugin(
    PluginName::PluginName("demo"),
    RelativePluginPath::RelativePluginPath("plugins/demo"),
    enabled_skills.map(skill => SkillName::SkillName(skill)),
  )
  let repository = LocalLockRepository::LocalLockRepository(
    RelativeSourcePath::RelativeSourcePath("marketplace"),
    MarketplaceKind::claude(),
    [plugin],
  )
  Lock::Lock([Target::Target(".cursor/skills")], [
    LockRepository::from_local(repository),
  ])
}

///|
async test "Sync sync_lock 1 - reconciles local links and preserves foreign replacements after an external lock edit" {
  with_sync_test_runtime(async fn(runtime, root) {
    let project = root.join("project")
    let repository_root = project.join("marketplace")
    create_sync_marketplace(repository_root)
    let lock_path = project.join("c-plugin-lock.json")
    let initial_lock = sync_test_lock(["alpha", "beta"])
    runtime.create_lock_exclusive(lock_path, initial_lock)
    let initial_bytes = @fs.read_file(lock_path.to_string()).text()

    let first = sync_lock(runtime, lock_path)

    debug_inspect(first.reconciliation.status, content="Partial")
    inspect(first.reconciliation.notices.length(), content="1")
    inspect(first.unavailable_repositories.length(), content="0")
    inspect(@fs.read_file(lock_path.to_string()).text(), content=initial_bytes)

    let repeated = sync_lock(runtime, lock_path)

    debug_inspect(repeated.reconciliation.status, content="Complete")
    inspect(repeated.reconciliation.notices.length(), content="0")
    inspect(
      repeated.reconciliation.durable_state ==
      first.reconciliation.durable_state,
      content="true",
    )
    inspect(@fs.read_file(lock_path.to_string()).text(), content=initial_bytes)
    for
      target_root in [
        project.join(".agents").join("skills"),
        project.join(".cursor").join("skills"),
      ] {
      for skill in ["alpha", "beta"] {
        let link = target_root.join(skill)
        debug_inspect(
          @fs.kind(link.to_string(), follow_symlink=false),
          content="SymLink",
        )
        inspect(
          @fs.realpath(link.to_string()),
          content=@fs.realpath(
            repository_root
            .join("plugins")
            .join("demo")
            .join("skills")
            .join(skill)
            .to_string(),
          ),
        )
      }
    }

    let primary_root = project.join(".agents").join("skills")
    let replaced_beta = primary_root.join("beta")
    @fs.remove(replaced_beta.to_string())
    @fs.write_file(
      replaced_beta.to_string(),
      "foreign\n",
      create_mode=CreateNew,
    )
    let neighbor = primary_root.join("neighbor")
    @fs.write_file(neighbor.to_string(), "neighbor\n", create_mode=CreateNew)
    let edited_lock = sync_test_lock([])
    runtime.write_lock_atomic(lock_path, edited_lock)

    let second = sync_lock(runtime, lock_path)

    debug_inspect(second.reconciliation.status, content="Partial")
    inspect(second.reconciliation.durable_state.entries.length(), content="0")
    inspect(@fs.exists(primary_root.join("alpha").to_string()), content="false")
    inspect(
      @fs.read_file(replaced_beta.to_string()).text(),
      content="foreign\n",
    )
    inspect(@fs.read_file(neighbor.to_string()).text(), content="neighbor\n")
    inspect(load_lock(lock_path) == edited_lock, content="true")
  })
}

///|
async test "Sync sync_lock 2 - rebuilds ownership conservatively from corrupt state" {
  with_sync_test_runtime(async fn(runtime, root) {
    let project = root.join("project")
    create_sync_marketplace(project.join("marketplace"))
    let lock_path = project.join("c-plugin-lock.json")
    runtime.create_lock_exclusive(lock_path, sync_test_lock(["alpha"]))
    let state_path = project.join(".agents").join("c-plugin-state.json")
    @fs.mkdir(state_path.dirname().to_string(), recursive=true)
    @fs.write_file(state_path.to_string(), "{not-json\n", create_mode=CreateNew)

    let result = sync_lock(runtime, lock_path)

    debug_inspect(result.reconciliation.status, content="Partial")
    inspect(result.reconciliation.notices.length(), content="1")
    match result.reconciliation.notices[0] {
      PreviousOwnershipCorrupt(path~, reason=_) =>
        inspect(path.path.path == state_path, content="true")
      _ => fail("expected PreviousOwnershipCorrupt")
    }
    inspect(result.reconciliation.durable_state.entries.length(), content="2")
    inspect(
      load_ownership_state(state_path) == result.reconciliation.durable_state,
      content="true",
    )
  })
}

///|
async test "Sync sync_lock 3 - preserves trusted links for unavailable repositories" {
  with_sync_test_runtime(async fn(runtime, root) {
    let project = root.join("project")
    create_sync_marketplace(project.join("marketplace"))
    let lock_path = project.join("c-plugin-lock.json")
    let repository = GitHubRepository::from_route("openai/codex")
    let plugin = Plugin::Plugin(
      PluginName::PluginName("demo"),
      RelativePluginPath::RelativePluginPath("plugins/demo"),
      [SkillName::SkillName("alpha")],
    )
    let github = GitHubLockRepository::GitHubLockRepository(
      repository,
      MarketplaceKind::codex(),
      CommitId::CommitId("0123456789abcdef0123456789abcdef01234567"),
      [plugin],
    )
    runtime.create_lock_exclusive(
      lock_path,
      Lock::Lock([], [
        LockRepository::github(github),
        sync_test_lock(["beta"]).repositories.to_array()[0].1,
      ]),
    )
    let managed_root = project.join(".agents").join("skills")
    let target = root.join("cache").join("github-alpha")
    let link = managed_root.join("alpha")
    @fs.mkdir(managed_root.to_string(), recursive=true)
    @fs.mkdir(target.to_string(), recursive=true)
    @fs.symlink(target=target.to_string(), link.to_string())
    let entry = OwnershipEntry::OwnershipEntry(
      OwnershipLink::OwnershipLink(link),
      target.relative(base=managed_root),
      OwnershipResolvedTarget::OwnershipResolvedTarget(target),
      OwnershipManagedRoot::OwnershipManagedRoot(managed_root),
      OwnershipSource::from_github(
        GitHubOwnershipSource::GitHubOwnershipSource(
          repository,
          PluginName::PluginName("demo"),
          SkillName::SkillName("alpha"),
        ),
      ),
    )
    let state = OwnershipState::OwnershipState([entry])
    let state_path = project.join(".agents").join("c-plugin-state.json")
    runtime.write_ownership_state_atomic(state_path, state)

    let result = sync_lock(runtime, lock_path)

    inspect(result.unavailable_repositories.length(), content="1")
    inspect(result.reconciliation.durable_state.entries.length(), content="2")
    debug_inspect(
      @fs.kind(link.to_string(), follow_symlink=false),
      content="SymLink",
    )
    inspect(@fs.realpath(link.to_string()), content=target.to_string())
    let local_link = managed_root.join("beta")
    debug_inspect(
      @fs.kind(local_link.to_string(), follow_symlink=false),
      content="SymLink",
    )
    inspect(
      load_ownership_state(state_path) == result.reconciliation.durable_state,
      content="true",
    )
  })
}

///|
async test "Sync sync_lock 4 - rejects a target whose ancestor is a symlink" {
  with_sync_test_runtime(async fn(runtime, root) {
    let project = root.join("project")
    let outside = root.join("outside")
    @fs.mkdir(outside.to_string(), recursive=true)
    @fs.symlink(target=outside.to_string(), project.join("escaped").to_string())
    let lock_path = project.join("c-plugin-lock.json")
    runtime.create_lock_exclusive(
      lock_path,
      Lock::Lock([Target::Target("escaped/skills")], []),
    )

    try sync_lock(runtime, lock_path) |> ignore catch {
      SyncError::InvalidPath(path=_, reason=_) => ()
      _ => fail("expected InvalidPath")
    } noraise {
      _ => fail("symlinked target ancestor must fail")
    }
    inspect(@fs.exists(outside.join("skills").to_string()), content="false")
    inspect(
      @fs.exists(
        project.join(".agents").join("c-plugin-state.json").to_string(),
      ),
      content="false",
    )
  })
}

///|
async test "Sync sync_lock 5 - distrusts ownership roots outside the lock scope" {
  with_sync_test_runtime(async fn(runtime, root) {
    let project = root.join("project")
    let lock_path = project.join("c-plugin-lock.json")
    runtime.create_lock_exclusive(lock_path, Lock::Lock([], []))
    let managed_root = root.join("outside-owned")
    let target = root.join("outside-target")
    let link = managed_root.join("foreign-link")
    @fs.mkdir(managed_root.to_string(), recursive=true)
    @fs.mkdir(target.to_string(), recursive=true)
    @fs.symlink(target=target.to_string(), link.to_string())
    let entry = OwnershipEntry::OwnershipEntry(
      OwnershipLink::OwnershipLink(link),
      target.relative(base=managed_root),
      OwnershipResolvedTarget::OwnershipResolvedTarget(target),
      OwnershipManagedRoot::OwnershipManagedRoot(managed_root),
      OwnershipSource::from_local(
        LocalOwnershipSource::LocalOwnershipSource(
          RelativeSourcePath::RelativeSourcePath("marketplace"),
          PluginName::PluginName("demo"),
          SkillName::SkillName("foreign-link"),
        ),
      ),
    )
    let state_path = project.join(".agents").join("c-plugin-state.json")
    runtime.write_ownership_state_atomic(
      state_path,
      OwnershipState::OwnershipState([entry]),
    )

    let result = sync_lock(runtime, lock_path)

    debug_inspect(result.reconciliation.status, content="Partial")
    match result.reconciliation.notices[0] {
      PreviousOwnershipCorrupt(path~, reason=_) =>
        inspect(path.path.path == state_path, content="true")
      _ => fail("expected unsafe ownership to become corrupt")
    }
    debug_inspect(
      @fs.kind(link.to_string(), follow_symlink=false),
      content="SymLink",
    )
    inspect(@fs.realpath(link.to_string()), content=target.to_string())
  })
}

///|
async test "Sync command 1 - routes the short global option to global discovery" {
  with_sync_test_runtime(async fn(_fixture_runtime, root) {
    let paths = RuntimePaths::RuntimePaths(
      root.join("home"),
      root.join("project"),
      root.join("cache"),
    )
    let global_lock = paths.global_lock_path()
    let empty_lock = Lock::Lock([], [])
    let mut discovered_options = None
    let runtime = Runtime::Runtime(
      paths~,
      discover_locks_api=(_paths, options) => {
        discovered_options = Some(options)
        ReadOnlyArray::from_array([global_lock])
      },
      load_lock=_path => empty_lock,
      create_lock_exclusive~,
      write_lock_atomic~,
      load_ownership_state=path => raise StateStoreError::NotFound(path~),
      write_ownership_state_atomic~,
    )
    let cli = @admiral.CliApp::CliApp(
      name="c-plugin",
      version="test",
      description="test",
      commands=[
        @admiral.CommandDef::CommandDef(name="skill", subcommands=[
          sync_command_def(async fn(context) { run_sync(runtime, context) }),
        ]),
      ],
    )

    cli.run(argv=Some(["skill", "sync", "-g"]), env=Map([]))

    debug_inspect(discovered_options, content="Some(Global)")
  })
}
