///|
fn add_local_test_marketplace() -> Marketplace raise {
  Marketplace::Marketplace("test", [
    MarketplacePlugin::MarketplacePlugin(
      PluginName::PluginName("demo"),
      RelativePluginPath::RelativePluginPath("plugins/demo"),
    ),
  ])
}

///|
fn add_local_test_resolved() -> ReadOnlyArray[ResolvedSkill] raise {
  [
    {
      plugin_name: PluginName::PluginName("demo"),
      plugin_path: RelativePluginPath::RelativePluginPath("plugins/demo"),
      skill_name: SkillName::SkillName("alpha"),
      skill_path: @x_path.AbsolutePath::AbsolutePath(
        "/marketplace/plugins/demo/skills/alpha",
      ),
    },
    {
      plugin_name: PluginName::PluginName("demo"),
      plugin_path: RelativePluginPath::RelativePluginPath("plugins/demo"),
      skill_name: SkillName::SkillName("beta"),
      skill_path: @x_path.AbsolutePath::AbsolutePath(
        "/marketplace/plugins/demo/skills/beta",
      ),
    },
  ]
}

///|
test "Add local candidate 1 - keeps only explicitly selected skills" {
  let candidate = build_local_add_candidate(
    Lock::Lock([], []),
    RelativeSourcePath::RelativeSourcePath("marketplace"),
    MarketplaceKind::claude(),
    add_local_test_marketplace(),
    add_local_test_resolved(),
    ["demo/beta"],
  )

  inspect(candidate.repositories.length(), content="1")
  let repository = candidate.repositories.to_array()[0].1
  match repository {
    Local(repository) => {
      inspect(repository.plugins.length(), content="1")
      let plugin = repository.plugins.to_array()[0].1
      inspect(
        plugin.enabled_skills.contains(SkillName::SkillName("beta")),
        content="true",
      )
      inspect(
        plugin.enabled_skills.contains(SkillName::SkillName("alpha")),
        content="false",
      )
    }
    _ => fail("expected local repository")
  }
}

///|
test "Add local candidate 2 - rejects unknown duplicate skill and repository identities" {
  let current = Lock::Lock([], [
    LockRepository::from_local(
      LocalLockRepository::LocalLockRepository(
        RelativeSourcePath::RelativeSourcePath("marketplace"),
        MarketplaceKind::claude(),
        [],
      ),
    ),
  ])
  let attempts : Array[(Lock, ReadOnlyArray[String], String)] = [
    (Lock::Lock([], []), ["demo/missing"], "unknown marketplace skill"),
    (
      Lock::Lock([], []),
      ["demo/alpha", "demo/alpha"],
      "plugin enabled skills must be unique",
    ),
    (current, ["demo/alpha"], "lock repositories must be unique"),
  ]
  for attempt in attempts {
    try
      build_local_add_candidate(
        attempt.0,
        RelativeSourcePath::RelativeSourcePath("marketplace"),
        MarketplaceKind::claude(),
        add_local_test_marketplace(),
        add_local_test_resolved(),
        attempt.1,
      )
      |> ignore
    catch {
      AddLocalError::InvalidInput(reason~) =>
        inspect(reason.contains(attempt.2), content="true")
      _ => fail("expected add input error")
    } noraise {
      _ => fail("invalid add candidate must fail")
    }
  }
}

///|
async test "Add local command 3 - resolves local root from project and global locks" {
  let mut captured = None
  let cli = @admiral.CliApp::CliApp(name="c-plugin", commands=[
    @admiral.CommandDef::CommandDef(name="skill", subcommands=[
      add_local_command_def(context => {
        captured = Some(add_local_options(context))
      }),
    ]),
  ])

  cli.run(
    argv=Some([
      "skill", "add", "--local", "./fixtures/../marketplace", "--kind", "claude",
      "--skill", "demo/alpha", "--skill", "demo/beta",
    ]),
    env=Map([]),
  )

  match captured {
    Some(options) => {
      inspect(options.source.path.to_string(), content="marketplace")
      inspect(
        resolve_add_repository_root(
          "/synthetic/project/c-plugin-lock.json",
          options.source,
        ).path.to_string(),
        content="/synthetic/project/marketplace",
      )
      inspect(
        resolve_add_repository_root(
          "/synthetic/home/c-plugin-lock.json",
          options.source,
        ).path.to_string(),
        content="/synthetic/home/marketplace",
      )
      inspect(options.kind == MarketplaceKind::claude(), content="true")
      debug_inspect(
        options.selections,
        content="<ReadOnlyArray: [\"demo/alpha\", \"demo/beta\"]>",
      )
    }
    None => fail("add command did not run")
  }
}

