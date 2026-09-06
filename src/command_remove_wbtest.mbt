///|
fn remove_test_lock(skills : Array[String]) -> Lock raise {
  let plugin = Plugin::Plugin(
    PluginName::PluginName("demo"),
    RelativePluginPath::RelativePluginPath("plugins/demo"),
    skills.map(skill => SkillName::SkillName(skill)),
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
test "Remove selection 1 - parses a normalized typed local skill identity" {
  let selection = parse_remove_skill_selection("marketplace/./demo/alpha")
  match selection.repository {
    LocalIdentity(source) =>
      inspect(source.path.to_string(), content="marketplace")
    _ => fail("remove selection must identify a local repository")
  }
  inspect(selection.plugin_name.value, content="demo")
  inspect(selection.skill_name.value, content="alpha")
}

///|
test "Remove candidate 2 - removes one skill and preserves repository plugin and target" {
  let current = remove_test_lock(["alpha", "beta"])
  let candidate = build_remove_candidate(current, [
    parse_remove_skill_selection("marketplace/demo/alpha"),
  ])
  match candidate {
    Some(candidate) => {
      inspect(candidate.targets == current.targets, content="true")
      inspect(candidate.repositories.length(), content="1")
      match candidate.repositories.to_array()[0].1 {
        Local(repository) => {
          let plugin = repository.plugins.to_array()[0].1
          inspect(plugin.enabled_skills.length(), content="1")
          inspect(
            plugin.enabled_skills.contains(SkillName::SkillName("beta")),
            content="true",
          )
        }
        _ => fail("local repository must remain local")
      }
    }
    None => fail("known skill removal must produce a candidate")
  }
}

///|
test "Remove candidate 3 - empty and unknown are no-op while final skill prunes repository" {
  let current = remove_test_lock(["alpha"])
  match build_remove_candidate(current, []) {
    None => ()
    Some(_) => fail("empty selection must be a no-op")
  }
  match
    build_remove_candidate(current, [
      parse_remove_skill_selection("marketplace/demo/unknown"),
    ]) {
    None => ()
    Some(_) => fail("unknown selection must be a no-op")
  }
  match
    build_remove_candidate(current, [
      parse_remove_skill_selection("marketplace/demo/alpha"),
    ]) {
    Some(candidate) => inspect(candidate.repositories.length(), content="0")
    None => fail("final skill removal must produce an empty repository set")
  }
}

///|
async test "Remove command 4 - parses repeated typed skill selections and global scope" {
  let mut captured : RemoveOptions? = None
  let cli = @admiral.CliApp::CliApp(name="c-plugin", commands=[
    remove_command_def(context => captured = Some(remove_options(context))),
  ])
  cli.run(
    argv=Some([
      "remove", "--skill", "marketplace/./demo/alpha", "--skill", "vendor/other/plugin/beta",
      "--global",
    ]),
    env=Map([]),
  )
  match captured {
    Some(options) => {
      inspect(options.global, content="true")
      inspect(options.selections.length(), content="2")
      inspect(options.selections[0].plugin_name.value, content="demo")
      inspect(options.selections[1].skill_name.value, content="beta")
    }
    None => fail("remove command did not run")
  }
}
