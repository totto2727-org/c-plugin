///|
/// Reports whether a lock mutation changed durable state and completed sync.
pub(all) enum PersistAndSyncResult {
  NoChange
  Synced
  PersistedButSyncFailed(cause~ : SyncError)
} derive(Debug)

///|
/// Persists a changed lock candidate before synchronizing that same value.
pub async fn persist_and_sync(
  current_lock~ : Lock,
  candidate~ : Lock?,
  persist~ : async (Lock) -> Unit raise StateStoreError,
  sync~ : async (Lock) -> Unit raise SyncError,
) -> PersistAndSyncResult raise StateStoreError {
  let changed_lock = match candidate {
    None => return NoChange
    Some(candidate) if candidate == current_lock => return NoChange
    Some(candidate) => candidate
  }
  persist(changed_lock)
  sync(changed_lock) catch {
    cause => return PersistedButSyncFailed(cause~)
  }
  Synced
}
