///|
/// Repository operations exposed by the bit-backed store.
pub(all) enum BitRepositoryOperation {
  Clone
  Fetch
  ResolveDefaultBranch
  CheckoutCommit
  ResolveHeadCommit
} derive(Debug, Eq)

///|
/// A bit operation failed at the c-plugin repository boundary.
pub(all) suberror BitRepositoryStoreError {
  OperationFailed(
    operation~ : BitRepositoryOperation,
    path~ : @x_path.AbsolutePath?,
    reason~ : String
  )
} derive(Debug, Eq)

///|
/// The remote default branch name and the commit currently referenced by it.
pub struct ResolvedDefaultBranch {
  name : String
  commit : CommitId
} derive(Eq)

///|
/// Create a resolved default branch value without changing its branch name.
pub fn ResolvedDefaultBranch::ResolvedDefaultBranch(
  name : String,
  commit : CommitId,
) -> ResolvedDefaultBranch {
  { name, commit }
}

///|
/// Injectable repository operations backed by mizchi/bit in production.
pub struct BitRepositoryStore {
  clone_repository_api : async (GitHubRepository, @x_path.AbsolutePath) -> CommitId? raise BitRepositoryStoreError
  fetch_repository_api : async (GitHubRepository, @x_path.AbsolutePath) -> CommitId? raise BitRepositoryStoreError
  resolve_default_branch_api : async (GitHubRepository) -> ResolvedDefaultBranch? raise BitRepositoryStoreError
  checkout_commit_api : async (@x_path.AbsolutePath, CommitId) -> CommitId raise BitRepositoryStoreError
  resolve_head_commit_api : async (@x_path.AbsolutePath) -> CommitId? raise BitRepositoryStoreError
}

///|
/// Create a repository store from explicit operation callbacks.
pub fn BitRepositoryStore::BitRepositoryStore(
  clone_repository_api~ : async (GitHubRepository, @x_path.AbsolutePath) -> CommitId? raise BitRepositoryStoreError,
  fetch_repository_api~ : async (GitHubRepository, @x_path.AbsolutePath) -> CommitId? raise BitRepositoryStoreError,
  resolve_default_branch_api~ : async (GitHubRepository) -> ResolvedDefaultBranch? raise BitRepositoryStoreError,
  checkout_commit_api~ : async (@x_path.AbsolutePath, CommitId) -> CommitId raise BitRepositoryStoreError,
  resolve_head_commit_api~ : async (@x_path.AbsolutePath) -> CommitId? raise BitRepositoryStoreError,
) -> BitRepositoryStore {
  {
    clone_repository_api,
    fetch_repository_api,
    resolve_default_branch_api,
    checkout_commit_api,
    resolve_head_commit_api,
  }
}

///|
/// Clone a GitHub repository into the caller-provided lock-scoped absolute cache path.
pub async fn BitRepositoryStore::clone_repository(
  self : BitRepositoryStore,
  repository : GitHubRepository,
  path : @x_path.AbsolutePath,
) -> CommitId? raise BitRepositoryStoreError {
  (self.clone_repository_api)(repository, path)
}

///|
/// Fetch a GitHub repository in the caller-provided lock-scoped absolute cache path.
pub async fn BitRepositoryStore::fetch_repository(
  self : BitRepositoryStore,
  repository : GitHubRepository,
  path : @x_path.AbsolutePath,
) -> CommitId? raise BitRepositoryStoreError {
  (self.fetch_repository_api)(repository, path)
}

///|
/// Resolve the remote HEAD into its branch name and commit.
pub async fn BitRepositoryStore::resolve_default_branch(
  self : BitRepositoryStore,
  repository : GitHubRepository,
) -> ResolvedDefaultBranch? raise BitRepositoryStoreError {
  (self.resolve_default_branch_api)(repository)
}

///|
/// Check out a pinned commit in the caller-provided lock-scoped absolute cache path.
pub async fn BitRepositoryStore::checkout_commit(
  self : BitRepositoryStore,
  path : @x_path.AbsolutePath,
  commit : CommitId,
) -> CommitId raise BitRepositoryStoreError {
  (self.checkout_commit_api)(path, commit)
}

