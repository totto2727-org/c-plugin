///|
async fn expect_bit_repository_store_error(
  action : async () -> Unit raise BitRepositoryStoreError,
  operation : BitRepositoryOperation,
  path : @x_path.AbsolutePath?,
  reason : String,
) -> Unit {
  try action() catch {
    BitRepositoryStoreError::OperationFailed(
      operation=actual_operation,
      path=actual_path,
      reason=actual_reason
    ) => {
      inspect(actual_operation == operation, content="true")
      inspect(actual_path == path, content="true")
      inspect(actual_reason, content=reason)
    }
  } noraise {
    _ => fail("bit repository operation must fail")
  }
}

///|
async test "BitRepositoryStore forwarding 1 - preserves typed inputs and results" {
  let repository = GitHubRepository::from_route("openai/codex")
  let cache_path = @x_path.AbsolutePath::AbsolutePath(
    "/synthetic/cache/scope/openai/codex",
  )
  let first_commit = CommitId::CommitId(
    "1111111111111111111111111111111111111111",
  )
  let second_commit = CommitId::CommitId(
    "2222222222222222222222222222222222222222",
  )
  let default_branch = ResolvedDefaultBranch::ResolvedDefaultBranch(
    "main", second_commit,
  )
  let events : Array[String] = []
  let repositories : Array[GitHubRepository] = []
  let paths : Array[@x_path.AbsolutePath] = []
  let commits : Array[CommitId] = []
  let store = BitRepositoryStore::BitRepositoryStore(
    clone_repository_api=(received_repository, received_path) => {
      events.push("clone")
      repositories.push(received_repository)
      paths.push(received_path)
      Some(first_commit)
    },
    fetch_repository_api=(received_repository, received_path) => {
      events.push("fetch")
      repositories.push(received_repository)
      paths.push(received_path)
      Some(second_commit)
    },
    resolve_default_branch_api=received_repository => {
      events.push("default-branch")
      repositories.push(received_repository)
      Some(default_branch)
    },
    checkout_commit_api=(received_path, received_commit) => {
      events.push("checkout")
      paths.push(received_path)
      commits.push(received_commit)
      first_commit
    },
    resolve_head_commit_api=received_path => {
      events.push("head")
      paths.push(received_path)
      Some(first_commit)
    },
  )

  inspect(
    store.clone_repository(repository, cache_path) == Some(first_commit),
    content="true",
  )
  inspect(
    store.fetch_repository(repository, cache_path) == Some(second_commit),
    content="true",
  )
  inspect(
    store.resolve_default_branch(repository) == Some(default_branch),
    content="true",
  )
  inspect(
    store.checkout_commit(cache_path, first_commit) == first_commit,
    content="true",
  )
  inspect(
    store.resolve_head_commit(cache_path) == Some(first_commit),
    content="true",
  )
  debug_inspect(
    events,
    content="[\"clone\", \"fetch\", \"default-branch\", \"checkout\", \"head\"]",
  )
  inspect(repositories.length(), content="3")
  inspect(repositories.all(received => received == repository), content="true")
  inspect(paths.length(), content="4")
  inspect(paths.all(received => received == cache_path), content="true")
  inspect(commits.length(), content="1")
  inspect(commits[0] == first_commit, content="true")
}

///|
async test "BitRepositoryStore forwarding 2 - preserves absent commits and branches" {
  let repository = GitHubRepository::from_route("openai/codex")
  let cache_path = @x_path.AbsolutePath::AbsolutePath(
    "/synthetic/cache/scope/openai/codex",
  )
  let commit = CommitId::CommitId("1111111111111111111111111111111111111111")
  let store = BitRepositoryStore::BitRepositoryStore(
    clone_repository_api=(_repository, _path) => None,
    fetch_repository_api=(_repository, _path) => None,
    resolve_default_branch_api=_repository => None,
    checkout_commit_api=(_path, _commit) => commit,
    resolve_head_commit_api=_path => None,
  )

  inspect(
    store.clone_repository(repository, cache_path) is None,
    content="true",
  )
  inspect(
    store.fetch_repository(repository, cache_path) is None,
    content="true",
  )
  inspect(store.resolve_default_branch(repository) is None, content="true")
  inspect(store.resolve_head_commit(cache_path) is None, content="true")
}

///|
async test "BitRepositoryStore forwarding 3 - propagates each injected typed failure" {
  let repository = GitHubRepository::from_route("openai/codex")
  let cache_path = @x_path.AbsolutePath::AbsolutePath(
    "/synthetic/cache/scope/openai/codex",
  )
  let commit = CommitId::CommitId("1111111111111111111111111111111111111111")
  let events : Array[String] = []
  let store = BitRepositoryStore::BitRepositoryStore(
    clone_repository_api=(_repository, path) => {
      events.push("clone")
      raise BitRepositoryStoreError::OperationFailed(
        operation=Clone,
        path=Some(path),
        reason="clone failed",
      )
    },
    fetch_repository_api=(_repository, path) => {
      events.push("fetch")
      raise BitRepositoryStoreError::OperationFailed(
        operation=Fetch,
        path=Some(path),
        reason="fetch failed",
      )
    },
    resolve_default_branch_api=_repository => {
      events.push("default-branch")
      raise BitRepositoryStoreError::OperationFailed(
        operation=ResolveDefaultBranch,
        path=None,
        reason="default branch failed",
      )
    },
    checkout_commit_api=(path, _commit) => {
      events.push("checkout")
      raise BitRepositoryStoreError::OperationFailed(
        operation=CheckoutCommit,
        path=Some(path),
        reason="checkout failed",
      )
    },
    resolve_head_commit_api=path => {
      events.push("head")
      raise BitRepositoryStoreError::OperationFailed(
        operation=ResolveHeadCommit,
        path=Some(path),
        reason="head failed",
      )
    },
  )

  expect_bit_repository_store_error(
    () => store.clone_repository(repository, cache_path) |> ignore,
    Clone,
    Some(cache_path),
    "clone failed",
  )
  expect_bit_repository_store_error(
    () => store.fetch_repository(repository, cache_path) |> ignore,
    Fetch,
    Some(cache_path),
    "fetch failed",
  )
  expect_bit_repository_store_error(
    () => store.resolve_default_branch(repository) |> ignore,
    ResolveDefaultBranch,
    None,
    "default branch failed",
  )
  expect_bit_repository_store_error(
    () => store.checkout_commit(cache_path, commit) |> ignore,
    CheckoutCommit,
    Some(cache_path),
    "checkout failed",
  )
  expect_bit_repository_store_error(
    () => store.resolve_head_commit(cache_path) |> ignore,
    ResolveHeadCommit,
    Some(cache_path),
    "head failed",
  )
  debug_inspect(
    events,
    content="[\"clone\", \"fetch\", \"default-branch\", \"checkout\", \"head\"]",
  )
}

///|
async test "BitRepositoryStore production - resolves an empty local repository without a HEAD commit" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-bit-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let filesystem = @bit_osfs.OsFs::new()
    @bit_lib.init_repo(filesystem, root.to_string())
    let absolute_root = @x_path.AbsolutePath::AbsolutePath(root)

    inspect(
      BitRepositoryStore::production().resolve_head_commit(absolute_root)
      is None,
      content="true",
    )
  }
}
