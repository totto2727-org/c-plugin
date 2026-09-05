///|
async test "dependency probe compiles native dependencies and initializes an isolated bit repository" {
  let root = @fs.tmpdir(prefix="c-plugin-probe-")
  let root_path : @path.Path = root
  let marker_path = root_path.join("marker")
  @fs.mkdir(marker_path.to_string(), recursive=true)
  inspect(@fs.exists(marker_path.to_string()), content="true")
  let filesystem = @bit_osfs.OsFs::new()
  @bit_lib.init_repo(filesystem, root_path.to_string())
  let head_path = root_path.join(".git").join("HEAD")
  inspect(
    @fs.read_file(head_path.to_string()).text(),
    content="ref: refs/heads/main\n",
  )
  match @bit_lib.read_head_ref(filesystem, root_path.join(".git").to_string()) {
    @bit_lib.Branch(name) => inspect(name, content="main")
    @bit_lib.Detached(_) => fail("new repository HEAD must name main")
  }
  guard @bit_lib.resolve_head_commit(
      filesystem,
      root_path.join(".git").to_string(),
    )
    is None else {
    fail("new repository must not have a HEAD commit")
  }
  let clone_api = async fn(remote : String, destination : String) {
    @bit_native.clone_http(filesystem, filesystem, remote, destination, false)
  }
  let pull_api = async fn(remote : String, destination : String) {
    @bit_native.pull_http(filesystem, filesystem, remote, destination, false)
  }
  let checkout_api = fn(reference : String) raise {
    @bit_lib.checkout(
      filesystem,
      filesystem,
      root_path.to_string(),
      reference,
      detach=false,
      update_worktree=true,
      update_index=true,
    )
  }
  let remote_ref_api = async fn(remote : String, reference : String) {
    @bit_native.resolve_remote_ref_id(remote, reference)
  }
  ignore(clone_api)
  ignore(pull_api)
  ignore(checkout_api)
  ignore(remote_ref_api)
  inspect(
    @tui.ansi_full_reset(),
    content="\u001b[0m\u001b[?1049h\u001b[?25l\u001b[2J\u001b[H",
  )
  let _lens : @lens.Lens[String] = @lens.root().string("name")
  let target_path = root_path.join("c-plugin-lock.json")
  @fs.write_file(target_path.to_string(), "{}", create_mode=CreateOrTruncate)
  inspect(
    @target_file_discovery.find_home_target_file(root, "c-plugin-lock.json"),
    content=target_path.to_string(),
  )
  @fs.rmdir(root, recursive=true)
}
