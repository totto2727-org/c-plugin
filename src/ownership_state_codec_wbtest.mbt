///|
fn ownership_root_json_path() -> @json.JsonPath raise {
  try {
    let _ : Bool = @json.from_json(Json::null())
    fail("expected JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((path, _)) => path
    _ => fail("unexpected error")
  }
}

///|
fn expect_ownership_rejection(
  action : () -> Unit raise,
  detail : String,
) -> Unit raise {
  try action() catch {
    _ => ()
  } noraise {
    _ => fail("expected ownership rejection: \{detail}")
  }
}

///|
test "OwnershipState ToJson::to_json - round trips ownership metadata" {
  let state = OwnershipState::OwnershipState([
    OwnershipEntry::OwnershipEntry(
      OwnershipLink::OwnershipLink("/home/alice/project/.agents/skills/./sync"),
      "../../../cache/skills/sync",
      OwnershipResolvedTarget::OwnershipResolvedTarget(
        "/home/alice/.cache/c-plugin/skills/sync",
      ),
      OwnershipManagedRoot::OwnershipManagedRoot(
        "/home/alice/project/.agents/skills",
      ),
      OwnershipSource::from_github(
        GitHubOwnershipSource::GitHubOwnershipSource(
          GitHubRepository::from_route("OpenAI/Codex"),
          PluginName::PluginName("c-plugin"),
          SkillName::SkillName("sync"),
        ),
      ),
    ),
  ])
  let decoded : OwnershipState = @json.from_json(ToJson::to_json(state))
  inspect(decoded == state, content="true")
  let empty = OwnershipState::OwnershipState([])
  inspect(
    ToJson::to_json(empty).stringify(),
    content="{\"version\":\"1\",\"entries\":[]}",
  )
}

///|
test "OwnershipState ToJson::to_json - round trips local ownership metadata" {
  let source = OwnershipSource::from_local(
    LocalOwnershipSource::LocalOwnershipSource(
      RelativeSourcePath::RelativeSourcePath("vendor/c-plugin"),
      PluginName::PluginName("c-plugin"),
      SkillName::SkillName("sync"),
    ),
  )
  let state = OwnershipState::OwnershipState([
    OwnershipEntry::OwnershipEntry(
      OwnershipLink::OwnershipLink("/home/alice/project/.agents/skills/sync"),
      "../../../vendor/c-plugin/skills/sync",
      OwnershipResolvedTarget::OwnershipResolvedTarget(
        "/home/alice/project/vendor/c-plugin/skills/sync",
      ),
      OwnershipManagedRoot::OwnershipManagedRoot(
        "/home/alice/project/.agents/skills",
      ),
      source,
    ),
  ])
  let decoded : OwnershipState = @json.from_json(ToJson::to_json(state))
  inspect(decoded == state, content="true")
}

///|
test "OwnershipState ToJson::to_json - preserves literal symlink targets" {
  for target in ["a/../b", "/absolute/target"] {
    let text = "{\"version\":\"1\",\"entries\":[{" +
      "\"link\":\"/home/alice/project/.agents/skills/sync\"," +
      "\"symlinkTarget\":\"\{target}\"," +
      "\"resolvedTarget\":\"/home/alice/.cache/c-plugin/skills/sync\"," +
      "\"managedRoot\":\"/home/alice/project/.agents/skills\"," +
      "\"source\":{\"type\":\"github\",\"repository\":\"openai/codex\"," +
      "\"plugin\":\"c-plugin\",\"skill\":\"sync\"}}]}"
    let state : OwnershipState = @json.from_json(@json.parse(text))
    inspect(ToJson::to_json(state).stringify(), content=text)
  }
}

///|
test "OwnershipState ToJson::to_json - sorts entries by link" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/z-last","symlinkTarget":"../../../cache/skills/z-last","resolvedTarget":"/home/alice/.cache/c-plugin/skills/z-last","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"z-last"}},{"link":"/home/alice/project/.agents/skills/a-first","symlinkTarget":"../../../cache/skills/a-first","resolvedTarget":"/home/alice/.cache/c-plugin/skills/a-first","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"a-first"}}]}
  let state : OwnershipState = @json.from_json(@json.parse(text))
  let expected =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/a-first","symlinkTarget":"../../../cache/skills/a-first","resolvedTarget":"/home/alice/.cache/c-plugin/skills/a-first","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"a-first"}},{"link":"/home/alice/project/.agents/skills/z-last","symlinkTarget":"../../../cache/skills/z-last","resolvedTarget":"/home/alice/.cache/c-plugin/skills/z-last","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"z-last"}}]}
  inspect(ToJson::to_json(state).stringify(), content=expected)
}

///|
test "OwnershipSource FromJson::from_json - rejects an invalid discriminator" {
  expect_ownership_rejection(
    fn() -> Unit raise {
      let json = @json.parse(
        "{\"type\":\"archive\",\"repository\":\"OpenAI/Codex\",\"plugin\":\"c-plugin\",\"skill\":\"sync\"}",
      )
      (@json.from_json(json) : OwnershipSource) |> ignore
    },
    "invalid source discriminator",
  )
}

