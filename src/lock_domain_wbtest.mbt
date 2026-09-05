///|
fn expect_rejection(action : () -> Unit raise, detail : String) -> Unit raise {
  try action() catch {
    _ => ()
  } noraise {
    _ => fail("expected rejection: \{detail}")
  }
}

///|
test "GitHubRepository from_route rejects empty and malformed components" {
  expect_rejection(
    fn() -> Unit raise { GitHubRepository::from_route("owner/") |> ignore },
    "empty repository component",
  )
  expect_rejection(
    fn() -> Unit raise {
      GitHubRepository::from_route("owner/repo/extra") |> ignore
    },
    "three route components",
  )
  expect_rejection(
    fn() -> Unit raise {
      GitHubRepository::from_route("owner/repo/name") |> ignore
    },
    "path-like route",
  )
}

///|
test "GitHubRepository from_route rejects path-like repository names" {
  expect_rejection(
    fn() -> Unit raise { GitHubRepository::from_route("owner/.") |> ignore },
    "dot repository",
  )
  expect_rejection(
    fn() -> Unit raise { GitHubRepository::from_route("owner/..") |> ignore },
    "dot-dot repository",
  )
}

///|
test "GitHubOwner enforces GitHub component boundaries" {
  inspect(GitHubOwner::GitHubOwner("a".repeat(39)).value.length(), content="39")
  expect_rejection(
    fn() -> Unit raise { GitHubOwner::GitHubOwner("-owner") |> ignore },
    "leading hyphen",
  )
  expect_rejection(
    fn() -> Unit raise { GitHubOwner::GitHubOwner("owner-") |> ignore },
    "trailing hyphen",
  )
  expect_rejection(
    fn() -> Unit raise { GitHubOwner::GitHubOwner("owner--name") |> ignore },
    "consecutive hyphens",
  )
  expect_rejection(
    fn() -> Unit raise { GitHubOwner::GitHubOwner("a".repeat(40)) |> ignore },
    "length 40",
  )
}

///|
test "GitHubRepositoryName enforces GitHub length boundary" {
  inspect(
    GitHubRepositoryName::GitHubRepositoryName("a".repeat(100)).value.length(),
    content="100",
  )
  expect_rejection(
    fn() -> Unit raise {
      GitHubRepositoryName::GitHubRepositoryName("a".repeat(101)) |> ignore
    },
    "length 101",
  )
}

///|
test "relative paths reject traversal and absolute paths" {
  expect_rejection(
    fn() -> Unit raise {
      RelativeSourcePath::RelativeSourcePath("../outside") |> ignore
    },
    "source parent traversal",
  )
  expect_rejection(
    fn() -> Unit raise {
      RelativePluginPath::RelativePluginPath("plugin/../outside") |> ignore
    },
    "plugin parent traversal",
  )
  expect_rejection(
    fn() -> Unit raise {
      RelativeSourcePath::RelativeSourcePath("/absolute/repository") |> ignore
    },
    "absolute source path",
  )
  expect_rejection(
    fn() -> Unit raise {
      RelativePluginPath::RelativePluginPath("/absolute/plugin") |> ignore
    },
    "absolute plugin path",
  )
  expect_rejection(
    fn() -> Unit raise { Target::Target("../outside") |> ignore },
    "target parent traversal",
  )
  expect_rejection(
    fn() -> Unit raise { Target::Target("/absolute/target") |> ignore },
    "absolute target path",
  )
}

///|
test "domain names reject empty and slash values" {
  expect_rejection(
    fn() -> Unit raise { PluginName::PluginName("") |> ignore },
    "empty plugin",
  )
  expect_rejection(
    fn() -> Unit raise { PluginName::PluginName("plugin/name") |> ignore },
    "path-like plugin",
  )
  expect_rejection(
    fn() -> Unit raise { SkillName::SkillName("") |> ignore },
    "empty skill",
  )
  expect_rejection(
    fn() -> Unit raise { SkillName::SkillName("skill/name") |> ignore },
    "path-like skill",
  )
}

