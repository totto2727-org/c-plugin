///|
async test "LinkReconciliation reconcile_skill_links 10 - hard-stops after a created link checkpoint failure" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-create-fail-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("skills")
    let target_a = root.join("target-a")
    let target_b = root.join("target-b")
    @fs.mkdir(target_a.to_string(), recursive=true)
    @fs.mkdir(target_b.to_string(), recursive=true)
    let entry_a = stale_reconciliation_entry(managed_root, "a", target_a)
    let entry_b = stale_reconciliation_entry(managed_root, "b", target_b)
    let desired_state = OwnershipState::OwnershipState([entry_b, entry_a])
    let state_path = reconciliation_state_path(root.join("state.json"))
    let empty = OwnershipState::OwnershipState([])
    let fail_checkpoint : async (@path.Path, OwnershipState) -> Unit raise StateStoreError = (
      path,
      _state,
    ) => raise StateStoreError::IO(path~, reason="checkpoint failed")
    let failed = reconcile_skill_links(
      state_path~,
      desired_state~,
      previous_ownership=Trusted(empty),
      checkpoint_ownership_state=fail_checkpoint,
    )
    debug_inspect(failed.status, content="Partial")
    inspect(failed.durable_state == empty, content="true")
    match failed.notices[0] {
      CheckpointFailed(operation=CheckpointOwnership, path~, reason~) => {
        inspect(path == state_path, content="true")
        inspect(reason, content="checkpoint failed")
      }
      _ => fail("expected checkpoint failure")
    }
    let first_kind = @fs.kind(
      entry_a.link.path.path.to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(first_kind, content="Unknown")
    let second_kind = @fs.kind(
      entry_b.link.path.path.to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(second_kind, content="Unknown")

    let checkpoints = []
    let retried = reconcile_skill_links(
      state_path~,
      desired_state~,
      previous_ownership=Trusted(failed.durable_state),
      checkpoint_ownership_state=fn(_path, state) { checkpoints.push(state) },
    )
    debug_inspect(retried.status, content="Complete")
    inspect(checkpoints.length(), content="2")
    inspect(retried.durable_state == desired_state, content="true")
    inspect(
      @fs.realpath(entry_a.link.path.path.to_string()),
      content=@fs.realpath(target_a.to_string()),
    )
    inspect(
      @fs.realpath(entry_b.link.path.path.to_string()),
      content=@fs.realpath(target_b.to_string()),
    )
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 12 - preserves an injected EEXIST race winner" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-eexist-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("skills")
    let desired_target = root.join("desired")
    let foreign_target = root.join("foreign")
    @fs.mkdir(desired_target.to_string(), recursive=true)
    @fs.mkdir(foreign_target.to_string(), recursive=true)
    let entry = stale_reconciliation_entry(
      managed_root, "install", desired_target,
    )
    let mut checkpointed = false
    let io : LinkReconciliationIO = {
      mkdir: async fn(path) {
        @fs.mkdir(path.to_string(), recursive=true) catch {
          @os_error.OSError(_) as error if error.is_EEXIST() => ()
          error => raise error
        }
      },
      kind: async fn(path) { @fs.kind(path.to_string(), follow_symlink=false) },
      realpath: async fn(path) { @path.Path(@fs.realpath(path.to_string())) },
      symlink: async fn(target, link) {
        @fs.symlink(
          target=foreign_target.relative(base=managed_root).to_string(),
          link.to_string(),
        )
        @fs.symlink(target=target.to_string(), link.to_string())
      },
      remove: async fn(path) { @fs.remove(path.to_string()) },
      checkpoint: fn(_path, _state) { checkpointed = true },
    }
    let empty = OwnershipState::OwnershipState([])
    let result = reconcile_skill_links_with_io(
      io,
      reconciliation_state_path(root.join("state.json")),
      OwnershipState::OwnershipState([entry]),
      Trusted(empty),
    )
    debug_inspect(result.status, content="Partial")
    inspect(result.durable_state == empty, content="true")
    inspect(checkpointed, content="false")
    match result.notices[0] {
      UnmanagedPathPreserved(path~) =>
        inspect(path == entry.link.path.path, content="true")
      _ => fail("expected unmanaged EEXIST winner notice")
    }
    inspect(
      @fs.realpath(entry.link.path.path.to_string()),
      content=@fs.realpath(foreign_target.to_string()),
    )
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 17 - hard-stops after successful create verifies the wrong target" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-verify-race-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("skills")
    let target_a = root.join("target-a")
    let target_b = root.join("target-b")
    let wrong_target = root.join("wrong-target")
    @fs.mkdir(target_a.to_string(), recursive=true)
    @fs.mkdir(target_b.to_string(), recursive=true)
    @fs.mkdir(wrong_target.to_string(), recursive=true)
    let entry_a = stale_reconciliation_entry(managed_root, "a", target_a)
    let entry_b = stale_reconciliation_entry(managed_root, "b", target_b)
    let mut checkpointed = false
    let io : LinkReconciliationIO = {
      mkdir: async fn(path) {
        @fs.mkdir(path.to_string(), recursive=true) catch {
          @os_error.OSError(_) as error if error.is_EEXIST() => ()
          error => raise error
        }
      },
      kind: async fn(path) { @fs.kind(path.to_string(), follow_symlink=false) },
      realpath: async fn(path) { @path.Path(@fs.realpath(path.to_string())) },
      symlink: async fn(target, link) {
        if link == entry_a.link.path.path {
          @fs.symlink(
            target=wrong_target.relative(base=managed_root).to_string(),
            link.to_string(),
          )
        } else {
          @fs.symlink(target=target.to_string(), link.to_string())
        }
      },
      remove: async fn(path) { @fs.remove(path.to_string()) },
      checkpoint: fn(_path, _state) { checkpointed = true },
    }
    let empty = OwnershipState::OwnershipState([])
    let result = reconcile_skill_links_with_io(
      io,
      reconciliation_state_path(root.join("state.json")),
      OwnershipState::OwnershipState([entry_b, entry_a]),
      Trusted(empty),
    )
    debug_inspect(result.status, content="Partial")
    inspect(result.durable_state == empty, content="true")
    inspect(checkpointed, content="false")
    match result.notices[0] {
      OperationFailed(operation=VerifyCreatedLink, path~, reason=_) =>
        inspect(path == entry_a.link.path.path, content="true")
      _ => fail("expected created-link verification failure")
    }
    inspect(
      @fs.realpath(entry_a.link.path.path.to_string()),
      content=@fs.realpath(wrong_target.to_string()),
    )
    let later_kind = @fs.kind(
      entry_b.link.path.path.to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(later_kind, content="Unknown")
  }
}
