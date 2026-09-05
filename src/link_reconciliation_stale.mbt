///|
async fn reconcile_stale_entries(
  io~ : LinkReconciliationIO,
  state_path~ : OwnershipStatePath,
  desired_state~ : OwnershipState,
  durable_state~ : OwnershipState,
  notices~ : Array[LinkReconciliationNotice],
) -> (OwnershipState, LinkReconciliationResult?) {
  let mut durable_state = durable_state
  let stale_entries = durable_state.entries
    .to_array()
    .filter(pair => desired_state.entries.get(pair.0) is None)
  stale_entries.sort_by((left, right) => left.0.compare(right.0))
  for pair in stale_entries {
    let identity = pair.0
    let recorded_entry = pair.1
    let recorded_root_kind = classify_link(
      io,
      recorded_entry.managed_root.path.path,
    ) catch {
      error => {
        notices.push(
          OperationFailed(
            operation=VerifyContainment,
            path=recorded_entry.managed_root.path.path,
            reason=error.to_string(),
          ),
        )
        continue
      }
    }
    match recorded_root_kind {
      None => {
        let checkpointed_state = state_without_entry(durable_state, identity)
        (io.checkpoint)(state_path.path.path, checkpointed_state) catch {
          error => {
            notices.push(
              CheckpointFailed(
                operation=CheckpointOwnership,
                path=state_path,
                reason=state_store_error_reason(error),
              ),
            )
            return (
              durable_state,
              Some({
                status: Partial,
                durable_state,
                notices: ReadOnlyArray::from_array(notices),
              }),
            )
          }
        }
        durable_state = checkpointed_state
        continue
      }
      Some(@fs.FileKind::Directory) => ()
      Some(_) => {
        notices.push(
          OperationFailed(
            operation=VerifyContainment,
            path=recorded_entry.managed_root.path.path,
            reason="recorded managed root must be a physical directory",
          ),
        )
        continue
      }
    }
    let contained = is_physically_contained(io, recorded_entry) catch {
      error => {
        notices.push(
          OperationFailed(
            operation=VerifyContainment,
            path=recorded_entry.link.path.path,
            reason=error.to_string(),
          ),
        )
        continue
      }
    }
    if !contained {
      notices.push(
        OperationFailed(
          operation=VerifyContainment,
          path=recorded_entry.link.path.path,
          reason="link parent resolves outside the recorded managed root",
        ),
      )
      continue
    }
    let kind = classify_link(io, recorded_entry.link.path.path) catch {
      error => {
        notices.push(
          OperationFailed(
            operation=ClassifyLink,
            path=recorded_entry.link.path.path,
            reason=error.to_string(),
          ),
        )
        continue
      }
    }
    let mut omit_ownership = false
    match kind {
      None => omit_ownership = true
      Some(@fs.FileKind::SymLink) => {
        let target = try (io.realpath)(recorded_entry.link.path.path) catch {
          @os_error.OSError(_) as error if error.is_ENOENT() => {
            notices.push(
              BrokenOwnedLinkPreserved(path=recorded_entry.link.path.path),
            )
            omit_ownership = true
            None
          }
          error => {
            notices.push(
              OperationFailed(
                operation=ClassifyLink,
                path=recorded_entry.link.path.path,
                reason=error.to_string(),
              ),
            )
            None
          }
        } noraise {
          path => Some(path.normalize())
        }
        match target {
          Some(live_target) if live_target ==
            recorded_entry.resolved_target.path.path =>
            match recheck_stale_link(io, recorded_entry) {
              Matching => {
                (io.remove)(recorded_entry.link.path.path) catch {
                  @os_error.OSError(_) as error if error.is_ENOENT() => ()
                  error => {
                    notices.push(
                      OperationFailed(
                        operation=RemoveLink,
                        path=recorded_entry.link.path.path,
                        reason=error.to_string(),
                      ),
                    )
                    continue
                  }
                }
                omit_ownership = true
              }
              Missing => omit_ownership = true
              Replaced => {
                notices.push(
                  ReplacedOwnedPathPreserved(path=recorded_entry.link.path.path),
                )
                omit_ownership = true
              }
              Failed(operation~, reason~) =>
                notices.push(
                  OperationFailed(
                    operation~,
                    path=recorded_entry.link.path.path,
                    reason~,
                  ),
                )
            }
          Some(_) => {
            notices.push(
              ReplacedOwnedPathPreserved(path=recorded_entry.link.path.path),
            )
            omit_ownership = true
          }
          None => ()
        }
      }
      Some(_) => {
        notices.push(
          ReplacedOwnedPathPreserved(path=recorded_entry.link.path.path),
        )
        omit_ownership = true
      }
    }
    if omit_ownership {
      let checkpointed_state = state_without_entry(durable_state, identity)
      (io.checkpoint)(state_path.path.path, checkpointed_state) catch {
        error => {
          notices.push(
            CheckpointFailed(
              operation=CheckpointOwnership,
              path=state_path,
              reason=state_store_error_reason(error),
            ),
          )
          return (
            durable_state,
            Some({
              status: Partial,
              durable_state,
              notices: ReadOnlyArray::from_array(notices),
            }),
          )
        }
      }
      durable_state = checkpointed_state
    }
  }
  (durable_state, None)
}
