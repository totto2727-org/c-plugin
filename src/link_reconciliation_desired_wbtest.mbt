///|
async test "LinkReconciliation reconcile_skill_links 2 - preserves every unrecorded collision without adoption" {
  @async.with_task_group() <| group => {
    let fixtures = [
      UnmanagedCollisionFixture::File,
      Directory,
      SameTargetSymlink,
      DifferentTargetSymlink,
      BrokenSymlink,
    ]
    for fixture in fixtures {
      let temporary_root : @path.Path = @fs.tmpdir(
        prefix="c-plugin-reconcile-collision-",
      )
      group.add_defer(() => {
        @fs.rmdir(temporary_root.to_string(), recursive=true)
      })
      let root : @path.Path = @fs.realpath(temporary_root.to_string())
      let managed_root = root.join(".agents").join("skills")
      let link = managed_root.join("install")
      let target = root.join("cache").join("skills").join("install")
      let other_target = root.join("cache").join("skills").join("other")
      let state_path = reconciliation_state_path(
        root.join(".agents").join("c-plugin-state.json"),
      )
      @fs.mkdir(managed_root.to_string(), recursive=true)
      @fs.mkdir(target.to_string(), recursive=true)
      @fs.mkdir(other_target.to_string(), recursive=true)
      match fixture {
        File =>
          @fs.write_file(link.to_string(), "foreign", create_mode=CreateNew)
        Directory => @fs.mkdir(link.to_string())
        SameTargetSymlink =>
          @fs.symlink(
            target=target.relative(base=managed_root).to_string(),
            link.to_string(),
          )
        DifferentTargetSymlink =>
          @fs.symlink(
            target=other_target.relative(base=managed_root).to_string(),
            link.to_string(),
          )
        BrokenSymlink => @fs.symlink(target="missing-target", link.to_string())
      }
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
      let mut checkpointed = false
      let result = reconcile_skill_links(
        state_path~,
        desired_state~,
        previous_ownership=PreviousOwnership::Trusted(previous_state),
        checkpoint_ownership_state=fn(_path, _state) { checkpointed = true },
      )

      debug_inspect(result.status, content="Partial")
      inspect(result.durable_state == previous_state, content="true")
      inspect(checkpointed, content="false")
      inspect(result.notices.length(), content="1")
      match result.notices[0] {
        UnmanagedPathPreserved(path~) => inspect(path == link, content="true")
        _ => fail("expected unmanaged path notice")
      }
      match fixture {
        File =>
          inspect(@fs.read_file(link.to_string()).text(), content="foreign")
        Directory =>
          debug_inspect(
            @fs.kind(link.to_string(), follow_symlink=false),
            content="Directory",
          )
        SameTargetSymlink => {
          debug_inspect(
            @fs.kind(link.to_string(), follow_symlink=false),
            content="SymLink",
          )
          inspect(
            @fs.realpath(link.to_string()),
            content=@fs.realpath(target.to_string()),
          )
        }
        DifferentTargetSymlink => {
          debug_inspect(
            @fs.kind(link.to_string(), follow_symlink=false),
            content="SymLink",
          )
          inspect(
            @fs.realpath(link.to_string()),
            content=@fs.realpath(other_target.to_string()),
          )
        }
        BrokenSymlink =>
          debug_inspect(
            @fs.kind(link.to_string(), follow_symlink=false),
            content="SymLink",
          )
      }
    }
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 18 - force replaces files and links but preserves directories and neighbors" {
  @async.with_task_group() <| group => {
    let fixtures : Array[(UnmanagedCollisionFixture, Bool)] = [
      (File, false),
      (File, true),
      (SameTargetSymlink, false),
      (DifferentTargetSymlink, false),
      (BrokenSymlink, false),
      (Directory, false),
    ]
    for fixture in fixtures {
      let temporary_root : @path.Path = @fs.tmpdir(
        prefix="c-plugin-force-collision-",
      )
      group.add_defer(() => {
        @fs.rmdir(temporary_root.to_string(), recursive=true)
      })
      let root : @path.Path = @fs.realpath(temporary_root.to_string())
      let managed_root = root.join(".agents").join("skills")
      let link = managed_root.join("install")
      let neighbor = managed_root.join("neighbor")
      let target = root.join("cache").join("skills").join("install")
      let other_target = root.join("cache").join("skills").join("other")
      let state_path = reconciliation_state_path(
        root.join(".agents").join("c-plugin-state.json"),
      )
      @fs.mkdir(managed_root.to_string(), recursive=true)
      @fs.mkdir(target.to_string(), recursive=true)
      @fs.mkdir(other_target.to_string(), recursive=true)
      @fs.write_file(neighbor.to_string(), "neighbor", create_mode=CreateNew)
      match fixture.0 {
        File =>
          @fs.write_file(link.to_string(), "foreign", create_mode=CreateNew)
        Directory => {
          @fs.mkdir(link.to_string())
          @fs.write_file(
            link.join("keep").to_string(),
            "directory-content",
            create_mode=CreateNew,
          )
        }
        SameTargetSymlink =>
          @fs.symlink(
            target=target.relative(base=managed_root).to_string(),
            link.to_string(),
          )
        DifferentTargetSymlink =>
          @fs.symlink(
            target=other_target.relative(base=managed_root).to_string(),
            link.to_string(),
          )
        BrokenSymlink => @fs.symlink(target="missing-target", link.to_string())
      }
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
      let previous_state = if fixture.1 {
        desired_state
      } else {
        OwnershipState::empty()
      }
      let checkpoints : Array[OwnershipState] = []
      let result = reconcile_skill_links(
        state_path~,
        desired_state~,
        previous_ownership=PreviousOwnership::Trusted(previous_state),
        collision_policy=ReplaceNonDirectory,
        checkpoint_ownership_state=fn(_path, state) { checkpoints.push(state) },
      )

      inspect(@fs.read_file(neighbor.to_string()).text(), content="neighbor")
      match fixture.0 {
        Directory => {
          debug_inspect(result.status, content="Partial")
          inspect(result.durable_state == previous_state, content="true")
          inspect(checkpoints.length(), content="0")
          debug_inspect(
            @fs.kind(link.to_string(), follow_symlink=false),
            content="Directory",
          )
          inspect(
            @fs.read_file(link.join("keep").to_string()).text(),
            content="directory-content",
          )
        }
        _ => {
          debug_inspect(result.status, content="Complete")
          inspect(result.durable_state == desired_state, content="true")
          inspect(
            checkpoints.length(),
            content=if fixture.1 { "2" } else { "1" },
          )
          debug_inspect(
            @fs.kind(link.to_string(), follow_symlink=false),
            content="SymLink",
          )
          inspect(
            @fs.realpath(link.to_string()),
            content=@fs.realpath(target.to_string()),
          )
        }
      }
    }
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 4 - refreshes same-target ownership metadata" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-metadata-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("skills")
    let target = root.join("target")
    @fs.mkdir(managed_root.to_string(), recursive=true)
    @fs.mkdir(target.to_string(), recursive=true)
    let recorded = desired_owned_entry(managed_root, target, "vendor/old")
    let desired = desired_owned_entry(managed_root, target, "vendor/new")
    @fs.symlink(
      target=recorded.symlink_target.to_string(),
      recorded.link.path.path.to_string(),
    )
    let desired_state = OwnershipState::OwnershipState([desired])
    let checkpoints = []
    let result = reconcile_skill_links(
      state_path=reconciliation_state_path(root.join("state.json")),
      desired_state~,
      previous_ownership=Trusted(OwnershipState::OwnershipState([recorded])),
      checkpoint_ownership_state=fn(_path, state) { checkpoints.push(state) },
    )
    debug_inspect(result.status, content="Complete")
    inspect(checkpoints.length(), content="1")
    inspect(checkpoints[0] == desired_state, content="true")
    debug_inspect(
      @fs.kind(desired.link.path.path.to_string(), follow_symlink=false),
      content="SymLink",
    )
    inspect(
      @fs.realpath(desired.link.path.path.to_string()),
      content=@fs.realpath(target.to_string()),
    )
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 5 - replaces a verified owned target with omission then addition checkpoints" {
  @async.with_task_group() <| group => {
    let temporary : @path.Path = @fs.tmpdir(prefix="c-plugin-replace-")
    group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
    let root : @path.Path = @fs.realpath(temporary.to_string())
    let managed_root = root.join("skills")
    let old_target = root.join("old-target")
    let new_target = root.join("new-target")
    @fs.mkdir(managed_root.to_string(), recursive=true)
    @fs.mkdir(old_target.to_string(), recursive=true)
    @fs.mkdir(new_target.to_string(), recursive=true)
    let recorded = desired_owned_entry(managed_root, old_target, "vendor/repo")
    let desired = desired_owned_entry(managed_root, new_target, "vendor/repo")
    @fs.symlink(
      target=recorded.symlink_target.to_string(),
      recorded.link.path.path.to_string(),
    )
    let desired_state = OwnershipState::OwnershipState([desired])
    let checkpoints = []
    let result = reconcile_skill_links(
      state_path=reconciliation_state_path(root.join("state.json")),
      desired_state~,
      previous_ownership=Trusted(OwnershipState::OwnershipState([recorded])),
      checkpoint_ownership_state=fn(_path, state) { checkpoints.push(state) },
    )
    debug_inspect(result.status, content="Complete")
    inspect(checkpoints.length(), content="2")
    inspect(checkpoints[0].entries.length(), content="0")
    inspect(checkpoints[1] == desired_state, content="true")
    inspect(result.durable_state == desired_state, content="true")
    inspect(
      @fs.realpath(desired.link.path.path.to_string()),
      content=@fs.realpath(new_target.to_string()),
    )
  }
}

///|
async test "LinkReconciliation reconcile_skill_links 6 - preserves replaced and broken desired-owned paths while dropping ownership" {
  @async.with_task_group() <| group => {
    for fixture in ["replaced", "broken"] {
      let temporary : @path.Path = @fs.tmpdir(
        prefix="c-plugin-owned-\{fixture}-",
      )
      group.add_defer(() => @fs.rmdir(temporary.to_string(), recursive=true))
      let root : @path.Path = @fs.realpath(temporary.to_string())
      let managed_root = root.join("skills")
      let target = root.join("target")
      let other = root.join("other")
      @fs.mkdir(managed_root.to_string(), recursive=true)
      @fs.mkdir(target.to_string(), recursive=true)
      @fs.mkdir(other.to_string(), recursive=true)
      let entry = desired_owned_entry(managed_root, target, "vendor/repo")
      if fixture == "replaced" {
        @fs.symlink(
          target=other.relative(base=managed_root).to_string(),
          entry.link.path.path.to_string(),
        )
      } else {
        @fs.symlink(target="missing-target", entry.link.path.path.to_string())
      }
      let desired_state = OwnershipState::OwnershipState([entry])
      let checkpoints = []
      let result = reconcile_skill_links(
        state_path=reconciliation_state_path(root.join("state.json")),
        desired_state~,
        previous_ownership=Trusted(OwnershipState::OwnershipState([entry])),
        checkpoint_ownership_state=fn(_path, state) { checkpoints.push(state) },
      )
      debug_inspect(result.status, content="Partial")
      inspect(result.durable_state.entries.length(), content="0")
      inspect(checkpoints.length(), content="1")
      inspect(checkpoints[0].entries.length(), content="0")
      debug_inspect(
        @fs.kind(entry.link.path.path.to_string(), follow_symlink=false),
        content="SymLink",
      )
      if fixture == "replaced" {
        inspect(
          @fs.realpath(entry.link.path.path.to_string()),
          content=@fs.realpath(other.to_string()),
        )
      }
    }
  }
}
