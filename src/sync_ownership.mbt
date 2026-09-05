///|
fn managed_skill_roots_for_sync(
  lock_path : @path.Path,
  lock : Lock,
) -> @immut_hashset.HashSet[ManagedSkillRoot] raise {
  let lock_root = lock_path.dirname()
  let roots = [
    ManagedSkillRoot::ManagedSkillRoot(lock_root.join(".agents").join("skills")),
  ]
  for target in lock.targets {
    let path = lock_root.join(target.path.path).normalize()
    roots.push(ManagedSkillRoot::ManagedSkillRoot(path))
  }
  @immut_hashset.HashSet(roots)
}

///|
async fn validate_managed_root_for_sync(
  lock_root : @path.Path,
  managed_root : ManagedSkillRoot,
) -> Unit {
  let managed_root_path = managed_root.path.path
  guard path_is_within(lock_root, managed_root_path) else {
    raise SyncError::InvalidPath(
      path=managed_root_path,
      reason="managed root must remain below the lock root",
    )
  }
  let physical_lock_root : @path.Path = @fs.realpath(lock_root.to_string()) catch {
    error =>
      raise SyncError::InvalidPath(path=lock_root, reason=error.to_string())
  }
  let mut existing_path = managed_root_path
  while true {
    let kind = try
      @fs.kind(existing_path.to_string(), follow_symlink=false)
    catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => {
        let parent = existing_path.dirname()
        guard parent != existing_path else {
          raise SyncError::InvalidPath(
            path=managed_root_path,
            reason="managed root has no existing directory ancestor",
          )
        }
        existing_path = parent
        continue
      }
      error =>
        raise SyncError::InvalidPath(
          path=existing_path,
          reason=error.to_string(),
        )
    } noraise {
      kind => kind
    }
    guard kind == @fs.FileKind::Directory else {
      raise SyncError::InvalidPath(
        path=existing_path,
        reason="managed root ancestors must be physical directories",
      )
    }
    let physical_existing : @path.Path = @fs.realpath(existing_path.to_string()) catch {
      error =>
        raise SyncError::InvalidPath(
          path=existing_path,
          reason=error.to_string(),
        )
    }
    guard path_is_within(physical_lock_root, physical_existing) else {
      raise SyncError::InvalidPath(
        path=managed_root_path,
        reason="managed root resolves outside the lock root",
      )
    }
    return
  }
}

///|
async fn validate_managed_roots_for_sync(
  lock_root : @path.Path,
  managed_roots : @immut_hashset.HashSet[ManagedSkillRoot],
) -> Unit {
  for managed_root in managed_roots {
    validate_managed_root_for_sync(lock_root, managed_root)
  }
}

///|
fn ownership_state_path_for_sync(
  lock_path : @path.Path,
) -> OwnershipStatePath raise {
  OwnershipStatePath::OwnershipStatePath(
    lock_path.dirname().join(".agents").join("c-plugin-state.json"),
  )
}

///|
async fn load_previous_ownership_for_sync(
  runtime : Runtime,
  state_path : OwnershipStatePath,
) -> PreviousOwnership {
  try runtime.load_ownership_state(state_path.path.path) catch {
    StateStoreError::NotFound(_) => PreviousOwnership::Missing
    StateStoreError::Decode(path=_, reason~) =>
      PreviousOwnership::Corrupt(reason~)
    error => raise SyncError::Store(cause=error)
  } noraise {
    state => PreviousOwnership::Trusted(state)
  }
}

///|
async fn validate_previous_ownership_for_sync(
  lock_root : @path.Path,
  previous_ownership : PreviousOwnership,
) -> PreviousOwnership {
  match previous_ownership {
    Trusted(state) => {
      for pair in state.entries.to_array() {
        let entry = pair.1
        let managed_root = ManagedSkillRoot::ManagedSkillRoot(
          entry.managed_root.path.path,
        ) catch {
          error =>
            return Corrupt(reason="invalid recorded managed root: \{error}")
        }
        validate_managed_root_for_sync(lock_root, managed_root) catch {
          error =>
            return Corrupt(
              reason="unsafe recorded managed root: \{error.to_string()}",
            )
        }
      }
      previous_ownership
    }
    Missing | Corrupt(_) => previous_ownership
  }
}

///|
fn ownership_repository_identity(
  source : OwnershipSource,
) -> RepositoryIdentity {
  match source {
    GitHub(source) => GitHubIdentity(source.repository)
    Local(source) => LocalIdentity(source.repository)
  }
}

///|
fn split_unavailable_ownership_for_sync(
  previous_ownership : PreviousOwnership,
  unavailable_repositories : @immut_hashmap.HashMap[
    RepositoryIdentity,
    RepositoryUnavailable,
  ],
) -> (PreviousOwnership, Array[OwnershipEntry]) raise {
  match previous_ownership {
    Trusted(state) => {
      let active_entries = []
      let preserved_entries = []
      for pair in state.entries.to_array() {
        let entry = pair.1
        if unavailable_repositories.get(
            ownership_repository_identity(entry.source),
          )
          is Some(_) {
          preserved_entries.push(entry)
        } else {
          active_entries.push(entry)
        }
      }
      (
        PreviousOwnership::Trusted(
          OwnershipState::OwnershipState(active_entries),
        ),
        preserved_entries,
      )
    }
    Missing | Corrupt(_) => (previous_ownership, [])
  }
}

///|
fn merge_preserved_ownership_for_sync(
  state : OwnershipState,
  preserved_entries : Array[OwnershipEntry],
) -> OwnershipState {
  let mut entries = state.entries
  for entry in preserved_entries {
    entries = entries.add(OwnershipLinkIdentity(entry.link.path), entry)
  }
  OwnershipState::{ version: state.version, entries }
}
