///|
fn app() -> @admiral.CliApp {
  @admiral.CliApp::CliApp(
    name="c-plugin",
    version="0.1.0",
    description="Native MoonBit CLI for c-plugin",
    // Temporary bootstrap: runtime/init are not available until S7.
    // Replace this empty dispatch with runtime composition and init_command_def in S7, then remove this comment.
    commands=[],
  )
}

///|
async fn main {
  app().run()
}