///|
test "PluginName Compare::compare - uses lexical order" {
  let alpha = PluginName::PluginName("alpha")
  let z = PluginName::PluginName("z")
  inspect(alpha.compare(z), content="-1")
}

///|
test "SkillName Compare::compare - uses lexical order" {
  let install = SkillName::SkillName("install")
  let sync = SkillName::SkillName("sync")
  inspect(install.compare(sync), content="-1")
}

///|
test "Target Compare::compare - uses normalized lexical path order" {
  let agents = Target::Target("project/.agents")
  let cursor = Target::Target("project/.cursor")
  inspect(agents.compare(cursor), content="-1")
}

///|
test "RepositoryIdentity Compare::compare - orders type then identity" {
  let github = RepositoryIdentity::GitHubIdentity(
    GitHubRepository::from_route("alpha/z"),
  )
  let later_github = RepositoryIdentity::GitHubIdentity(
    GitHubRepository::from_route("z/a"),
  )
  let local_repository = RepositoryIdentity::LocalIdentity(
    RelativeSourcePath::RelativeSourcePath("alpha"),
  )
  inspect(github.compare(later_github), content="-1")
  inspect(later_github.compare(local_repository), content="-1")
}

///|
test "CommitId rejects bad length and hexadecimal boundaries" {
  expect_rejection(
    fn() -> Unit raise {
      CommitId::CommitId("0123456789abcdef0123456789abcdef0123456") |> ignore
    },
    "39-character commit",
  )
  expect_rejection(
    fn() -> Unit raise {
      CommitId::CommitId("0123456789abcdef0123456789abcdef012345678") |> ignore
    },
    "41-character commit",
  )
  expect_rejection(
    fn() -> Unit raise {
      CommitId::CommitId("g123456789abcdef0123456789abcdef01234567") |> ignore
    },
    "non-hexadecimal commit",
  )
}

///|
test "SkillName preserves the c-plugin skill namespace" {
  inspect(SkillName::SkillName("c-plugin").value, content="c-plugin")
}

///|
test "path identity Hash::hash - matches normalized equality" {
  let target = Target::Target(".agents/skills")
  let equivalent_target = Target::Target(".agents/./skills")
  inspect(target == equivalent_target, content="true")
  inspect(target.hash() == equivalent_target.hash(), content="true")
  let source = RelativeSourcePath::RelativeSourcePath("vendor/plugin")
  let equivalent_source = RelativeSourcePath::RelativeSourcePath(
    "vendor/./plugin",
  )
  inspect(source == equivalent_source, content="true")
  inspect(source.hash() == equivalent_source.hash(), content="true")
  let plugin_path = RelativePluginPath::RelativePluginPath("plugins/example")
  let equivalent_plugin_path = RelativePluginPath::RelativePluginPath(
    "plugins/./example",
  )
  inspect(plugin_path == equivalent_plugin_path, content="true")
  inspect(plugin_path.hash() == equivalent_plugin_path.hash(), content="true")
}

