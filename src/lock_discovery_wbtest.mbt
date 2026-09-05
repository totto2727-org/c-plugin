///|
struct LockDiscoveryFixture {
  root : @path.Path
  paths : RuntimePaths
}

///|
test "path_is_within - accepts a normalized base itself" {
  let base : @path.Path = "/synthetic/home/workspace/./package"
  let target : @path.Path = "/synthetic/home/workspace/package"
  assert_true(path_is_within(base, target))
}

///|
test "path_is_within - accepts direct and deep normalized descendants" {
  let base : @path.Path = "/synthetic/home/workspace/package"
  let direct : @path.Path = "/synthetic/home/workspace/package/child"
  let deep : @path.Path = "/synthetic/home/workspace/package/child/../nested/deep"
  assert_true(path_is_within(base, direct))
  assert_true(path_is_within(base, deep))
}

///|
test "path_is_within - rejects a common lexical prefix sibling" {
  let base : @path.Path = "/synthetic/home/foo"
  let sibling : @path.Path = "/synthetic/home/foobar"
  assert_false(path_is_within(base, sibling))
}

///|
test "path_is_within - rejects a normalized escape" {
  let base : @path.Path = "/synthetic/home/workspace/package"
  let escaped : @path.Path = "/synthetic/home/workspace/package/../../outside"
  assert_false(path_is_within(base, escaped))
}