///|
test "OwnershipSource FromJson::from_json - reports an invalid plugin at its exact path" {
  let json = @json.parse(
    "{\"type\":\"github\",\"repository\":\"OpenAI/Codex\",\"plugin\":\"bad/plugin\",\"skill\":\"sync\"}",
  )
  try {
    let _ : OwnershipSource = @json.from_json(json)
    fail("expected JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/plugin")
    _ => fail("unexpected error")
  }
}

///|
test "OwnershipSource FromJson::from_json - preserves a prefixed local repository path" {
  let json = @json.parse(
    "{\"type\":\"local\",\"repository\":\"../outside\",\"plugin\":\"c-plugin\",\"skill\":\"sync\"}",
  )
  let path = ownership_root_json_path().add_key("source")
  try {
    let _ : OwnershipSource = @json.from_json(json, path~)
    fail("expected JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/source/repository")
    _ => fail("unexpected error")
  }
}

///|
test "OwnershipEntry FromJson::from_json - reports invalid absolute fields at their exact paths" {
  let resolved_target_json = @json.parse(
    "{\"link\":\"/home/alice/project/.agents/skills/sync\",\"symlinkTarget\":\"../../../cache/skills/sync\",\"resolvedTarget\":\"cache/skills/sync\",\"managedRoot\":\"/home/alice/project/.agents/skills\",\"source\":{\"type\":\"github\",\"repository\":\"OpenAI/Codex\",\"plugin\":\"c-plugin\",\"skill\":\"sync\"}}",
  )
  try {
    let _ : OwnershipEntry = @json.from_json(resolved_target_json)
    fail("expected resolved target JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/resolvedTarget")
    _ => fail("unexpected error")
  }
  let managed_root_json = @json.parse(
    "{\"link\":\"/home/alice/project/.agents/skills/sync\",\"symlinkTarget\":\"../../../cache/skills/sync\",\"resolvedTarget\":\"/home/alice/.cache/c-plugin/skills/sync\",\"managedRoot\":\".agents/skills\",\"source\":{\"type\":\"github\",\"repository\":\"OpenAI/Codex\",\"plugin\":\"c-plugin\",\"skill\":\"sync\"}}",
  )
  try {
    let _ : OwnershipEntry = @json.from_json(managed_root_json)
    fail("expected managed root JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/managedRoot")
    _ => fail("unexpected error")
  }
}

///|
test "OwnershipEntry FromJson::from_json - reports a relative link at its exact path" {
  let json = @json.parse(
    "{\"link\":\".agents/skills/sync\",\"symlinkTarget\":\"../../../cache/skills/sync\",\"resolvedTarget\":\"/home/alice/.cache/c-plugin/skills/sync\",\"managedRoot\":\"/home/alice/project/.agents/skills\",\"source\":{\"type\":\"github\",\"repository\":\"OpenAI/Codex\",\"plugin\":\"c-plugin\",\"skill\":\"sync\"}}",
  )
  try {
    let _ : OwnershipEntry = @json.from_json(json)
    fail("expected JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/link")
    _ => fail("unexpected error")
  }
}

///|
test "OwnershipEntry FromJson::from_json - reports a managed-root direct-child violation at the link path" {
  let json = @json.parse(
    "{\"link\":\"/home/alice/project/.agents/skills/nested/sync\",\"symlinkTarget\":\"../../../../cache/skills/sync\",\"resolvedTarget\":\"/home/alice/.cache/c-plugin/skills/sync\",\"managedRoot\":\"/home/alice/project/.agents/skills\",\"source\":{\"type\":\"github\",\"repository\":\"OpenAI/Codex\",\"plugin\":\"c-plugin\",\"skill\":\"sync\"}}",
  )
  try {
    let _ : OwnershipEntry = @json.from_json(json)
    fail("expected JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/link")
    _ => fail("unexpected error")
  }
}

///|
test "OwnershipState FromJson::from_json - rejects unsupported version shapes" {
  expect_ownership_rejection(
    fn() -> Unit raise {
      let json = @json.parse("{\"version\":1,\"entries\":[]}")
      (@json.from_json(json) : OwnershipState) |> ignore
    },
    "numeric version",
  )
  expect_ownership_rejection(
    fn() -> Unit raise {
      let json = @json.parse("{\"version\":\"2\",\"entries\":[]}")
      (@json.from_json(json) : OwnershipState) |> ignore
    },
    "unsupported string version",
  )
  expect_ownership_rejection(
    fn() -> Unit raise {
      let json = @json.parse(
        "{\"version\":\"1.0000000000000001\",\"entries\":[]}",
      )
      (@json.from_json(json) : OwnershipState) |> ignore
    },
    "precision-sensitive version",
  )
}

///|
test "OwnershipState FromJson::from_json - rejects duplicate normalized links" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"sync"}},{"link":"/home/alice/project/.agents/skills/./sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"sync"}}]}
  expect_ownership_rejection(
    fn() -> Unit raise {
      (@json.from_json(@json.parse(text)) : OwnershipState) |> ignore
    },
    "duplicate normalized ownership link",
  )
}

///|
test "OwnershipState FromJson::from_json - retains the incoming JSON path" {
  let json = @json.parse("{\"version\":\"1\",\"entries\":[{}]}")
  let path = ownership_root_json_path().add_key("ownership")
  try {
    let _ : OwnershipState = @json.from_json(json, path~)
    fail("expected JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/ownership/entries/0/link")
    _ => fail("unexpected error")
  }
}
