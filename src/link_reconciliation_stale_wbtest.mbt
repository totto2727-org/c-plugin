///|
async test "LinkReconciliation reconcile_skill_links 3 - reconciles trusted stale ownership safely" {
  @async.with_task_group() <| group => {
    let temporary_root : @path.Path = @fs.tmpdir(
      prefix="c-plugin-reconcile-stale-",
    )
    group.add_defer(() => @fs.rmdir(temporary_root.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary_root.to_string())
    let target_root = root.join("targets")
    @fs.mkdir(target_root.to_string(), recursive=true)
    let names = [
      "matching", "missing", "file", "directory", "different", "broken", "removed-root",
    ]
    let entries = []
    for name in names {
      let managed_root = root.join("managed").join(name)
      let target = target_root.join(name)
      @fs.mkdir(managed_root.to_string(), recursive=true)
      @fs.mkdir(target.to_string(), recursive=true)
      entries.push(stale_reconciliation_entry(managed_root, "install", target))
    }
    for index, entry in entries {
      match names[index] {
        "matching" =>
          @fs.symlink(
            target=entry.symlink_target.to_string(),
            entry.link.path.path.to_string(),
          )
        "removed-root" =>
          @fs.rmdir(entry.managed_root.path.path.to_string(), recursive=true)
        "missing" => ()
        "file" =>
          @fs.write_file(
            entry.link.path.path.to_string(),
            "foreign",
            create_mode=CreateNew,
          )
        "directory" => @fs.mkdir(entry.link.path.path.to_string())
        "different" => {
          let other = target_root.join("different-other")
          @fs.mkdir(other.to_string())
          @fs.symlink(
            target=other.relative(base=entry.managed_root.path.path).to_string(),
            entry.link.path.path.to_string(),
          )
        }
        "broken" =>
          @fs.symlink(target="missing-target", entry.link.path.path.to_string())
        _ => fail("unexpected fixture")
      }
    }
    let neighbor = entries[0].managed_root.path.path.join("foreign-neighbor")
    @fs.write_file(neighbor.to_string(), "keep", create_mode=CreateNew)
    let previous_state = OwnershipState::OwnershipState(entries)
    let desired_state = OwnershipState::OwnershipState([])
    let state_path = reconciliation_state_path(
      root.join("ownership-state.json"),
    )
    let mut checkpoint_count = 0
    let mut checkpoint_state = None

    let result = reconcile_skill_links(
      state_path~,
      desired_state~,
      previous_ownership=PreviousOwnership::Trusted(previous_state),
      checkpoint_ownership_state=fn(_path, state) {
        checkpoint_count = checkpoint_count + 1
        checkpoint_state = Some(state)
      },
    )

    debug_inspect(result.status, content="Partial")
    inspect(result.durable_state.entries.length(), content="0")
    inspect(checkpoint_count, content="7")
    inspect(checkpoint_state == Some(result.durable_state), content="true")
    inspect(result.notices.length(), content="4")
    inspect(@fs.read_file(neighbor.to_string()).text(), content="keep")
    inspect(
      @fs.read_file(entries[2].link.path.path.to_string()).text(),
      content="foreign",
    )
    debug_inspect(
      @fs.kind(entries[3].link.path.path.to_string(), follow_symlink=false),
      content="Directory",
    )
    debug_inspect(
      @fs.kind(entries[4].link.path.path.to_string(), follow_symlink=false),
      content="SymLink",
    )
    debug_inspect(
      @fs.kind(entries[5].link.path.path.to_string(), follow_symlink=false),
      content="SymLink",
    )
    for index in [0, 1, 6] {
      let kind = @fs.kind(
        entries[index].link.path.path.to_string(),
        follow_symlink=false,
      ) catch {
        _ => @fs.FileKind::Unknown
      }
      debug_inspect(kind, content="Unknown")
    }
    let removed_root_kind = @fs.kind(
      entries[6].managed_root.path.path.to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(removed_root_kind, content="Unknown")
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 8 - isolates stale deletion authority by ownership state" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-cross-lock-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("shared-skills")
    let target_a = root.join("target-a")
    let target_b = root.join("target-b")
    @fs.mkdir(managed_root.to_string(), recursive=true)
    @fs.mkdir(target_a.to_string(), recursive=true)
    @fs.mkdir(target_b.to_string(), recursive=true)
    let entry_a = stale_reconciliation_entry(managed_root, "a", target_a)
    let entry_b = stale_reconciliation_entry(managed_root, "b", target_b)
    @fs.symlink(
      target=entry_a.symlink_target.to_string(),
      entry_a.link.path.path.to_string(),
    )
    @fs.symlink(
      target=entry_b.symlink_target.to_string(),
      entry_b.link.path.path.to_string(),
    )
    let desired_state = OwnershipState::OwnershipState([])
    let result_a = reconcile_skill_links(
      state_path=reconciliation_state_path(root.join("state-a.json")),
      desired_state~,
      previous_ownership=Trusted(OwnershipState::OwnershipState([entry_a])),
      checkpoint_ownership_state=fn(_path, _state) { () },
    )
    debug_inspect(result_a.status, content="Complete")
    let removed_a = @fs.kind(
      entry_a.link.path.path.to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(removed_a, content="Unknown")
    debug_inspect(
      @fs.kind(entry_b.link.path.path.to_string(), follow_symlink=false),
      content="SymLink",
    )
    let result_b = reconcile_skill_links(
      state_path=reconciliation_state_path(root.join("state-b.json")),
      desired_state~,
      previous_ownership=Trusted(OwnershipState::OwnershipState([entry_b])),
      checkpoint_ownership_state=fn(_path, _state) { () },
    )
    debug_inspect(result_b.status, content="Complete")
    let removed_b = @fs.kind(
      entry_b.link.path.path.to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(removed_b, content="Unknown")
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 11 - retries stale omission after checkpoint failure" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-remove-fail-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("skills")
    let target = root.join("target")
    @fs.mkdir(managed_root.to_string(), recursive=true)
    @fs.mkdir(target.to_string(), recursive=true)
    let entry = stale_reconciliation_entry(managed_root, "stale", target)
    @fs.symlink(
      target=entry.symlink_target.to_string(),
      entry.link.path.path.to_string(),
    )
    let previous = OwnershipState::OwnershipState([entry])
    let desired_state = OwnershipState::OwnershipState([])
    let state_path = reconciliation_state_path(root.join("state.json"))
    let fail_checkpoint : async (@path.Path, OwnershipState) -> Unit raise StateStoreError = (
      path,
      _state,
    ) => raise StateStoreError::IO(path~, reason="remove checkpoint failed")
    let failed = reconcile_skill_links(
      state_path~,
      desired_state~,
      previous_ownership=Trusted(previous),
      checkpoint_ownership_state=fail_checkpoint,
    )
    debug_inspect(failed.status, content="Partial")
    inspect(failed.durable_state == previous, content="true")
    match failed.notices[0] {
      CheckpointFailed(operation=CheckpointOwnership, path~, reason~) => {
        inspect(path == state_path, content="true")
        inspect(reason, content="remove checkpoint failed")
      }
      _ => fail("expected stale checkpoint failure")
    }
    let removed = @fs.kind(
      entry.link.path.path.to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(removed, content="Unknown")
    let retried = reconcile_skill_links(
      state_path~,
      desired_state~,
      previous_ownership=Trusted(failed.durable_state),
      checkpoint_ownership_state=fn(_path, _state) { () },
    )
    debug_inspect(retried.status, content="Complete")
    inspect(retried.durable_state.entries.length(), content="0")
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 13 - rejects a replaced stale managed root" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-stale-root-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let recorded_root = root.join("recorded-skills")
    let outside_root = root.join("outside-skills")
    let target = root.join("target")
    @fs.mkdir(outside_root.to_string(), recursive=true)
    @fs.mkdir(target.to_string(), recursive=true)
    let entry = stale_reconciliation_entry(recorded_root, "install", target)
    @fs.symlink(
      target=target.relative(base=outside_root).to_string(),
      outside_root.join("install").to_string(),
    )
    @fs.symlink(target=outside_root.to_string(), recorded_root.to_string())
    let previous = OwnershipState::OwnershipState([entry])
    let mut checkpointed = false
    let result = reconcile_skill_links(
      state_path=reconciliation_state_path(root.join("state.json")),
      desired_state=OwnershipState::OwnershipState([]),
      previous_ownership=Trusted(previous),
      checkpoint_ownership_state=fn(_path, _state) { checkpointed = true },
    )
    debug_inspect(result.status, content="Partial")
    inspect(result.durable_state == previous, content="true")
    inspect(checkpointed, content="false")
    match result.notices[0] {
      OperationFailed(operation=VerifyContainment, path~, reason=_) =>
        inspect(path == recorded_root, content="true")
      _ => fail("expected stale-root containment failure")
    }
    debug_inspect(
      @fs.kind(outside_root.join("install").to_string(), follow_symlink=false),
      content="SymLink",
    )
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 16 - preserves a foreign replacement during stale final recheck" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-recheck-race-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("skills")
    let recorded_target = root.join("recorded-target")
    let foreign_target = root.join("foreign-target")
    @fs.mkdir(managed_root.to_string(), recursive=true)
    @fs.mkdir(recorded_target.to_string(), recursive=true)
    @fs.mkdir(foreign_target.to_string(), recursive=true)
    let entry = stale_reconciliation_entry(
      managed_root, "install", recorded_target,
    )
    @fs.symlink(
      target=entry.symlink_target.to_string(),
      entry.link.path.path.to_string(),
    )
    let mut link_kind_calls = 0
    let mut remove_called = false
    let checkpoints = []
    let io : LinkReconciliationIO = {
      mkdir: async fn(path) { @fs.mkdir(path.to_string(), recursive=true) },
      kind: async fn(path) {
        if path == entry.link.path.path {
          link_kind_calls = link_kind_calls + 1
          if link_kind_calls == 2 {
            @fs.remove(path.to_string())
            @fs.symlink(
              target=foreign_target.relative(base=managed_root).to_string(),
              path.to_string(),
            )
          }
        }
        @fs.kind(path.to_string(), follow_symlink=false)
      },
      realpath: async fn(path) { @path.Path(@fs.realpath(path.to_string())) },
      symlink: async fn(target, link) {
        @fs.symlink(target=target.to_string(), link.to_string())
      },
      remove: async fn(path) {
        remove_called = true
        @fs.remove(path.to_string())
      },
      checkpoint: fn(_path, state) { checkpoints.push(state) },
    }
    let result = reconcile_skill_links_with_io(
      io,
      reconciliation_state_path(root.join("state.json")),
      OwnershipState::OwnershipState([]),
      Trusted(OwnershipState::OwnershipState([entry])),
    )
    debug_inspect(result.status, content="Partial")
    inspect(remove_called, content="false")
    inspect(checkpoints.length(), content="1")
    inspect(checkpoints[0].entries.length(), content="0")
    inspect(result.durable_state.entries.length(), content="0")
    match result.notices[0] {
      ReplacedOwnedPathPreserved(path~) =>
        inspect(path == entry.link.path.path, content="true")
      _ => fail("expected final-recheck replacement notice")
    }
    inspect(
      @fs.realpath(entry.link.path.path.to_string()),
      content=@fs.realpath(foreign_target.to_string()),
    )
  }
}
