///|
test "RuntimePaths RuntimePaths - normalizes injected synthetic roots" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home/./workspace/..", "/synthetic/work/../work/project", "/synthetic/cache/./repositories",
  )
  inspect(paths.home.path.to_string(), content="/synthetic/home")
  inspect(paths.cwd.path.to_string(), content="/synthetic/work/project")
  inspect(
    paths.cache_root.path.to_string(),
    content="/synthetic/cache/repositories",
  )
}

///|
test "RuntimePaths project paths - derive lock ownership state and managed skills" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home", "/synthetic/work", "/synthetic/cache/repositories",
  )
  let project_root : @path.Path = "/synthetic/work/project/./plugin"
  let ownership_state_path : OwnershipStatePath = paths.project_ownership_state_path(
    project_root,
  )
  inspect(
    paths.project_lock_path(project_root).to_string(),
    content="/synthetic/work/project/plugin/c-plugin-lock.json",
  )
  inspect(
    ownership_state_path.path.to_string(),
    content="/synthetic/work/project/plugin/.agents/c-plugin-state.json",
  )
  inspect(
    paths.project_managed_skill_root(project_root).to_string(),
    content="/synthetic/work/project/plugin/.agents/skills",
  )
}

///|
test "RuntimePaths global paths - derive all paths below synthetic home" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home/./user", "/synthetic/work", "/synthetic/cache/repositories",
  )
  let ownership_state_path : OwnershipStatePath = paths.global_ownership_state_path()
  inspect(
    paths.global_lock_path().to_string(),
    content="/synthetic/home/user/c-plugin-lock.json",
  )
  inspect(
    ownership_state_path.path.to_string(),
    content="/synthetic/home/user/.agents/c-plugin-state.json",
  )
  inspect(
    paths.global_managed_skill_root().to_string(),
    content="/synthetic/home/user/.agents/skills",
  )
}

///|
test "RuntimePaths RuntimePaths - retains the injected cache root" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home", "/synthetic/work", "/synthetic/cache/repositories",
  )
  inspect(
    paths.cache_root.path.to_string(),
    content="/synthetic/cache/repositories",
  )
}

///|
test "RuntimePaths RuntimePaths - rejects a relative home root" {
  let detail = try {
    RuntimePaths::RuntimePaths(
      "synthetic/home", "/synthetic/work", "/synthetic/cache/repositories",
    )
    |> ignore
    "no error"
  } catch {
    RelativeRoot(name~, path~) => "\{name}:\{path.to_string()}"
  }
  inspect(detail, content="home:synthetic/home")
}

///|
test "RuntimePaths RuntimePaths - rejects a relative working directory root" {
  let detail = try {
    RuntimePaths::RuntimePaths(
      "/synthetic/home", "synthetic/work", "/synthetic/cache/repositories",
    )
    |> ignore
    "no error"
  } catch {
    RelativeRoot(name~, path~) => "\{name}:\{path.to_string()}"
  }
  inspect(detail, content="cwd:synthetic/work")
}

///|
test "RuntimePaths RuntimePaths - rejects a relative cache root" {
  let detail = try {
    RuntimePaths::RuntimePaths(
      "/synthetic/home", "/synthetic/work", "synthetic/cache/repositories",
    )
    |> ignore
    "no error"
  } catch {
    RelativeRoot(name~, path~) => "\{name}:\{path.to_string()}"
  }
  inspect(detail, content="cache root:synthetic/cache/repositories")
}

///|
test "RuntimePaths project paths - reject a relative project root" {
  let paths = RuntimePaths::RuntimePaths(
    "/synthetic/home", "/synthetic/work", "/synthetic/cache/repositories",
  )
  let detail = try {
    paths.project_lock_path("synthetic/project") |> ignore
    "no error"
  } catch {
    RelativeRoot(name~, path~) => "\{name}:\{path.to_string()}"
  }
  inspect(detail, content="project root:synthetic/project")
}
