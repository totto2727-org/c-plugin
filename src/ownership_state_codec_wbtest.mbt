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
test "OwnershipLiteralTarget 1 preserves a non-normalized relative symlink payload" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"a/../b","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"sync"}}]}
  let state : OwnershipState = @json.from_json(@json.parse(text))
  inspect(ToJson::to_json(state).stringify(), content=text)
}

///|
test "OwnershipLiteralTarget 2 preserves a absolute symlink payload" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"/absolute/target","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"openai/codex","plugin":"c-plugin","skill":"sync"}}]}
  let state : OwnershipState = @json.from_json(@json.parse(text))
  inspect(ToJson::to_json(state).stringify(), content=text)
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
test "OwnershipCodec 1 rejects relative link" {
  let text =
    #|{"link":".agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipEntry) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/link")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 2 rejects relative resolvedTarget" {
  let text =
    #|{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"cache/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipEntry) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/resolvedTarget")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 3 rejects relative managedRoot" {
  let text =
    #|{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":".agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipEntry) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/managedRoot")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 4 reports outside link relationship" {
  let text =
    #|{"link":"/home/alice/other/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipEntry) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/link")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 5 reports nested link relationship" {
  let text =
    #|{"link":"/home/alice/project/.agents/skills/nested/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipEntry) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/link")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 6 rejects normalized duplicate identities" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}},{"link":"/home/alice/project/.agents/skills/./sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}]}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/entries")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 7 preserves prefix and array index for relative link" {
  let text =
    #|{"version":"1","entries":[{"link":".agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}]}
  let json = @json.parse(text)
  let path = ownership_root_json_path().add_key("state")
  try (@json.from_json(json, path~) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/state/entries/0/link")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 8 preserves prefix and array index for nested link" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/nested/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}]}
  let json = @json.parse(text)
  let path = ownership_root_json_path().add_key("state")
  try (@json.from_json(json, path~) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/state/entries/0/link")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 9 preserves prefix for duplicate identities" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}},{"link":"/home/alice/project/.agents/skills/./sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}]}
  let json = @json.parse(text)
  let path = ownership_root_json_path().add_key("state")
  try (@json.from_json(json, path~) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/state/entries")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 10 rejects numeric version" {
  let text =
    #|{"version":1,"entries":[]}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/version")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 11 rejects unsupported version" {
  let text =
    #|{"version":"2","entries":[]}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/version")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 12 rejects precision sensitive version" {
  let text =
    #|{"version":"1.0000000000000001","entries":[]}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/version")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 13 rejects unknown source discriminator" {
  let text =
    #|{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"archive","repository":"OpenAI/Codex","plugin":"c-plugin","skill":"sync"}}
  let json = @json.parse(text)
  try (@json.from_json(json) : OwnershipEntry) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/source/type")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 14 preserves nested invalid plugin path" {
  let text =
    #|{"version":"1","entries":[{"link":"/home/alice/project/.agents/skills/sync","symlinkTarget":"../../../cache/skills/sync","resolvedTarget":"/home/alice/.cache/c-plugin/skills/sync","managedRoot":"/home/alice/project/.agents/skills","source":{"type":"github","repository":"OpenAI/Codex","plugin":"bad/plugin","skill":"sync"}}]}
  let json = @json.parse(text)
  let path = ownership_root_json_path().add_key("state")
  try (@json.from_json(json, path~) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/state/entries/0/source/plugin")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 15 preserves prefixed invalid local repository path" {
  let text =
    #|{"type":"local","repository":"../outside","plugin":"c-plugin","skill":"sync"}
  let json = @json.parse(text)
  let path = ownership_root_json_path().add_key("source")
  try (@json.from_json(json, path~) : OwnershipSource) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/source/repository")
  } noraise {
    _ => fail("expected ownership JsonDecodeError")
  }
}

///|
test "OwnershipCodec 16 preserves the incoming path for a missing entry field" {
  let json = @json.parse("{\"version\":\"1\",\"entries\":[{}]}")
  let path = ownership_root_json_path().add_key("ownership")
  try (@json.from_json(json, path~) : OwnershipState) |> ignore catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path.to_string(), content="/ownership/entries/0/link")
  } noraise {
    _ => fail("expected missing ownership field JsonDecodeError")
  }
}