///|
async fn with_lock_discovery_fixture(
  action : async (LockDiscoveryFixture) -> Unit,
) -> Unit {
  let root : @path.Path = @fs.tmpdir(prefix="c-plugin-lock-discovery-")
  let home = root.join("home")
  let cwd = home.join("workspace").join("package").join("source")
  let cache_root = root.join("cache")
  @fs.mkdir(cwd.to_string(), recursive=true)
  @fs.mkdir(cache_root.to_string(), recursive=true)
  let fixture = {
    root,
    paths: RuntimePaths::RuntimePaths(home, cwd, cache_root),
  }
  action(fixture) catch {
    error => {
      @async.protect_from_cancel(async fn() {
        @fs.rmdir(root.to_string(), recursive=true)
      })
      raise error
    }
  }
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
async fn write_lock(path : @path.Path) -> @path.Path {
  @fs.mkdir(path.dirname().to_string(), recursive=true) catch {
    _ => ()
  }
  @fs.write_file(path.to_string(), "{}", create_mode=CreateOrTruncate)
  path
}

///|
async test "discover_locks - finds the nearest project lock below the synthetic home" {
  with_lock_discovery_fixture(async fn(fixture) {
    let outer_lock = write_lock(
      fixture.paths.home.path.join("workspace").join("c-plugin-lock.json"),
    )
    let nearest_lock = write_lock(
      fixture.paths.home.path
      .join("workspace")
      .join("package")
      .join("c-plugin-lock.json"),
    )
    let locks = discover_locks(
      fixture.paths,
      LockDiscoveryOptions::Project(recursive=false),
    )
    inspect(locks[0].to_string(), content=nearest_lock.to_string())
    assert_false(locks.contains(outer_lock))
  })
}

///|
async test "discover_locks - resolves the global lock exactly below the synthetic home" {
  with_lock_discovery_fixture(async fn(fixture) {
    let global_lock = write_lock(
      fixture.paths.home.path.join("c-plugin-lock.json"),
    )
    let _project_lock = write_lock(
      fixture.paths.home.path
      .join("workspace")
      .join("package")
      .join("c-plugin-lock.json"),
    )
    let locks = discover_locks(fixture.paths, LockDiscoveryOptions::Global)
    inspect(locks[0].to_string(), content=global_lock.to_string())
  })
}

///|
async test "discover_locks - includes the nearest project lock and visible descendants recursively" {
  with_lock_discovery_fixture(async fn(fixture) {
    let nearest_lock = write_lock(
      fixture.paths.home.path
      .join("workspace")
      .join("package")
      .join("c-plugin-lock.json"),
    )
    let child_lock = write_lock(
      fixture.paths.home.path
      .join("workspace")
      .join("package")
      .join("child")
      .join("c-plugin-lock.json"),
    )
    let nested_lock = write_lock(
      fixture.paths.home.path
      .join("workspace")
      .join("package")
      .join("child")
      .join("nested")
      .join("c-plugin-lock.json"),
    )
    let locks = discover_locks(
      fixture.paths,
      LockDiscoveryOptions::Project(recursive=true),
    )
    assert_true(locks.contains(nearest_lock))
    assert_true(locks.contains(child_lock))
    assert_true(locks.contains(nested_lock))
  })
}

///|
async test "discover_locks - excludes descendants in gitignored directories" {
  with_lock_discovery_fixture(async fn(fixture) {
    let project_root = fixture.paths.home.path.join("workspace").join("package")
    let nearest_lock = write_lock(project_root.join("c-plugin-lock.json"))
    @fs.write_file(
      project_root.join(".gitignore").to_string(),
      "ignored/\n",
      create_mode=CreateOrTruncate,
    )
    let visible_lock = write_lock(
      project_root.join("visible").join("c-plugin-lock.json"),
    )
    let ignored_lock = write_lock(
      project_root.join("ignored").join("c-plugin-lock.json"),
    )
    let locks = discover_locks(
      fixture.paths,
      LockDiscoveryOptions::Project(recursive=true),
    )
    assert_true(locks.contains(nearest_lock))
    assert_true(locks.contains(visible_lock))
    assert_false(locks.contains(ignored_lock))
  })
}

///|
async test "discover_locks - does not search for project locks above the synthetic home" {
  with_lock_discovery_fixture(async fn(fixture) {
    let outside_lock = write_lock(fixture.root.join("c-plugin-lock.json"))
    let detail = try {
      discover_locks(
        fixture.paths,
        LockDiscoveryOptions::Project(recursive=false),
      )
      |> ignore
      "no error"
    } catch {
      LockFileNotFound(scope=Project, boundary~) => boundary.to_string()
      _ => "wrong error"
    }
    inspect(detail, content=fixture.paths.home.path.to_string())
    assert_true(@fs.exists(outside_lock.to_string()))
  })
}

///|
async test "discover_locks - reports a typed error when no project lock exists" {
  with_lock_discovery_fixture(async fn(fixture) {
    let detail = try {
      discover_locks(
        fixture.paths,
        LockDiscoveryOptions::Project(recursive=false),
      )
      |> ignore
      "no error"
    } catch {
      LockFileNotFound(scope=Project, boundary~) => boundary.to_string()
      _ => "wrong error"
    }
    inspect(detail, content=fixture.paths.home.path.to_string())
  })
}

///|
async test "discover_locks - rejects a cwd outside the synthetic home" {
  with_lock_discovery_fixture(async fn(fixture) {
    let outside_cwd = fixture.root.join("outside").join("source")
    let outside_lock = write_lock(
      fixture.root.join("outside").join("c-plugin-lock.json"),
    )
    @fs.mkdir(outside_cwd.to_string(), recursive=true)
    let paths = RuntimePaths::RuntimePaths(
      fixture.paths.home.path,
      outside_cwd,
      fixture.paths.cache_root.path,
    )
    let detail = try {
      discover_locks(paths, LockDiscoveryOptions::Project(recursive=false))
      |> ignore
      "no error"
    } catch {
      LockFileNotFound(scope=Project, boundary~) => boundary.to_string()
      _ => "wrong error"
    }
    inspect(detail, content=fixture.paths.home.path.to_string())
    assert_true(@fs.exists(outside_lock.to_string()))
  })
}

///|
async test "discover_locks - reports a typed error when no global lock exists" {
  with_lock_discovery_fixture(async fn(fixture) {
    let detail = try {
      discover_locks(fixture.paths, LockDiscoveryOptions::Global) |> ignore
      "no error"
    } catch {
      LockFileNotFound(scope=Global, boundary~) => boundary.to_string()
      _ => "wrong error"
    }
    inspect(detail, content=fixture.paths.home.path.to_string())
  })
}
