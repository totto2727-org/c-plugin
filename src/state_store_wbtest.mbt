///|
fn empty_test_lock() -> Lock raise {
  Lock::Lock([], [])
}

///|
fn alternate_test_lock() -> Lock raise {
  Lock::Lock([Target::Target(".agents/skills")], [])
}

///|
async test "StateStore create_lock_exclusive - creates once and preserves existing bytes" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("nested").join("c-plugin-lock.json")
    create_lock_exclusive(path, empty_test_lock())
    let original = @fs.read_file(path.to_string()).text()
    try create_lock_exclusive(path, alternate_test_lock()) catch {
      StateStoreError::AlreadyExists(path=error_path) =>
        inspect(error_path == path, content="true")
      _ => fail("expected AlreadyExists")
    } noraise {
      _ => fail("second exclusive create must fail")
    }
    inspect(@fs.read_file(path.to_string()).text(), content=original)
  }
}

///|
async test "StateStore write_lock_atomic - replaces the target and removes its temporary sibling" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("c-plugin-lock.json")
    @fs.write_file(path.to_string(), "old bytes", create_mode=CreateNew)
    let lock = alternate_test_lock()
    write_lock_atomic(path, lock)
    inspect(
      @fs.read_file(path.to_string()).text(),
      content=lock.to_pretty_json(),
    )
    let temporary_path = path
      .dirname()
      .join(path.basename().to_owned() + ".tmp")
    inspect(@fs.exists(temporary_path.to_string()), content="false")
    inspect(load_lock(path) == lock, content="true")
  }
}

///|
async test "StateStore write_ownership_state_atomic - replaces the target and removes its temporary sibling" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("nested").join("c-plugin-state.json")
    let state = OwnershipState::OwnershipState([])
    write_ownership_state_atomic(path, state)
    inspect(load_ownership_state(path) == state, content="true")
    let temporary_path = path
      .dirname()
      .join(path.basename().to_owned() + ".tmp")
    inspect(@fs.exists(temporary_path.to_string()), content="false")
  }
}

///|
async test "StateStore load_lock - corrupt bytes are preserved" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("c-plugin-lock.json")
    let corrupt = "{not-json\n"
    @fs.write_file(path.to_string(), corrupt, create_mode=CreateNew)
    try load_lock(path) catch {
      StateStoreError::Decode(path=error_path, reason=_) =>
        inspect(error_path == path, content="true")
      _ => fail("expected Decode")
    } noraise {
      _ => fail("corrupt lock must fail")
    }
    inspect(@fs.read_file(path.to_string()).text(), content=corrupt)
  }
}

///|
async test "StateStore load_ownership_state - reports a missing file separately" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("missing-state.json")
    try load_ownership_state(path) catch {
      StateStoreError::NotFound(path=error_path) =>
        inspect(error_path == path, content="true")
      _ => fail("expected NotFound")
    } noraise {
      _ => fail("missing ownership state must fail")
    }
  }
}

///|
async test "StateStore load_lock - unsupported version bytes are preserved" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("c-plugin-lock.json")
    let unsupported = "{\"version\":\"1\",\"targets\":[],\"repositories\":[]}"
    @fs.write_file(path.to_string(), unsupported, create_mode=CreateNew)
    try load_lock(path) catch {
      StateStoreError::Decode(path=error_path, reason=_) =>
        inspect(error_path == path, content="true")
      _ => fail("expected Decode")
    } noraise {
      _ => fail("unsupported lock must fail")
    }
    inspect(@fs.read_file(path.to_string()).text(), content=unsupported)
  }
}

///|
async test "StateStore write_lock_atomic - a stale temporary sibling preserves the existing target" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("c-plugin-lock.json")
    let temporary_path = path
      .dirname()
      .join(path.basename().to_owned() + ".tmp")
    @fs.write_file(path.to_string(), "old bytes", create_mode=CreateNew)
    @fs.write_file(
      temporary_path.to_string(),
      "stale temp",
      create_mode=CreateNew,
    )
    try write_lock_atomic(path, alternate_test_lock()) catch {
      StateStoreError::IO(path=error_path, reason=_) =>
        inspect(error_path == temporary_path, content="true")
      _ => fail("expected IO")
    } noraise {
      _ => fail("stale temp must fail before rename")
    }
    inspect(@fs.read_file(path.to_string()).text(), content="old bytes")
    inspect(
      @fs.read_file(temporary_path.to_string()).text(),
      content="stale temp",
    )
  }
}

///|
async test "StateStore write_lock_atomic - a rename failure removes the new temp and preserves the target directory" {
  @async.with_task_group() <| group => {
    let root : @path.Path = @fs.tmpdir(prefix="c-plugin-state-store-")
    group.add_defer(() => @fs.rmdir(root.to_string(), recursive=true))
    let path = root.join("c-plugin-lock.json")
    @fs.mkdir(path.to_string())
    try write_lock_atomic(path, alternate_test_lock()) catch {
      StateStoreError::IO(path=error_path, reason=_) =>
        inspect(error_path == path, content="true")
      _ => fail("expected IO")
    } noraise {
      _ => fail("rename over a directory must fail")
    }
    inspect(
      @fs.kind(path.to_string()) == @fs.FileKind::Directory,
      content="true",
    )
    let temporary_path = path
      .dirname()
      .join(path.basename().to_owned() + ".tmp")
    inspect(@fs.exists(temporary_path.to_string()), content="false")
  }
}
