///|
test "OwnershipLink 2 normalizes an absolute path" {
  inspect(
    OwnershipLink::OwnershipLink("/workspace/skills/./sync").path.to_string(),
    content="/workspace/skills/sync",
  )
}

///|
test "OwnershipResolvedTarget 2 normalizes an absolute path" {
  inspect(
    OwnershipResolvedTarget::OwnershipResolvedTarget(
      "/cache/skills/../skills/sync",
    ).path.to_string(),
    content="/cache/skills/sync",
  )
}

///|
test "OwnershipManagedRoot 2 normalizes an absolute path" {
  inspect(
    OwnershipManagedRoot::OwnershipManagedRoot("/workspace/./skills").path.to_string(),
    content="/workspace/skills",
  )
}

///|
test "OwnershipStatePath OwnershipStatePath - normalizes an absolute path" {
  inspect(
    OwnershipStatePath::OwnershipStatePath(
      "/workspace/project/.agents/./c-plugin-state.json",
    ).path.to_string(),
    content="/workspace/project/.agents/c-plugin-state.json",
  )
}

///|
test "OwnershipLink 1 rejects relative input with its original cause" {
  try OwnershipLink::OwnershipLink("skills/sync") |> ignore catch {
    OwnershipLinkConstructionFailed(path~, cause~) => {
      inspect(path.to_string(), content="skills/sync")
      assert_true(cause is Failure(_))
    }
  } noraise {
    _ => fail("expected typed path construction failure")
  }
}

///|
test "OwnershipResolvedTarget 1 rejects relative input with its original cause" {
  try
    OwnershipResolvedTarget::OwnershipResolvedTarget("cache/sync") |> ignore
  catch {
    OwnershipResolvedTargetConstructionFailed(path~, cause~) => {
      inspect(path.to_string(), content="cache/sync")
      assert_true(cause is Failure(_))
    }
  } noraise {
    _ => fail("expected typed path construction failure")
  }
}

///|
test "OwnershipManagedRoot 1 rejects relative input with its original cause" {
  try
    OwnershipManagedRoot::OwnershipManagedRoot("workspace/skills") |> ignore
  catch {
    OwnershipManagedRootConstructionFailed(path~, cause~) => {
      inspect(path.to_string(), content="workspace/skills")
      assert_true(cause is Failure(_))
    }
  } noraise {
    _ => fail("expected typed path construction failure")
  }
}

///|
test "OwnershipStatePath 1 rejects relative input with its original cause" {
  try
    OwnershipStatePath::OwnershipStatePath(".agents/c-plugin-state.json")
    |> ignore
  catch {
    OwnershipStatePathConstructionFailed(path~, cause~) => {
      inspect(path.to_string(), content=".agents/c-plugin-state.json")
      assert_true(cause is Failure(_))
    }
  } noraise {
    _ => fail("expected typed path construction failure")
  }
}

///|
fn github_ownership_source() -> OwnershipSource raise {
  OwnershipSource::from_github(
    GitHubOwnershipSource::GitHubOwnershipSource(
      GitHubRepository::from_route("OpenAI/Codex"),
      PluginName::PluginName("c-plugin"),
      SkillName::SkillName("sync"),
    ),
  )
}

///|
fn ownership_entry(link : @path.Path) -> OwnershipEntry raise {
  ownership_entry_with(
    link,
    "../../../cache/skills/sync",
    "/home/alice/.cache/c-plugin/skills/sync",
    github_ownership_source(),
  )
}

///|
fn ownership_entry_with(
  link : @path.Path,
  symlink_target : @path.Path,
  resolved_target : @path.Path,
  source : OwnershipSource,
) -> OwnershipEntry raise {
  OwnershipEntry::OwnershipEntry(
    OwnershipLink::OwnershipLink(link),
    symlink_target,
    OwnershipResolvedTarget::OwnershipResolvedTarget(resolved_target),
    OwnershipManagedRoot::OwnershipManagedRoot(
      "/home/alice/project/.agents/skills",
    ),
    source,
  )
}

