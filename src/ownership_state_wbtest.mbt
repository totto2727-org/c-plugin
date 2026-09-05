///|
test "Ownership path values OwnershipLink - normalize absolute paths" {
  inspect(
    OwnershipLink::OwnershipLink("/workspace/skills/./sync").path.to_string(),
    content="/workspace/skills/sync",
  )
  inspect(
    OwnershipResolvedTarget::OwnershipResolvedTarget(
      "/cache/skills/../skills/sync",
    ).path.to_string(),
    content="/cache/skills/sync",
  )
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
test "panic_OwnershipLink OwnershipLink - rejects a relative path" {
  try! (OwnershipLink::OwnershipLink("skills/sync") |> ignore)
}

///|
test "panic_OwnershipResolvedTarget OwnershipResolvedTarget - rejects a relative path" {
  try! (OwnershipResolvedTarget::OwnershipResolvedTarget("cache/sync") |> ignore)
}

///|
test "panic_OwnershipManagedRoot OwnershipManagedRoot - rejects a relative path" {
  try! (OwnershipManagedRoot::OwnershipManagedRoot("workspace/skills") |> ignore)
}

///|
test "panic_OwnershipStatePath OwnershipStatePath - rejects a relative path" {
  try! (OwnershipStatePath::OwnershipStatePath(".agents/c-plugin-state.json")
  |> ignore)
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
  inspect(base.compare(base), content="0")
  inspect(base.compare(changed_symlink) != 0, content="true")
  inspect(base.compare(changed_target) != 0, content="true")
  inspect(base.compare(changed_source) != 0, content="true")
  inspect(base != changed_symlink, content="true")
  inspect(base != changed_target, content="true")
  inspect(base != changed_source, content="true")
  inspect(
    OwnershipManagedRoot::OwnershipManagedRoot("/workspace/a").compare(
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
  inspect(first.compare(last), content="-1")
}

///|
test "OwnershipEntry OwnershipEntry - rejects a link outside managed root" {
  expect_ownership_rejection(
    fn() -> Unit raise {
      ownership_entry("/home/alice/project/.agents-other/skills/sync") |> ignore
    },
    "link outside managed root",
  )
}

///|
test "OwnershipEntry OwnershipEntry - rejects a nested link below a managed skill root" {
  expect_ownership_rejection(
    fn() -> Unit raise {
      ownership_entry("/home/alice/project/.agents/skills/nested/sync")
      |> ignore
    },
    "nested link below managed root",
  )
}

///|
test "OwnershipState OwnershipState - rejects duplicate normalized links" {
  expect_ownership_rejection(
    fn() -> Unit raise {
      OwnershipState::OwnershipState([
        ownership_entry("/home/alice/project/.agents/skills/sync"),
        ownership_entry("/home/alice/project/.agents/skills/./sync"),
      ])
      |> ignore
    },
    "duplicate normalized links",
  )
}
