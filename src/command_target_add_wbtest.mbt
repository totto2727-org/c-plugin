///|
test "Target add candidate 1 - adds one normalized unique target" {
  let current = Lock::Lock([], [])
  let target = Target::Target(".cursor/./skills")
  let candidate = build_target_add_candidate(current, target)
  inspect(candidate.targets.length(), content="1")
  inspect(
    candidate.targets.contains(Target::Target(".cursor/skills")),
    content="true",
  )
  inspect(candidate.repositories == current.repositories, content="true")
}

///|
test "Target add candidate 2 - duplicate normalized target is semantic no-op" {
  let current = Lock::Lock([Target::Target(".cursor/skills")], [])
  let candidate = build_target_add_candidate(
    current,
    Target::Target(".cursor/./skills"),
  )
  inspect(candidate == current, content="true")
}

///|
async test "Target add command 3 - parses typed path and global scope" {
  let mut captured : TargetAddOptions? = None
  let cli = @admiral.CliApp::CliApp(name="c-plugin", commands=[
    @admiral.CommandDef::CommandDef(name="skill", subcommands=[
      target_command_def(
        context => captured = Some(target_add_options(context)),
        _ => (),
      ),
    ]),
  ])
  cli.run(
    argv=Some(["skill", "target", "add", ".cursor/./skills", "--global"]),
    env=Map([]),
  )
  match captured {
    Some(options) => {
      inspect(options.global, content="true")
      inspect(options.target.path.to_string(), content=".cursor/skills")
    }
    None => fail("target add command did not run")
  }
  match target_add_discovery_options(false) {
    Project(recursive~) => inspect(recursive, content="false")
    _ => fail("project target add must use project discovery")
  }
  match target_add_discovery_options(true) {
    Global => ()
    _ => fail("global target add must use global discovery")
  }
}
