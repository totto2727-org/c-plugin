///|
async test "read_marketplace_file - reads parses and decodes a marketplace" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-marketplace-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("marketplace.json")
    let text =
      #|{"name":"test","plugins":[{"name":"second","source":"plugins/second"},{"name":"first","source":"plugins/first"}]}
    @fs.write_file(path.to_string(), text, create_mode=CreateNew)
    let marketplace = read_marketplace_file(path, MarketplaceKind::claude())
    inspect(marketplace.name, content="test")
    debug_inspect(
      marketplace.plugins.map(plugin => plugin.name.value),
      content="<ReadOnlyArray: [\"second\", \"first\"]>",
    )
  }
}

///|
async test "read_marketplace_file - reports filesystem failure separately" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-marketplace-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("missing.json")
    try read_marketplace_file(path, MarketplaceKind::cursor()) |> ignore catch {
      MarketplaceReadError::IO(path=failed_path, reason=_) =>
        inspect(failed_path.to_string(), content=path.to_string())
      _ => fail("expected MarketplaceReadError::IO")
    }
  }
}

///|
async test "read_marketplace_file - reports JSON syntax failure separately" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-marketplace-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("marketplace.json")
    @fs.write_file(path.to_string(), "{", create_mode=CreateNew)
    try read_marketplace_file(path, MarketplaceKind::claude()) |> ignore catch {
      MarketplaceReadError::Syntax(path=failed_path, cause=_) =>
        inspect(failed_path.to_string(), content=path.to_string())
      _ => fail("expected MarketplaceReadError::Syntax")
    }
  }
}

///|
async test "read_marketplace_file - preserves validation JsonPath" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-marketplace-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("marketplace.json")
    let text =
      #|{"name":"test","plugins":[{"source":"plugins/first"}]}
    @fs.write_file(path.to_string(), text, create_mode=CreateNew)
    try read_marketplace_file(path, MarketplaceKind::claude()) |> ignore catch {
      MarketplaceReadError::Validation(
        path=failed_path,
        cause=@json.JsonDecodeError::JsonDecodeError((json_path, _))
      ) => {
        inspect(failed_path.to_string(), content=path.to_string())
        inspect(json_path.to_string(), content="/plugins/0/name")
      }
      _ => fail("expected MarketplaceReadError::Validation")
    }
  }
}
