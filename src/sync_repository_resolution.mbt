///|
fn marketplace_manifest_path(kind : MarketplaceKind) -> @path.Path {
  match kind {
    Claude => ".claude-plugin/marketplace.json"
    Cursor => ".cursor-plugin/marketplace.json"
    Codex => ".codex-plugin/marketplace.json"
  }
}

///|
fn repository_root_error_reason(error : RepositoryRootError) -> String {
  match error {
    RelativeRepositoryRoot(path~) =>
      "repository root is relative: \{path.to_string()}"
  }
}

///|
fn marketplace_read_error_reason(error : MarketplaceReadError) -> String {
  match error {
    IO(path~, reason~) => "marketplace I/O at \{path}: \{reason}"
    Syntax(path~, cause=_) => "invalid marketplace JSON at \{path}"
    Validation(path~, cause=_) => "invalid marketplace data at \{path}"
  }
}

///|
fn skill_resolution_error_reason(error : SkillResolutionError) -> String {
  match error {
    IO(path~, reason~) => "skill resolution I/O at \{path}: \{reason}"
    InvalidSkillName(path~, reason~) =>
      "invalid skill name at \{path}: \{reason}"
    InvalidSkillPath(path~, reason~) =>
      "invalid skill path at \{path}: \{reason}"
  }
}

///|
async fn resolve_repository_for_sync(
  lock_path : @path.Path,
  repository : LockRepository,
) -> RepositorySkillResolution {
  match repository {
    GitHub(_) =>
      Unavailable(
        repository~,
        reason="GitHub repository resolution is not available in Milestone 3",
      )
    Local(local_repository) => {
      let repository_path = lock_path
        .dirname()
        .join(local_repository.path.path.path)
        .normalize()
      let repository_root = RepositoryRoot::RepositoryRoot(repository_path) catch {
        error =>
          return Unavailable(
            repository~,
            reason=repository_root_error_reason(error),
          )
      }
      let marketplace_path = repository_path.join(
        marketplace_manifest_path(local_repository.marketplace_kind),
      )
      let marketplace = read_marketplace_file(
        marketplace_path,
        local_repository.marketplace_kind,
      ) catch {
        error =>
          return Unavailable(
            repository~,
            reason=marketplace_read_error_reason(error),
          )
      }
      let skills = resolve_marketplace_skills(repository_root, marketplace) catch {
        error =>
          return Unavailable(
            repository~,
            reason=skill_resolution_error_reason(error),
          )
      }
      Available(repository~, skills~)
    }
  }
}

///|
async fn resolve_repositories_for_sync(
  lock_path : @path.Path,
  lock : Lock,
) -> RepositorySkillResolutions {
  let resolutions = []
  for pair in lock.repositories.to_array() {
    let repository = pair.1
    let resolution = resolve_repository_for_sync(lock_path, repository) catch {
      error => Unavailable(repository~, reason=error.to_string())
    }
    resolutions.push(resolution)
  }
  RepositorySkillResolutions::RepositorySkillResolutions(resolutions)
}