///|
async test "Add local command 4 - parses both force aliases" {
  for flag in ["-f", "--force"] {
    let mut captured : AddLocalOptions? = None
    let cli = @admiral.CliApp::CliApp(name="c-plugin", commands=[
      @admiral.CommandDef::CommandDef(name="skill", subcommands=[
        add_local_command_def(context => {
          captured = Some(add_local_options(context))
        }),
      ]),
    ])
    cli.run(
      argv=Some([
        "skill", "add", "--local", "./marketplace", "--kind", "claude", "--skill",
        "demo/alpha", flag,
      ]),
      env=Map([]),
    )
    match captured {
      Some(options) => inspect(options.force, content="true")
      None => fail("add command did not run")
    }
  }
}

///|
async fn assert_add_local_rejection_preserves_state(
  selections : ReadOnlyArray[String],
  force~ : Bool,
  check_reason~ : (String) -> Unit raise,
) -> Unit {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-add-rejection-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let home = root.join("home")
    let project = home.join("project")
    let repository = project.join("marketplace")
    let manifest = repository.join(".claude-plugin").join("marketplace.json")
    let skill = repository.join("plugins/demo/skills/alpha")
    let lock_path = project.join("c-plugin-lock.json")
    let state_path = project.join(".agents/c-plugin-state.json")
    let foreign = project.join(".agents/skills/alpha")
    @fs.mkdir(manifest.dirname().to_string(), recursive=true)
    @fs.mkdir(skill.to_string(), recursive=true)
    @fs.mkdir(foreign.dirname().to_string(), recursive=true)
    @fs.write_file(
      manifest.to_string(),
      "{\"name\":\"test\",\"plugins\":[{\"name\":\"demo\",\"source\":\"plugins/demo\"}]}",
      create_mode=CreateNew,
    )
    @fs.write_file(
      skill.join("SKILL.md").to_string(),
      "# Alpha\n",
      create_mode=CreateNew,
    )
    @fs.write_file(foreign.to_string(), "foreign\n", create_mode=CreateNew)
    let source = RelativeSourcePath::RelativeSourcePath("marketplace")
    let kind = MarketplaceKind::claude()
    let current_lock = Lock::Lock([], [
      LockRepository::from_local(
        LocalLockRepository::LocalLockRepository(source, kind, [
          Plugin::Plugin(
            PluginName::PluginName("demo"),
            RelativePluginPath::RelativePluginPath("plugins/demo"),
            [SkillName::SkillName("alpha")],
          ),
        ]),
      ),
    ])
    create_lock_exclusive(lock_path, current_lock)
    write_ownership_state_atomic(state_path, OwnershipState::empty())
    let lock_before = @fs.read_file(lock_path.to_string()).text()
    let state_before = @fs.read_file(state_path.to_string()).text()
    let storage_events : Array[String] = []
    let runtime = Runtime::Runtime(
      paths=RuntimePaths::RuntimePaths(home, project, root.join("cache")),
      discover_locks_api=fn(_paths, _options) {
        ReadOnlyArray::from_array([lock_path])
      },
      load_lock~,
      create_lock_exclusive=(path, lock) => {
        storage_events.push("create_lock")
        create_lock_exclusive(path, lock)
      },
      write_lock_atomic=(path, lock) => {
        storage_events.push("write_lock")
        write_lock_atomic(path, lock)
      },
      load_ownership_state=path => {
        storage_events.push("load_ownership")
        load_ownership_state(path)
      },
      write_ownership_state_atomic=(path, state) => {
        storage_events.push("write_ownership")
        write_ownership_state_atomic(path, state)
      },
    )
    try
      add_local(runtime, { global: false, force, source, kind, selections })
      |> ignore
    catch {
      AddLocalError::InvalidInput(reason~) => check_reason(reason)
      _ => fail("expected add input error")
    } noraise {
      _ => fail("invalid add must fail before changing state")
    }
    // Ownership I/O is the existing Runtime boundary used by synchronization.
    debug_inspect(storage_events, content="[]")
    inspect(@fs.read_file(lock_path.to_string()).text(), content=lock_before)
    assert_true(load_lock(lock_path) == current_lock)
    inspect(@fs.read_file(state_path.to_string()).text(), content=state_before)
    inspect(@fs.read_file(foreign.to_string()).text(), content="foreign\n")
    debug_inspect(
      @fs.kind(foreign.to_string(), follow_symlink=false),
      content="Regular",
    )
  }
}

///|
async test "Add local command 5 - duplicate source preserves lock and skips sync storage" {
  assert_add_local_rejection_preserves_state(["demo/alpha"], force=false, check_reason=reason => {
    assert_true(reason.contains("lock repositories must be unique"))
  })
}

///|
async test "Add local command 6 - unknown selection preserves lock and skips sync storage" {
  assert_add_local_rejection_preserves_state(
    ["demo/alpha", "demo/missing"],
    force=false,
    check_reason=reason => {
      inspect(reason, content="unknown marketplace skill: demo/missing")
    },
  )
}

///|
async test "Add local command 7 - forced duplicate source preserves lock and foreign file" {
  assert_add_local_rejection_preserves_state(["demo/alpha"], force=true, check_reason=reason => {
    assert_true(reason.contains("lock repositories must be unique"))
  })
}
