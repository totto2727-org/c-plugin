///|
fn lock_root_json_path() -> @json.JsonPath raise {
  try {
    let _ : Bool = @json.from_json(Json::null())
    fail("expected JsonDecodeError")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((path, _)) => path
    _ => fail("unexpected error")
  }
}

///|
fn expect_json_rejection(
  action : () -> Unit raise,
  detail : String,
) -> Unit raise {
  try action() catch {
    _ => ()
  } noraise {
    _ => fail("expected JSON rejection: \{detail}")
  }
}

///|
test "GitHubRepository FromJson and ToJson - canonicalizes route" {
  let repository : GitHubRepository = @json.from_json(
    @json.parse("\"OpenAI/Codex\""),
  )
  inspect(repository.route(), content="openai/codex")
  let decoded : GitHubRepository = @json.from_json(repository.to_json())
  inspect(decoded == repository, content="true")
}

///|
test "identity FromJson - rejects invalid boundary values" {
  expect_json_rejection(
    fn() -> Unit raise {
      (@json.from_json(@json.parse("\"-owner/repository\"")) : GitHubRepository)
      |> ignore
    },
    "invalid GitHub owner boundary",
  )
  let repository_name = "r".repeat(101)
  expect_json_rejection(
    fn() -> Unit raise {
      (@json.from_json(repository_name.to_json()) : GitHubRepositoryName)
      |> ignore
    },
    "overlong GitHub repository name",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      (@json.from_json(@json.parse("\"../marketplace\"")) : RelativeSourcePath)
      |> ignore
    },
    "relative source path traversal",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      (@json.from_json(@json.parse("\"0123456789abcdef\"")) : CommitId)
      |> ignore
    },
    "invalid commit length",
  )
}

///|
test "Target FromJson and ToJson - preserves Path value" {
  let target : Target = @json.from_json(@json.parse("\".agents/skills\""))
  inspect(target.path.to_string(), content=".agents/skills")
  let decoded : Target = @json.from_json(target.to_json())
  inspect(decoded == target, content="true")
}

///|
let canonical_lock_json =
  #|{
  #|  "version": "2",
  #|  "targets": [
  #|    ".agents/skills",
  #|    ".cursor/skills"
  #|  ],
  #|  "repositories": [
  #|    {
  #|      "type": "github",
  #|      "repository": "openai/codex",
  #|      "marketplaceKind": "codex",
  #|      "commit": "0123456789abcdef0123456789abcdef01234567",
  #|      "plugins": [
  #|        {
  #|          "name": "c-plugin",
  #|          "path": "plugins/c-plugin",
  #|          "enabledSkills": [
  #|            "install",
  #|            "sync"
  #|          ]
  #|        }
  #|      ]
  #|    },
  #|    {
  #|      "type": "local",
  #|      "path": "vendor/plugin",
  #|      "marketplaceKind": "claude",
  #|      "plugins": []
  #|    }
  #|  ]
  #|}

///|
test "Lock FromJson and ToJson - canonical round trip is sorted" {
  let lock : Lock = @json.parse(canonical_lock_json) |> @json.from_json
  inspect(lock.to_pretty_json(), content=canonical_lock_json + "\n")
  let decoded : Lock = @json.from_json(lock.to_json())
  inspect(decoded == lock, content="true")
  inspect(
    decoded.targets.contains(Target::Target(".agents/skills")),
    content="true",
  )
}

///|
test "Lock FromJson and ToJson - sorts collections at the JSON boundary" {
  let text =
    #|{"version":"2","targets":[".cursor/skills",".agents/skills"],"repositories":[{"type":"local","path":"vendor/z-last","marketplaceKind":"claude","plugins":[{"name":"z-plugin","path":"plugins/z","enabledSkills":["sync","install"]},{"name":"a-plugin","path":"plugins/a","enabledSkills":[]}]},{"type":"github","repository":"a-owner/a-repo","marketplaceKind":"codex","commit":"0123456789abcdef0123456789abcdef01234567","plugins":[]}]}
  let lock : Lock = @json.from_json(@json.parse(text))
  let expected =
    #|{"version":"2","targets":[".agents/skills",".cursor/skills"],"repositories":[{"type":"github","repository":"a-owner/a-repo","marketplaceKind":"codex","commit":"0123456789abcdef0123456789abcdef01234567","plugins":[]},{"type":"local","path":"vendor/z-last","marketplaceKind":"claude","plugins":[{"name":"a-plugin","path":"plugins/a","enabledSkills":[]},{"name":"z-plugin","path":"plugins/z","enabledSkills":["install","sync"]}]}]}
  inspect(lock.to_json().stringify(), content=expected)
}

///|
test "Lock FromJson - nested failure preserves JSON path" {
  let invalid_text = "{\"version\":\"2\",\"targets\":[],\"repositories\":[{\"type\":\"github\",\"repository\":\"openai/codex\",\"marketplaceKind\":\"codex\",\"commit\":\"0123456789abcdef0123456789abcdef01234567\",\"plugins\":[{\"name\":\"c-plugin\",\"path\":\"plugins/c-plugin\",\"enabledSkills\":[1]}]}]}"
  let invalid = @json.parse(invalid_text)
  try {
    let _ : Lock = @json.from_json(invalid)
    fail("expected nested decode failure")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((path, _)) =>
      inspect(
        path.to_string(),
        content="/repositories/0/plugins/0/enabledSkills/0",
      )
    _ => fail("expected JsonDecodeError")
  }
}

