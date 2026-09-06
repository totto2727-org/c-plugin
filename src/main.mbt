///|
fn runtime_for_init(paths : RuntimePaths) -> Runtime {
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
fn app(runtime : Runtime) -> @admiral.CliApp {
  @admiral.CliApp::CliApp(
    name="c-plugin",
    version="0.1.0",
    description="Native MoonBit CLI for c-plugin",
    commands=[
      init_command_def(async fn(context) { run_init(runtime, context) }),
      @admiral.CommandDef::CommandDef(
        name="skill",
        description="Manage skills from plugin repositories",
        subcommands=[
          add_local_command_def(async fn(context) {
            run_add_local(runtime, context)
          }),
          remove_command_def(async fn(context) { run_remove(runtime, context) }),
          sync_command_def(async fn(context) { run_sync(runtime, context) }),
          target_command_def(async fn(context) {
            run_target_add(runtime, context)
          }),
        ],
      ),
    ],
  )
}

///|
async fn main {
  let home : @path.Path = @env.get_env_var("HOME").unwrap_or_else(() => {
    fail("HOME is not set")
  })
  let cwd : @path.Path = @env.current_dir().unwrap_or_else(() => {
    fail("failed to resolve current directory")
  })
  let cache_root = home.join(".cache").join("c-plugin").join("repositories")
  let paths = RuntimePaths::RuntimePaths(home, cwd, cache_root)
  let runtime = runtime_for_init(paths)
  app(runtime).run()
}
