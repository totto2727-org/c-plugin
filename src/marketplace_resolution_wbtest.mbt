///|
async fn create_test_skill(
  root : @path.Path,
  plugin_path : String,
  skill_name : String,
) -> Unit {
  let directory = root.join(plugin_path).join("skills").join(skill_name)
  @fs.mkdir(directory.to_string(), recursive=true)
  @fs.write_file(
    directory.join("SKILL.md").to_string(),
    "# Test\n",
    create_mode=CreateNew,
  )
}

///|
fn test_marketplace(plugins : Array[(String, String)]) -> Marketplace raise {
  Marketplace::Marketplace(
    "test",
    plugins.map(plugin => {
      MarketplacePlugin::MarketplacePlugin(
        PluginName::PluginName(plugin.0),
        RelativePluginPath::RelativePluginPath(@path.Path(plugin.1)),
      )
    }),
  )
}

///|
test "RepositoryRoot RepositoryRoot - normalizes an absolute path" {
  let root = RepositoryRoot::RepositoryRoot(
    @path.Path("/synthetic/repository/./plugins/.."),
  )
  inspect(root.path.to_string(), content="/synthetic/repository")
}

///|
test "RepositoryRoot RepositoryRoot - reports a normalized relative path" {
  let relative = @path.Path("repository/../relative")
  try RepositoryRoot::RepositoryRoot(relative) catch {
    RepositoryRootError::RelativeRepositoryRoot(path~) =>
      inspect(path.to_string(), content="relative")
  } noraise {
    _ => fail("relative repository root must fail")
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - preserves plugin and sorted skill order" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/b", "zeta")
    create_test_skill(root, "plugins/b", "alpha")
    create_test_skill(root, "plugins/a", "shared")
    let marketplace = test_marketplace([
      ("plugin-b", "plugins/b"),
      ("plugin-a", "plugins/a"),
    ])
    let resolved = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      marketplace,
    )
    debug_inspect(
      resolved.map(skill => {
        "\{skill.plugin_name.value}|\{skill.plugin_path.path.to_string()}|\{skill.skill_name.value}|\{skill.skill_path.path.to_string()}"
      }),
      content=(
        #|<ReadOnlyArray:
        #|  [
        #|    "plugin-b|plugins/b|alpha|ROOT/plugins/b/skills/alpha",
        #|    "plugin-b|plugins/b|zeta|ROOT/plugins/b/skills/zeta",
        #|    "plugin-a|plugins/a|shared|ROOT/plugins/a/skills/shared",
        #|  ]>
      ).replace_all(old="ROOT", new=root.to_string()),
    )
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - consumes every M0 kind identically" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/p", "install")
    let strings =
      #|{"name":"test","plugins":[{"name":"plugin","source":"plugins/p"}]}
    let codex =
      #|{"name":"test","plugins":[{"name":"plugin","source":{"source":"local","path":"plugins/p"}}]}
    let claude = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      Marketplace::from_json(MarketplaceKind::claude(), @json.parse(strings)),
    )
    let cursor = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      Marketplace::from_json(MarketplaceKind::cursor(), @json.parse(strings)),
    )
    let codex_result = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      Marketplace::from_json(MarketplaceKind::codex(), @json.parse(codex)),
    )
    inspect(claude == cursor && cursor == codex_result, content="true")
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - missing skills directory is empty" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/later", "valid")
    let resolved = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      test_marketplace([
        ("missing", "plugins/missing"),
        ("later", "plugins/later"),
      ]),
    )
    inspect(resolved.length(), content="1")
    inspect(resolved[0].plugin_name.value, content="later")
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - filters non-skills and hidden entries" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/p", "valid")
    create_test_skill(root, "plugins/p", ".hidden")
    let skills = root.join("plugins/p/skills")
    @fs.mkdir(skills.join("no-marker").to_string())
    @fs.write_file(
      skills.join("regular-file").to_string(),
      "file",
      create_mode=CreateNew,
    )
    let resolved = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      test_marketplace([("plugin", "plugins/p")]),
    )
    inspect(resolved.length(), content="1")
    inspect(resolved[0].skill_name.value, content="valid")
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - shared names across plugins remain distinct" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/a", "shared")
    create_test_skill(root, "plugins/b", "shared")
    let resolved = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      test_marketplace([("a", "plugins/a"), ("b", "plugins/b")]),
    )
    debug_inspect(
      resolved.map(skill => skill.plugin_name.value),
      content="<ReadOnlyArray: [\"a\", \"b\"]>",
    )
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - invalid discovered name is typed" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/p", "bad\\name")
    let candidate = root.join("plugins/p/skills").join("bad\\name")
    try
      resolve_marketplace_skills(
        RepositoryRoot::RepositoryRoot(root),
        test_marketplace([("plugin", "plugins/p")]),
      )
    catch {
      SkillResolutionError::InvalidSkillName(path~, reason=_) =>
        inspect(path == candidate, content="true")
      _ => fail("expected InvalidSkillName")
    } noraise {
      _ => fail("invalid skill name must fail")
    }
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - file at skills path is IO" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let skills = root.join("plugins/p/skills")
    @fs.mkdir(skills.dirname().to_string(), recursive=true)
    @fs.write_file(skills.to_string(), "file", create_mode=CreateNew)
    try
      resolve_marketplace_skills(
        RepositoryRoot::RepositoryRoot(root),
        test_marketplace([("plugin", "plugins/p")]),
      )
    catch {
      SkillResolutionError::IO(path~, reason=_) =>
        inspect(path == skills, content="true")
      _ => fail("expected IO")
    } noraise {
      _ => fail("file at skills path must fail")
    }
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - input and output are snapshots" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/p", "stable")
    let caller = [
      MarketplacePlugin::MarketplacePlugin(
        PluginName::PluginName("plugin"),
        RelativePluginPath::RelativePluginPath(@path.Path("plugins/p")),
      ),
    ]
    let marketplace = Marketplace::Marketplace("test", caller)
    let resolved = resolve_marketplace_skills(
      RepositoryRoot::RepositoryRoot(root),
      marketplace,
    )
    caller.clear()
    inspect(marketplace.plugins.length(), content="1")
    inspect(resolved.length(), content="1")
    inspect(resolved[0].skill_name.value, content="stable")
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - normalizes dotted root" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/p", "stable")
    let marketplace = test_marketplace([("plugin", "plugins/p")])
    inspect(
      resolve_marketplace_skills(
        RepositoryRoot::RepositoryRoot(root),
        marketplace,
      ) ==
      resolve_marketplace_skills(
        RepositoryRoot::RepositoryRoot(root.join(".")),
        marketplace,
      ),
      content="true",
    )
  }
}

///|
async test "MarketplaceResolution resolve_marketplace_skills - does not suppress sibling IO" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-resolution-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    create_test_skill(root, "plugins/good", "valid")
    let invalid = root.join("plugins/bad/skills")
    @fs.mkdir(invalid.dirname().to_string(), recursive=true)
    @fs.write_file(invalid.to_string(), "file", create_mode=CreateNew)
    try
      resolve_marketplace_skills(
        RepositoryRoot::RepositoryRoot(root),
        test_marketplace([("good", "plugins/good"), ("bad", "plugins/bad")]),
      )
    catch {
      SkillResolutionError::IO(path~, reason=_) =>
        inspect(path == invalid, content="true")
      _ => fail("expected IO")
    } noraise {
      _ => fail("IO must not become partial success")
    }
  }
}