///|
test "Lock FromJson - unsupported version preserves input" {
  let text = "{\"version\":\"3\",\"targets\":[],\"repositories\":[]}"
  let json = @json.parse(text)
  try {
    let _ : Lock = @json.from_json(json)
    fail("expected unsupported version failure")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((path, message)) => {
      inspect(path.to_string(), content="/version")
      inspect(message, content="unsupported lock version: 3")
    }
    _ => fail("expected JsonDecodeError")
  }
  inspect(json.stringify(), content=text)
}

///|
test "LockRepository FromJson - dispatches each top-level type" {
  let github_text = "{\"type\":\"github\",\"repository\":\"openai/codex\",\"marketplaceKind\":\"codex\",\"commit\":\"0123456789abcdef0123456789abcdef01234567\",\"plugins\":[]}"
  let local_text = "{\"type\":\"local\",\"path\":\"vendor/plugin\",\"marketplaceKind\":\"claude\",\"plugins\":[]}"
  let github : LockRepository = @json.from_json(@json.parse(github_text))
  let local_repository : LockRepository = @json.from_json(
    @json.parse(local_text),
  )
  match github {
    GitHub(_) => inspect(true, content="true")
    Local(_) => fail("expected GitHub repository")
  }
  match local_repository {
    Local(_) => inspect(true, content="true")
    GitHub(_) => fail("expected local repository")
  }
}

///|
test "LockRepository FromJson - preserves variant and nested error paths" {
  let prefixed_path = lock_root_json_path().add_key("request")
  try {
    let json = @json.parse(
      "{\"type\":\"local\",\"repository\":\"openai/codex\",\"marketplaceKind\":\"codex\",\"commit\":\"0123456789abcdef0123456789abcdef01234567\",\"plugins\":[]}",
    )
    let _ : GitHubLockRepository = @json.from_json(json, path=prefixed_path)
    fail("expected GitHub repository type mismatch")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((path, _)) =>
      inspect(path.to_string(), content="/request/type")
    _ => fail("expected JsonDecodeError")
  }
  try {
    let json = @json.parse(
      "{\"type\":\"github\",\"repository\":\"openai/codex\",\"marketplaceKind\":\"codex\",\"commit\":\"invalid\",\"plugins\":[]}",
    )
    let _ : LockRepository = @json.from_json(json, path=prefixed_path)
    fail("expected nested commit rejection")
  } catch {
    @json.JsonDecodeError::JsonDecodeError((path, _)) =>
      inspect(path.to_string(), content="/request/commit")
    _ => fail("expected JsonDecodeError")
  }
}

///|
test "lock FromJson - rejects strict schema failures" {
  expect_json_rejection(
    fn() -> Unit raise {
      let text =
        #|{"version":"2","targets":[".agents/skills",".agents/./skills"],"repositories":[]}
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "duplicate normalized target identity",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text =
        #|{"version":"2","targets":[],"repositories":[{"type":"local","path":"vendor/plugin","marketplaceKind":"claude","plugins":[{"name":"plugin","path":"plugins/first","enabledSkills":["sync","sync"]}]}]}
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "duplicate enabled skill identity",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text =
        #|{"version":"2","targets":[],"repositories":[{"type":"local","path":"vendor/plugin","marketplaceKind":"claude","plugins":[{"name":"plugin","path":"plugins/first","enabledSkills":[]},{"name":"plugin","path":"plugins/second","enabledSkills":[]}]}]}
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "duplicate plugin name identity",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text = "{\"version\":\"2\",\"targets\":[],\"repositories\":[{\"type\":\"gitlab\"}]}"
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "unknown repository type",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text = "{\"version\":\"2\",\"targets\":[],\"repositories\":[{\"type\":1}]}"
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "repository type with wrong JSON type",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text = "{\"version\":2,\"targets\":[],\"repositories\":[]}"
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "numeric lock version",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text = "{\"version\":\"2.5\",\"targets\":[],\"repositories\":[]}"
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "fractional lock version",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text = "{\"version\":\"2.0000000000000001\",\"targets\":[],\"repositories\":[]}"
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "precision-sensitive lock version",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text = "{\"type\":\"github\",\"repository\":\"openai/codex\",\"marketplaceKind\":\"codex\",\"plugins\":[]}"
      (@json.from_json(@json.parse(text)) : GitHubLockRepository) |> ignore
    },
    "missing GitHub commit",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text = "{\"type\":\"github\",\"repository\":\"openai/codex\",\"marketplaceKind\":\"codex\",\"commit\":null,\"plugins\":[]}"
      (@json.from_json(@json.parse(text)) : GitHubLockRepository) |> ignore
    },
    "null GitHub commit",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      (@json.from_json(@json.parse("\"unknown\"")) : MarketplaceKind) |> ignore
    },
    "unknown marketplace kind",
  )
  expect_json_rejection(
    fn() -> Unit raise {
      let text =
        #|{"version":"2","targets":[],"repositories":[{"type":"github","repository":"OpenAI/Codex","marketplaceKind":"codex","commit":"0123456789abcdef0123456789abcdef01234567","plugins":[]},{"type":"github","repository":"openai/codex","marketplaceKind":"claude","commit":"fedcba9876543210fedcba9876543210fedcba98","plugins":[]}]}
      (@json.from_json(@json.parse(text)) : Lock) |> ignore
    },
    "duplicate repository identity",
  )
}
