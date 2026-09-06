///|
enum OwnershipCheckpointResult {
  Written(OwnershipState)
  HardStop(LinkReconciliationResult)
}

///|
fn state_with_entry(
  state : OwnershipState,
  entry : OwnershipEntry,
) -> OwnershipState {
  {
    version: state.version,
    entries: state.entries.add(
      OwnershipLinkIdentity::OwnershipLinkIdentity(entry.link.path),
      entry,
    ),
  }
}

///|
fn state_without_entry(
  state : OwnershipState,
  identity : OwnershipLinkIdentity,
) -> OwnershipState {
  { version: state.version, entries: state.entries.remove(identity) }
}

///|
fn state_store_error_reason(error : StateStoreError) -> String {
  match error {
    AlreadyExists(path~) => "already exists: \{path.to_string()}"
    NotFound(path~) => "not found: \{path.to_string()}"
    Decode(reason~, path=_) | IO(reason~, path=_) => reason
  }
}

///|
async fn checkpoint_ownership(
  io : LinkReconciliationIO,
  state_path : OwnershipStatePath,
  durable_state : OwnershipState,
  checkpointed_state : OwnershipState,
  notices : Array[LinkReconciliationNotice],
) -> OwnershipCheckpointResult {
  (io.checkpoint)(state_path.path.path, checkpointed_state) catch {
    error => {
      notices.push(
        CheckpointFailed(
          operation=CheckpointOwnership,
          path=state_path,
          reason=state_store_error_reason(error),
        ),
      )
      return HardStop({
        status: Partial,
        durable_state,
        notices: ReadOnlyArray::from_array(notices),
      })
    }
  }
  Written(checkpointed_state)
}