///|
/// Resolve the current HEAD commit in the caller-provided lock-scoped absolute cache path.
pub async fn BitRepositoryStore::resolve_head_commit(
  self : BitRepositoryStore,
  path : @x_path.AbsolutePath,
) -> CommitId? raise BitRepositoryStoreError {
  (self.resolve_head_commit_api)(path)
}

///|
fn bit_repository_remote_url(repository : GitHubRepository) -> String {
  "https://github.com/\{repository.route()}.git"
}

///|
fn commit_id_from_bit(
  object_id : @bit_object.ObjectId,
  operation : BitRepositoryOperation,
  path : @x_path.AbsolutePath?,
) -> CommitId raise BitRepositoryStoreError {
  CommitId::CommitId(object_id.to_hex()) catch {
    error =>
      raise BitRepositoryStoreError::OperationFailed(
        operation~,
        path~,
        reason=error.to_string(),
      )
  }
}

///|
/// Create the production store backed by the pinned mizchi/bit libraries.
pub fn BitRepositoryStore::production() -> BitRepositoryStore {
  let filesystem = @bit_osfs.OsFs::new()
  BitRepositoryStore::BitRepositoryStore(
    clone_repository_api=(repository, path) => {
      let result = @bit_native.clone_http(
        filesystem,
        filesystem,
        bit_repository_remote_url(repository),
        path.path.to_string(),
        false,
      ) catch {
        error =>
          raise BitRepositoryStoreError::OperationFailed(
            operation=Clone,
            path=Some(path),
            reason=error.to_string(),
          )
      }
      match result {
        None => None
        Some(object_id) =>
          Some(commit_id_from_bit(object_id, Clone, Some(path)))
      }
    },
    fetch_repository_api=(repository, path) => {
      let result = @bit_native.pull_http(
        filesystem,
        filesystem,
        path.path.to_string(),
        bit_repository_remote_url(repository),
        false,
        rebase=false,
      ) catch {
        error =>
          raise BitRepositoryStoreError::OperationFailed(
            operation=Fetch,
            path=Some(path),
            reason=error.to_string(),
          )
      }
      match result {
        None => None
        Some(object_id) =>
          Some(commit_id_from_bit(object_id, Fetch, Some(path)))
      }
    },
    resolve_default_branch_api=repository => {
      let result = @bit_native.resolve_remote_ref_id(
        bit_repository_remote_url(repository),
        "HEAD",
      ) catch {
        error =>
          raise BitRepositoryStoreError::OperationFailed(
            operation=ResolveDefaultBranch,
            path=None,
            reason=error.to_string(),
          )
      }
      match result {
        None => None
        Some((_object_id, None)) =>
          raise BitRepositoryStoreError::OperationFailed(
            operation=ResolveDefaultBranch,
            path=None,
            reason="remote HEAD did not resolve to a default branch",
          )
        Some((object_id, Some(name))) => {
          let commit = commit_id_from_bit(object_id, ResolveDefaultBranch, None)
          Some(ResolvedDefaultBranch::ResolvedDefaultBranch(name, commit))
        }
      }
    },
    checkout_commit_api=(path, commit) => {
      let object_id = @bit_lib.checkout(
        filesystem,
        filesystem,
        path.path.to_string(),
        commit.value,
        detach=true,
        update_worktree=true,
        update_index=true,
      ) catch {
        error =>
          raise BitRepositoryStoreError::OperationFailed(
            operation=CheckoutCommit,
            path=Some(path),
            reason=error.to_string(),
          )
      }
      commit_id_from_bit(object_id, CheckoutCommit, Some(path))
    },
    resolve_head_commit_api=path => {
      let result = @bit_lib.resolve_head_commit(
        filesystem,
        path.path.join(".git").to_string(),
      ) catch {
        error =>
          raise BitRepositoryStoreError::OperationFailed(
            operation=ResolveHeadCommit,
            path=Some(path),
            reason=error.to_string(),
          )
      }
      match result {
        None => None
        Some(object_id) =>
          Some(commit_id_from_bit(object_id, ResolveHeadCommit, Some(path)))
      }
    },
  )
}
