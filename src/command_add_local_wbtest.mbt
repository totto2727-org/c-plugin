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
