///|
fn persist_and_sync_test_lock(targets : Array[String]) -> Lock raise {
  Lock::Lock(targets.map(target => Target::Target(target)), [])
}

///|
async test "PersistAndSync persist_and_sync 1 - persists before syncing the same changed candidate" {
  let current_lock = persist_and_sync_test_lock([])
  let candidate = persist_and_sync_test_lock([".cursor/skills"])
  let events : Array[String] = []
  let persisted : Array[Lock] = []
  let synced : Array[Lock] = []
  let persist : async (Lock) -> Unit raise StateStoreError = fn(lock) {
    events.push("persist")
    persisted.push(lock)
  }
  let sync : async (Lock) -> Unit raise SyncError = fn(lock) {
    events.push("sync")
    synced.push(lock)
  }

  let result = persist_and_sync(
    current_lock~,
    candidate=Some(candidate),
    persist~,
    sync~,
  )

  debug_inspect(result, content="Synced")
  debug_inspect(events, content="[\"persist\", \"sync\"]")
  inspect(persisted.length(), content="1")
  inspect(synced.length(), content="1")
  inspect(persisted[0] == candidate, content="true")
  inspect(synced[0] == candidate, content="true")
}

///|
async test "PersistAndSync persist_and_sync 2 - skips persistence and sync when cancelled" {
  let current_lock = persist_and_sync_test_lock([])
  let events : Array[String] = []
  let persist : async (Lock) -> Unit raise StateStoreError = _lock => {
    events.push("persist")
  }
  let sync : async (Lock) -> Unit raise SyncError = fn(_lock) {
    events.push("sync")
  }

  let result = persist_and_sync(current_lock~, candidate=None, persist~, sync~)

  debug_inspect(result, content="NoChange")
  debug_inspect(events, content="[]")
}

///|
async test "PersistAndSync persist_and_sync 3 - skips persistence and sync for an equal candidate" {
  let current_lock = persist_and_sync_test_lock([".cursor/skills"])
  let events : Array[String] = []
  let persist : async (Lock) -> Unit raise StateStoreError = fn(_lock) {
    events.push("persist")
  }
  let sync : async (Lock) -> Unit raise SyncError = fn(_lock) {
    events.push("sync")
  }

  let result = persist_and_sync(
    current_lock~,
    candidate=Some(current_lock),
    persist~,
    sync~,
  )

  debug_inspect(result, content="NoChange")
  debug_inspect(events, content="[]")
}

///|
async test "PersistAndSync persist_and_sync 4 - does not sync after persistence fails" {
  let current_lock = persist_and_sync_test_lock([])
  let candidate = persist_and_sync_test_lock([".cursor/skills"])
  let lock_path = @path.Path("c-plugin-lock.json")
  let synced : Array[Lock] = []
  let persist : async (Lock) -> Unit raise StateStoreError = _lock => {
    raise StateStoreError::IO(path=lock_path, reason="write failed")
  }
  let sync : async (Lock) -> Unit raise SyncError = fn(lock) {
    synced.push(lock)
  }

  try
    persist_and_sync(current_lock~, candidate=Some(candidate), persist~, sync~)
    |> ignore
  catch {
    StateStoreError::IO(path~, reason~) => {
      inspect(path == lock_path, content="true")
      inspect(reason, content="write failed")
    }
    _ => fail("expected persistence error")
  } noraise {
    _ => fail("persistence failure must propagate")
  }
  inspect(synced.length(), content="0")
}

///|
async test "PersistAndSync persist_and_sync 5 - reports sync failure after preserving the candidate" {
  let current_lock = persist_and_sync_test_lock([])
  let candidate = persist_and_sync_test_lock([".cursor/skills"])
  let persisted : Array[Lock] = []
  let persist : async (Lock) -> Unit raise StateStoreError = fn(lock) {
    persisted.push(lock)
  }
  let sync : async (Lock) -> Unit raise SyncError = _lock => {
    raise SyncError::Planning(reason="sync failed")
  }

  let result = persist_and_sync(
    current_lock~,
    candidate=Some(candidate),
    persist~,
    sync~,
  )

  match result {
    PersistedButSyncFailed(cause=SyncError::Planning(reason~)) =>
      inspect(reason, content="sync failed")
    _ => fail("expected persisted sync failure")
  }
  inspect(persisted.length(), content="1")
  inspect(persisted[0] == candidate, content="true")
}