///|
test "OwnershipEntry Compare::compare - uses every Eq field as a tie breaker" {
  let link = "/home/alice/project/.agents/skills/sync"
  let base = ownership_entry(link)
  let changed_symlink = ownership_entry_with(
    link,
    "../../../other-cache/skills/sync",
    base.resolved_target.path.path,
    base.source,
  )
  let changed_target = ownership_entry_with(
    link,
    base.symlink_target,
    "/home/alice/.cache/c-plugin/skills/other-sync",
    base.source,
  )
  let changed_source = ownership_entry_with(
    link,
    base.symlink_target,
    base.resolved_target.path.path,
    OwnershipSource::from_local(
      LocalOwnershipSource::LocalOwnershipSource(
        RelativeSourcePath::RelativeSourcePath("vendor/c-plugin"),
        PluginName::PluginName("c-plugin"),
        SkillName::SkillName("sync"),
      ),
    ),
  )
  inspect(Compare::compare(base, base), content="0")
  inspect(Compare::compare(base, changed_symlink) != 0, content="true")
  inspect(Compare::compare(base, changed_target) != 0, content="true")
  inspect(Compare::compare(base, changed_source) != 0, content="true")
  inspect(base != changed_symlink, content="true")
  inspect(base != changed_target, content="true")
  inspect(base != changed_source, content="true")
  inspect(
    Compare::compare(
      OwnershipManagedRoot::OwnershipManagedRoot("/workspace/a"),
      OwnershipManagedRoot::OwnershipManagedRoot("/workspace/b"),
    ) !=
    0,
    content="true",
  )
}

///|
test "OwnershipEntry OwnershipEntry - normalizes absolute paths but preserves symlink target" {
  let entry = ownership_entry(
    "/home/alice/project/.agents/skills/../skills/sync",
  )
  inspect(
    entry.link.path.path.to_string(),
    content="/home/alice/project/.agents/skills/sync",
  )
  inspect(
    entry.symlink_target.to_string(),
    content="../../../cache/skills/sync",
  )
  inspect(
    entry.resolved_target.path.path.to_string(),
    content="/home/alice/.cache/c-plugin/skills/sync",
  )
  inspect(
    entry.managed_root.path.path.to_string(),
    content="/home/alice/project/.agents/skills",
  )
}

///|
test "OwnershipState entries - stores an immutable hash map" {
  let state = OwnershipState::OwnershipState([
    ownership_entry("/home/alice/project/.agents/skills/sync"),
  ])
  let entries = state.entries
  let added_entry = ownership_entry(
    "/home/alice/project/.agents/skills/install",
  )
  let expanded_entries = state.entries.add(
    OwnershipLinkIdentity(added_entry.link.path),
    added_entry,
  )
  inspect(entries.length(), content="1")
  inspect(expanded_entries.length(), content="2")
}

///|
test "OwnershipState equality - ignores entry order" {
  let sync = ownership_entry("/home/alice/project/.agents/skills/sync")
  let install = ownership_entry("/home/alice/project/.agents/skills/install")
  let state = OwnershipState::OwnershipState([sync, install])
  let reordered = OwnershipState::OwnershipState([install, sync])
  inspect(state == reordered, content="true")
}

///|
test "OwnershipLinkIdentity Compare::compare - uses normalized lexical path order" {
  let first = OwnershipLinkIdentity(
    OwnershipLink::OwnershipLink(
      "/home/alice/project/.agents/skills/other/../alpha",
    ).path,
  )
  let last = OwnershipLinkIdentity(
    OwnershipLink::OwnershipLink("/home/alice/project/.agents/skills/z").path,
  )
  inspect(Compare::compare(first, last), content="-1")
}

///|
test "OwnershipEntry 1 rejects a link outside its managed root with typed context" {
  let link = OwnershipLink::OwnershipLink(
    "/home/alice/project/.agents-other/skills/sync",
  )
  let managed_root = OwnershipManagedRoot::OwnershipManagedRoot(
    "/home/alice/project/.agents/skills",
  )
  let target = OwnershipResolvedTarget::OwnershipResolvedTarget("/cache/sync")
  let source = github_ownership_source()
  try
    OwnershipEntry::OwnershipEntry(
      link, "../../../cache/sync", target, managed_root, source,
    )
    |> ignore
  catch {
    OwnershipLinkOutsideManagedRoot(link=actual_link, managed_root=actual_root) => {
      assert_true(actual_link == link)
      assert_true(actual_root == managed_root)
    }
  } noraise {
    _ => fail("expected direct-child failure")
  }
}

