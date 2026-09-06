///|
fn reconciliation_state_path(path : @path.Path) -> OwnershipStatePath raise {
  OwnershipStatePath::OwnershipStatePath(path)
}

///|
async test "LinkReconciliation reconcile_skill_links 1 - creates a missing desired link and checkpoints ownership" {
  @async.with_task_group() <| group => {
    let temporary_root : @path.Path = @fs.tmpdir(
      prefix="c-plugin-reconcile-red-",
    )
    group.add_defer(() => @fs.rmdir(temporary_root.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary_root.to_string())
    let managed_root = root.join(".agents").join("skills")
    let link = managed_root.join("install")
    let target = root.join("cache").join("skills").join("install")
    let state_path = reconciliation_state_path(
      root.join(".agents").join("c-plugin-state.json"),
    )
    @fs.mkdir(target.to_string(), recursive=true)
    let entry = OwnershipEntry::OwnershipEntry(
      OwnershipLink::OwnershipLink(link),
      target.relative(base=managed_root),
      OwnershipResolvedTarget::OwnershipResolvedTarget(target),
      OwnershipManagedRoot::OwnershipManagedRoot(managed_root),
      OwnershipSource::from_local(
        LocalOwnershipSource::LocalOwnershipSource(
          RelativeSourcePath::RelativeSourcePath(
            @path.Path("vendor/repository"),
          ),
          PluginName::PluginName("plugin"),
          SkillName::SkillName("install"),
        ),
      ),
    )
    let desired_state = OwnershipState::OwnershipState([entry])
    let previous_state = OwnershipState::OwnershipState([])
    let mut checkpoint_path = None
    let mut checkpoint_state = None

    let result = reconcile_skill_links(
      state_path~,
      desired_state~,
      previous_ownership=PreviousOwnership::Trusted(previous_state),
      checkpoint_ownership_state=fn(path, state) {
        checkpoint_path = Some(path)
        checkpoint_state = Some(state)
      },
    )

    let link_kind = @fs.kind(link.to_string(), follow_symlink=false) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(link_kind, content="SymLink")
    inspect(
      @fs.realpath(link.to_string()),
      content=@fs.realpath(target.to_string()),
    )
    inspect(checkpoint_path == Some(state_path.path.path), content="true")
    inspect(checkpoint_state == Some(desired_state), content="true")
    debug_inspect(result.status, content="Complete")
    inspect(result.durable_state == desired_state, content="true")

    let mut second_checkpointed = false
    let second = reconcile_skill_links(
      state_path~,
      desired_state~,
      previous_ownership=PreviousOwnership::Trusted(result.durable_state),
      checkpoint_ownership_state=fn(_path, _state) {
        second_checkpointed = true
      },
    )
    inspect(second_checkpointed, content="false")
    debug_inspect(second.status, content="Complete")
    inspect(second.durable_state == result.durable_state, content="true")
  }
}

///|
enum UnmanagedCollisionFixture {
  File
  Directory
  SameTargetSymlink
  DifferentTargetSymlink
  BrokenSymlink
}

///|
fn stale_reconciliation_entry(
  managed_root : @path.Path,
  name : String,
  target : @path.Path,
) -> OwnershipEntry raise {
  OwnershipEntry::OwnershipEntry(
    OwnershipLink::OwnershipLink(managed_root.join(name)),
    target.relative(base=managed_root),
    OwnershipResolvedTarget::OwnershipResolvedTarget(target),
    OwnershipManagedRoot::OwnershipManagedRoot(managed_root),
    OwnershipSource::from_local(
      LocalOwnershipSource::LocalOwnershipSource(
        RelativeSourcePath::RelativeSourcePath(@path.Path("vendor/repository")),
        PluginName::PluginName("plugin"),
        SkillName::SkillName(name),
      ),
    ),
  )
}

///|
fn desired_owned_entry(
  managed_root : @path.Path,
  target : @path.Path,
  repository : String,
) -> OwnershipEntry raise {
  OwnershipEntry::OwnershipEntry(
    OwnershipLink::OwnershipLink(managed_root.join("install")),
    target.relative(base=managed_root),
    OwnershipResolvedTarget::OwnershipResolvedTarget(target),
    OwnershipManagedRoot::OwnershipManagedRoot(managed_root),
    OwnershipSource::from_local(
      LocalOwnershipSource::LocalOwnershipSource(
        RelativeSourcePath::RelativeSourcePath(@path.Path(repository)),
        PluginName::PluginName("plugin"),
        SkillName::SkillName("install"),
      ),
    ),
  )
}

///|
async test "LinkReconciliation reconcile_skill_links 7 - distinguishes unavailable ownership while creating only an absent link" {
  @async.with_task_group() <| group => {
    for mode in [PreviousOwnership::Missing, Corrupt(reason="invalid json")] {
      let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-unavailable-")
      group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
      let root : @path.Path = @fs.realpath(temporary.to_string())
      let managed_root = root.join("skills")
      let desired_target = root.join("desired-target")
      let absent_target = root.join("absent-target")
      let foreign_target = root.join("foreign-target")
      @fs.mkdir(managed_root.to_string(), recursive=true)
      @fs.mkdir(desired_target.to_string(), recursive=true)
      @fs.mkdir(absent_target.to_string(), recursive=true)
      @fs.mkdir(foreign_target.to_string(), recursive=true)
      let collision = stale_reconciliation_entry(
        managed_root, "collision", desired_target,
      )
      let absent = stale_reconciliation_entry(
        managed_root, "absent", absent_target,
      )
      @fs.symlink(
        target=foreign_target.relative(base=managed_root).to_string(),
        collision.link.path.path.to_string(),
      )
      let desired_state = OwnershipState::OwnershipState([collision, absent])
      let state_path = reconciliation_state_path(root.join("state.json"))
      let checkpoints = []
      let result = reconcile_skill_links(
        state_path~,
        desired_state~,
        previous_ownership=mode,
        checkpoint_ownership_state=fn(_path, state) { checkpoints.push(state) },
      )
      debug_inspect(result.status, content="Partial")
      inspect(checkpoints.length(), content="1")
      inspect(result.durable_state.entries.length(), content="1")
      inspect(
        result.durable_state.entries.get(
          OwnershipLinkIdentity::OwnershipLinkIdentity(absent.link.path),
        ) ==
        Some(absent),
        content="true",
      )
      inspect(result.notices.length(), content="2")
      match (mode, result.notices[0]) {
        (PreviousOwnership::Missing, PreviousOwnershipMissing(path~)) =>
          inspect(path == state_path, content="true")
        (Corrupt(_), PreviousOwnershipCorrupt(path~, reason=_)) =>
          inspect(path == state_path, content="true")
        _ => fail("expected distinct unavailable ownership notice")
      }
      inspect(
        @fs.realpath(collision.link.path.path.to_string()),
        content=@fs.realpath(foreign_target.to_string()),
      )
      inspect(
        @fs.realpath(absent.link.path.path.to_string()),
        content=@fs.realpath(absent_target.to_string()),
      )
    }
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 9 - rejects a symlink managed root without child mutation" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-root-link-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let physical_root = root.join("physical-skills")
    let managed_root = root.join("managed-skills")
    let target = root.join("target")
    @fs.mkdir(physical_root.to_string(), recursive=true)
    @fs.mkdir(target.to_string(), recursive=true)
    @fs.symlink(target=physical_root.to_string(), managed_root.to_string())
    let entry = desired_owned_entry(managed_root, target, "vendor/repo")
    let mut checkpointed = false
    let result = reconcile_skill_links(
      state_path=reconciliation_state_path(root.join("state.json")),
      desired_state=OwnershipState::OwnershipState([entry]),
      previous_ownership=Trusted(OwnershipState::OwnershipState([])),
      checkpoint_ownership_state=fn(_path, _state) { checkpointed = true },
    )
    debug_inspect(result.status, content="Partial")
    inspect(checkpointed, content="false")
    inspect(result.notices.length(), content="1")
    match result.notices[0] {
      OperationFailed(operation=VerifyContainment, path~, reason=_) =>
        inspect(path == managed_root, content="true")
      _ => fail("expected managed-root containment notice")
    }
    let child_kind = @fs.kind(
      physical_root.join("install").to_string(),
      follow_symlink=false,
    ) catch {
      _ => @fs.FileKind::Unknown
    }
    debug_inspect(child_kind, content="Unknown")
  }
}