///|
test "lock domain equality ignores collection input order" {
  let plugin = Plugin::Plugin(
    PluginName::PluginName("c-plugin"),
    RelativePluginPath::RelativePluginPath("plugins/c-plugin"),
    [SkillName::SkillName("install"), SkillName::SkillName("sync")],
  )
  let github = LockRepository::github(
    GitHubLockRepository::GitHubLockRepository(
      GitHubRepository::from_route("OpenAI/Codex"),
      MarketplaceKind::codex(),
      CommitId::CommitId("0123456789ABCDEF0123456789abcdef01234567"),
      [plugin],
    ),
  )
  let local_repository = LockRepository::from_local(
    LocalLockRepository::LocalLockRepository(
      RelativeSourcePath::RelativeSourcePath("vendor/plugin"),
      MarketplaceKind::claude(),
      [
        Plugin::Plugin(
          PluginName::PluginName("local"),
          RelativePluginPath::RelativePluginPath("plugin"),
          [],
        ),
      ],
    ),
  )
  let lock = Lock::Lock(
    [Target::Target(".agents/skills"), Target::Target(".cursor/skills")],
    [github, local_repository],
  )
  let reordered_plugin = Plugin::Plugin(
    PluginName::PluginName("c-plugin"),
    RelativePluginPath::RelativePluginPath("plugins/c-plugin"),
    [SkillName::SkillName("sync"), SkillName::SkillName("install")],
  )
  inspect(plugin == reordered_plugin, content="true")
  let second_plugin = Plugin::Plugin(
    PluginName::PluginName("second"),
    RelativePluginPath::RelativePluginPath("plugins/second"),
    [],
  )
  let ordered_github = GitHubLockRepository::GitHubLockRepository(
    GitHubRepository::from_route("openai/codex"),
    MarketplaceKind::codex(),
    CommitId::CommitId("0123456789abcdef0123456789abcdef01234567"),
    [plugin, second_plugin],
  )
  let reordered_github = GitHubLockRepository::GitHubLockRepository(
    GitHubRepository::from_route("openai/codex"),
    MarketplaceKind::codex(),
    CommitId::CommitId("0123456789abcdef0123456789abcdef01234567"),
    [second_plugin, plugin],
  )
  inspect(ordered_github == reordered_github, content="true")
  let ordered_local = LocalLockRepository::LocalLockRepository(
    RelativeSourcePath::RelativeSourcePath("vendor/plugin"),
    MarketplaceKind::claude(),
    [plugin, second_plugin],
  )
  let reordered_local = LocalLockRepository::LocalLockRepository(
    RelativeSourcePath::RelativeSourcePath("vendor/plugin"),
    MarketplaceKind::claude(),
    [second_plugin, plugin],
  )
  inspect(ordered_local == reordered_local, content="true")
  let target_reordered_lock = Lock::Lock(
    [Target::Target(".cursor/skills"), Target::Target(".agents/skills")],
    [github, local_repository],
  )
  inspect(lock == target_reordered_lock, content="true")
  let repository_reordered_lock = Lock::Lock(
    [Target::Target(".agents/skills"), Target::Target(".cursor/skills")],
    [local_repository, github],
  )
  inspect(lock == repository_reordered_lock, content="true")
  inspect(lock.version, content="2")
  inspect(
    lock.targets.contains(Target::Target(".agents/skills")),
    content="true",
  )
  match lock.repositories[github.identity()] {
    LockRepository::GitHub(repository) => {
      inspect(repository.repository.owner.value, content="openai")
      inspect(repository.repository.name.value, content="codex")
      inspect(repository.repository.route(), content="openai/codex")
      inspect(
        repository.commit.value,
        content="0123456789abcdef0123456789abcdef01234567",
      )
      inspect(
        repository.plugins[plugin.name].enabled_skills.contains(
          SkillName::SkillName("install"),
        ),
        content="true",
      )
    }
    LockRepository::Local(_) => fail("expected GitHub repository")
  }
}

