///|
test "Target remove candidate 1 - removes known targets and preserves others" {
  let current = Lock::Lock(
    [Target::Target(".cursor/skills"), Target::Target(".claude/skills")],
    [],
  )
  let candidate = build_target_remove_candidate(current, [
    Target::Target(".cursor/./skills"),
  ])
  match candidate {
    Some(candidate) => {
      inspect(candidate.targets.length(), content="1")
      inspect(
        candidate.targets.contains(Target::Target(".claude/skills")),
        content="true",
      )
      inspect(candidate.repositories == current.repositories, content="true")
    }
    None => fail("known target removal must produce a candidate")
  }
}

///|
test "Target remove candidate 2 - empty and unknown are no-op while last removal is allowed" {
  let current = Lock::Lock([Target::Target(".cursor/skills")], [])
  match build_target_remove_candidate(current, []) {
    None => ()
    Some(_) => fail("empty selection must be a no-op")
  }
  match
    build_target_remove_candidate(current, [Target::Target(".claude/skills")]) {
    None => ()
    Some(_) => fail("unknown selection must be a no-op")
  }
  match
    build_target_remove_candidate(current, [Target::Target(".cursor/skills")]) {
    Some(candidate) => inspect(candidate.targets.length(), content="0")
    None => fail("removing the last target must produce an empty candidate")
  }
}

///|
async test "Target remove command 3 - parses repeatable typed targets and global scope" {
  let mut captured : TargetRemoveOptions? = None
  let cli = @admiral.CliApp::CliApp(name="c-plugin", commands=[
    @admiral.CommandDef::CommandDef(name="skill", subcommands=[
      target_command_def(_ => (), context => {
        captured = Some(target_remove_options(context))
      }),
    ]),
  ])
  cli.run(
    argv=Some([
      "skill", "target", "remove", "--target", ".cursor/./skills", "--target", ".claude/skills",
      "--global",
    ]),
    env=Map([]),
  )
  match captured {
    Some(options) => {
      inspect(options.global, content="true")
      inspect(options.targets.length(), content="2")
      inspect(options.targets[0].path.to_string(), content=".cursor/skills")
      inspect(options.targets[1].path.to_string(), content=".claude/skills")
    }
    None => fail("target remove command did not run")
  }
  match target_remove_discovery_options(false) {
    Project(recursive~) => inspect(recursive, content="false")
    _ => fail("project target remove must use project discovery")
  }
  match target_remove_discovery_options(true) {
    Global => ()
    _ => fail("global target remove must use global discovery")
  }
}