///|
test "OwnershipEntry 2 rejects a link nested below its managed root with typed context" {
  let link = OwnershipLink::OwnershipLink(
    "/home/alice/project/.agents/skills/nested/sync",
  )
  let managed_root = OwnershipManagedRoot::OwnershipManagedRoot(
    "/home/alice/project/.agents/skills",
  )
  let target = OwnershipResolvedTarget::OwnershipResolvedTarget("/cache/sync")
  let source = github_ownership_source()
  try
    OwnershipEntry::OwnershipEntry(
      link, "../../../cache/sync", target, managed_root, source,
    )
    |> ignore
  catch {
    OwnershipLinkOutsideManagedRoot(link=actual_link, managed_root=actual_root) => {
      assert_true(actual_link == link)
      assert_true(actual_root == managed_root)
    }
  } noraise {
    _ => fail("expected direct-child failure")
  }
}

///|
test "OwnershipEntry 3 rejects a link equal to its managed root with typed context" {
  let link = OwnershipLink::OwnershipLink("/home/alice/project/.agents/skills")
  let managed_root = OwnershipManagedRoot::OwnershipManagedRoot(
    "/home/alice/project/.agents/skills",
  )
  let target = OwnershipResolvedTarget::OwnershipResolvedTarget("/cache/sync")
  let source = github_ownership_source()
  try
    OwnershipEntry::OwnershipEntry(
      link, "../../../cache/sync", target, managed_root, source,
    )
    |> ignore
  catch {
    OwnershipLinkOutsideManagedRoot(link=actual_link, managed_root=actual_root) => {
      assert_true(actual_link == link)
      assert_true(actual_root == managed_root)
    }
  } noraise {
    _ => fail("expected direct-child failure")
  }
}

///|
test "OwnershipState 1 rejects identical entries" {
  let first = ownership_entry("/home/alice/project/.agents/skills/sync")
  try OwnershipState::OwnershipState([first, first]) |> ignore catch {
    DuplicateOwnershipLink(identity~) =>
      inspect(
        identity.path.path.to_string(),
        content="/home/alice/project/.agents/skills/sync",
      )
  } noraise {
    _ => fail("expected duplicate ownership identity")
  }
}

///|
test "OwnershipState 2 rejects normalized duplicate links" {
  let first = ownership_entry("/home/alice/project/.agents/skills/sync")
  let second = ownership_entry("/home/alice/project/.agents/skills/./sync")
  try OwnershipState::OwnershipState([first, second]) |> ignore catch {
    DuplicateOwnershipLink(identity~) =>
      inspect(
        identity.path.path.to_string(),
        content="/home/alice/project/.agents/skills/sync",
      )
  } noraise {
    _ => fail("expected duplicate ownership identity")
  }
}

///|
test "OwnershipState 3 rejects a duplicate link with different metadata" {
  let first = ownership_entry("/home/alice/project/.agents/skills/sync")
  let second = ownership_entry_with(
    first.link.path.path,
    "other-target",
    "/cache/other",
    first.source,
  )
  try OwnershipState::OwnershipState([first, second]) |> ignore catch {
    DuplicateOwnershipLink(identity~) =>
      inspect(
        identity.path.path.to_string(),
        content="/home/alice/project/.agents/skills/sync",
      )
  } noraise {
    _ => fail("expected duplicate ownership identity")
  }
}

///|
test "OwnershipState 4 reports the first duplicate in input order" {
  let first = ownership_entry("/home/alice/project/.agents/skills/a")
  let second = ownership_entry("/home/alice/project/.agents/skills/b")
  try
    OwnershipState::OwnershipState([first, second, second, first]) |> ignore
  catch {
    DuplicateOwnershipLink(identity~) =>
      inspect(
        identity.path.path.to_string(),
        content="/home/alice/project/.agents/skills/b",
      )
  } noraise {
    _ => fail("expected duplicate ownership identity")
  }
}

///|
test "OwnershipState 5 accepts an empty ownership collection" {
  let state = OwnershipState::OwnershipState([])
  inspect(state.version, content="1")
  inspect(state.entries.length(), content="0")
}
