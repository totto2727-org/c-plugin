///|
test "CacheScope SHA-256 dependency conforms to FIPS 180-4 vectors" {
  inspect(
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(""))),
    content="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  inspect(
    @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode("abc"))),
    content="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  inspect(
    @crypto.bytes_to_hex_string(
      @crypto.sha256(
        @utf8.encode("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
      ),
    ),
    content="248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
  )
}

///|
test "CacheScope scopes the normalized absolute lock path with the exact SHA-256 vector" {
  let scope = CacheScope::CacheScope(
    "/synthetic/work/project/./nested/../c-plugin-lock.json",
  )
  inspect(
    scope.scope_key,
    content="0998fb40de7b50184fd504e4df5d3a4199773315e8ff95b52ba45e518deac3db",
  )
  inspect(scope.scope_key.length(), content="64")
  inspect(
    scope.scope_key.all(char => {
      char.is_ascii_digit() || (char >= 'a' && char <= 'f')
    }),
    content="true",
  )
  inspect(
    scope.lock_path.to_string(),
    content="/synthetic/work/project/c-plugin-lock.json",
  )
}

///|
test "CacheScope gives moved lock files separate cache paths for the same repository" {
  let repository = GitHubRepository::from_route("OpenAI/Codex")
  let first_scope = CacheScope::CacheScope(
    "/synthetic/work/project-a/c-plugin-lock.json",
  )
  let second_scope = CacheScope::CacheScope(
    "/synthetic/work/project-b/c-plugin-lock.json",
  )
  inspect(first_scope.scope_key == second_scope.scope_key, content="false")
  inspect(
    first_scope.cache_path("/synthetic/cache", repository).to_string(),
    content="/synthetic/cache/9cf8eac041ac21c0a38688ed3b1d93bd19e088832111658920c40d2918f1d431/openai/codex",
  )
  inspect(
    first_scope.cache_path("/synthetic/cache", repository) ==
    second_scope.cache_path("/synthetic/cache", repository),
    content="false",
  )
}

///|
test "CacheScope cache path uses canonical GitHub repository components" {
  let scope = CacheScope::CacheScope(
    "/synthetic/work/project/c-plugin-lock.json",
  )
  let mixed_case = GitHubRepository::from_route("OpenAI/Codex")
  let lower_case = GitHubRepository::from_route("openai/codex")
  inspect(
    scope.cache_path("/synthetic/cache", mixed_case) ==
    scope.cache_path("/synthetic/cache", lower_case),
    content="true",
  )
  inspect(
    scope.cache_path("/synthetic/cache", mixed_case).to_string(),
    content="/synthetic/cache/0998fb40de7b50184fd504e4df5d3a4199773315e8ff95b52ba45e518deac3db/openai/codex",
  )
}

///|
test "CacheScope metadata uses the validated normalized lock identity" {
  let scope = CacheScope::CacheScope(
    "/synthetic/work/project/./c-plugin-lock.json",
  )
  json_inspect(scope.metadata(), content={
    "version": 1,
    "lockPath": "/synthetic/work/project/c-plugin-lock.json",
  })
}

///|
test "CacheScopeMetadata FromJson and ToJson - round trips the normalized lock identity" {
  let metadata = CacheScopeMetadata::CacheScopeMetadata(
    1, "/synthetic/work/project/./c-plugin-lock.json",
  )
  let decoded : CacheScopeMetadata = @json.from_json(ToJson::to_json(metadata))
  inspect(decoded == metadata, content="true")
  json_inspect(metadata, content={
    "version": 1,
    "lockPath": "/synthetic/work/project/c-plugin-lock.json",
  })
}

///|
test "CacheScopeMetadata FromJson - rejects an unsupported version" {
  let json = @json.parse(
    "{\"version\":2,\"lockPath\":\"/synthetic/work/c-plugin-lock.json\"}",
  )
  try {
    let _ : CacheScopeMetadata = @json.from_json(json)
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/version")
  } noraise {
    _ => fail("expected unsupported metadata version to fail")
  }
}

///|
test "CacheScopeMetadata FromJson - rejects a relative lock path" {
  let json = @json.parse(
    "{\"version\":1,\"lockPath\":\"synthetic/work/c-plugin-lock.json\"}",
  )
  try {
    let _ : CacheScopeMetadata = @json.from_json(json)
  } catch {
    @json.JsonDecodeError::JsonDecodeError((error_path, _)) =>
      inspect(error_path, content="/lockPath")
  } noraise {
    _ => fail("expected relative metadata lock path to fail")
  }
}

///|
test "CacheScope validates metadata versions and absolute paths" {
  try
    CacheScopeMetadata::CacheScopeMetadata(
      2, "/synthetic/work/project/c-plugin-lock.json",
    )
    |> ignore
  catch {
    UnsupportedMetadataVersion(version~) => inspect(version, content="2")
    _ => fail("expected UnsupportedMetadataVersion")
  } noraise {
    _ => fail("expected unsupported metadata version to fail")
  }
  try
    CacheScope::CacheScope("synthetic/work/c-plugin-lock.json") |> ignore
  catch {
    RelativePath(name~, path~) =>
      inspect(
        "\{name}:\{path}",
        content="lock path:synthetic/work/c-plugin-lock.json",
      )
    _ => fail("expected RelativePath")
  } noraise {
    _ => fail("expected relative lock path to fail")
  }
  let scope = CacheScope::CacheScope(
    "/synthetic/work/project/c-plugin-lock.json",
  )
  try
    scope.cache_path(
      "synthetic/cache",
      GitHubRepository::from_route("owner/repository"),
    )
    |> ignore
  catch {
    RelativePath(name~, path~) =>
      inspect("\{name}:\{path}", content="cache root:synthetic/cache")
    _ => fail("expected RelativePath")
  } noraise {
    _ => fail("expected relative cache root to fail")
  }
}
