///|
test "CliApp app - exposes implemented stage commands" {
  let cli = app()
  inspect(cli.name, content="c-plugin")
  inspect(cli.version, content="0.1.0")
  inspect(cli.commands.length(), content="0")
}