///|
test "aggregate collections are immutable values" {
  let plugin = Plugin::Plugin(
    PluginName::PluginName("plugin"),
    RelativePluginPath::RelativePluginPath("plugin"),
    [SkillName::SkillName("install")],
  )
  let expanded_skills = plugin.enabled_skills.add(SkillName::SkillName("sync"))
  inspect(plugin.enabled_skills.length(), content="1")
  inspect(expanded_skills.length(), content="2")
  let github = GitHubLockRepository::GitHubLockRepository(
    GitHubRepository::from_route("openai/codex"),
    MarketplaceKind::codex(),
    CommitId::CommitId("0123456789abcdef0123456789abcdef01234567"),
    [plugin],
  )
  let github_extra = Plugin::Plugin(
    PluginName::PluginName("github-extra"),
    RelativePluginPath::RelativePluginPath("github-extra"),
    [],
  )
  let expanded_github_plugins = github.plugins.add(
    github_extra.name,
    github_extra,
  )
  inspect(github.plugins.length(), content="1")
  inspect(expanded_github_plugins.length(), content="2")
  let local_repository = LocalLockRepository::LocalLockRepository(
    RelativeSourcePath::RelativeSourcePath("vendor/plugin"),
    MarketplaceKind::claude(),
    [plugin],
  )
  let local_extra = Plugin::Plugin(
    PluginName::PluginName("local-extra"),
    RelativePluginPath::RelativePluginPath("local-extra"),
    [],
  )
  let expanded_local_plugins = local_repository.plugins.add(
    local_extra.name,
    local_extra,
  )
  inspect(local_repository.plugins.length(), content="1")
  inspect(expanded_local_plugins.length(), content="2")
  let lock = Lock::Lock([Target::Target(".agents/skills")], [
    LockRepository::github(github),
  ])
  let expanded_targets = lock.targets.add(Target::Target(".cursor/skills"))
  let added_repository = LockRepository::from_local(local_repository)
  let expanded_repositories = lock.repositories.add(
    added_repository.identity(),
    added_repository,
  )
  inspect(lock.targets.length(), content="1")
  inspect(lock.repositories.length(), content="1")
  inspect(expanded_targets.length(), content="2")
  inspect(expanded_repositories.length(), content="2")
}

///|
test "lock rejects duplicate target repository plugin and skill identities" {
  let target = Target::Target(".agents/skills")
  let equivalent_target = Target::Target(".agents/./skills")
  expect_rejection(
    fn() -> Unit raise { Lock::Lock([target, equivalent_target], []) |> ignore },
    "normalized target identity",
  )
  let duplicate_skills = [
    SkillName::SkillName("sync"),
    SkillName::SkillName("sync"),
  ]
  expect_rejection(
    fn() -> Unit raise {
      Plugin::Plugin(
        PluginName::PluginName("plugin"),
        RelativePluginPath::RelativePluginPath("plugin"),
        duplicate_skills,
      )
      |> ignore
    },
    "enabled skill identity",
  )
  let first_plugin = Plugin::Plugin(
    PluginName::PluginName("plugin"),
    RelativePluginPath::RelativePluginPath("first/plugin"),
    [],
  )
  let same_plugin_identity = Plugin::Plugin(
    PluginName::PluginName("plugin"),
    RelativePluginPath::RelativePluginPath("second/plugin"),
    [SkillName::SkillName("different-skill")],
  )
  expect_rejection(
    fn() -> Unit raise {
      GitHubLockRepository::GitHubLockRepository(
        GitHubRepository::from_route("owner/repo"),
        MarketplaceKind::claude(),
        CommitId::CommitId("0123456789abcdef0123456789abcdef01234567"),
        [first_plugin, same_plugin_identity],
      )
      |> ignore
    },
    "plugin name identity",
  )
  let first_repository = LockRepository::github(
    GitHubLockRepository::GitHubLockRepository(
      GitHubRepository::from_route("owner/repo"),
      MarketplaceKind::claude(),
      CommitId::CommitId("0123456789abcdef0123456789abcdef01234567"),
      [],
    ),
  )
  let same_repository_identity = LockRepository::github(
    GitHubLockRepository::GitHubLockRepository(
      GitHubRepository::from_route("OWNER/REPO"),
      MarketplaceKind::cursor(),
      CommitId::CommitId("fedcba9876543210fedcba9876543210fedcba98"),
      [],
    ),
  )
  expect_rejection(
    fn() -> Unit raise {
      Lock::Lock([], [first_repository, same_repository_identity]) |> ignore
    },
    "canonical repository identity",
  )
}
