///|
async fn reconcile_desired_entries(
  io~ : LinkReconciliationIO,
  state_path~ : OwnershipStatePath,
  desired_state~ : OwnershipState,
  durable_state~ : OwnershipState,
  notices~ : Array[LinkReconciliationNotice],
  collision_policy~ : DesiredLinkCollisionPolicy,
) -> (OwnershipState, LinkReconciliationResult?) {
  let mut durable_state = durable_state
  let desired_entries = desired_state.entries.to_array()
  desired_entries.sort_by((left, right) => left.0.compare(right.0))

  for pair in desired_entries {
    let identity = pair.0
    let desired_entry = pair.1
    (io.mkdir)(desired_entry.managed_root.path.path) catch {
      error => {
        notices.push(
          OperationFailed(
            operation=EnsureManagedRoot,
            path=desired_entry.managed_root.path.path,
            reason=error.to_string(),
          ),
        )
        continue
      }
    }
    let managed_root_kind = (io.kind)(desired_entry.managed_root.path.path) catch {
      error => {
        notices.push(
          OperationFailed(
            operation=VerifyContainment,
            path=desired_entry.managed_root.path.path,
            reason=error.to_string(),
          ),
        )
        continue
      }
    }
    if managed_root_kind != @fs.FileKind::Directory {
      notices.push(
        OperationFailed(
          operation=VerifyContainment,
          path=desired_entry.managed_root.path.path,
          reason="managed root must be a physical directory",
        ),
      )
      continue
    }
    let contained = is_physically_contained(io, desired_entry) catch {
      error => {
        notices.push(
          OperationFailed(
            operation=VerifyContainment,
            path=desired_entry.link.path.path,
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
          path=desired_entry.link.path.path,
          reason="link parent resolves outside the managed root",
        ),
      )
      continue
    }
    let kind = classify_link(io, desired_entry.link.path.path) catch {
      error => {
        notices.push(
          OperationFailed(
            operation=ClassifyLink,
            path=desired_entry.link.path.path,
            reason=error.to_string(),
          ),
        )
        continue
      }
    }
    let mut should_create = false
    let replace_existing = match collision_policy {
      ReplaceNonDirectory =>
        match kind {
          Some(@fs.FileKind::Regular) | Some(@fs.FileKind::SymLink) => true
          _ => false
        }
      PreserveExisting => false
    }
    if replace_existing {
      match durable_state.entries.get(identity) {
        Some(_) => {
          let omitted = state_without_entry(durable_state, identity)
          match
            checkpoint_ownership(
              io, state_path, durable_state, omitted, notices,
            ) {
            Written(state) => durable_state = state
            HardStop(result) => return (durable_state, Some(result))
          }
        }
        None => ()
      }
      (io.remove)(desired_entry.link.path.path) catch {
        @os_error.OSError(_) as error if error.is_ENOENT() => ()
        error => {
          notices.push(
            OperationFailed(
              operation=RemoveLink,
              path=desired_entry.link.path.path,
              reason=error.to_string(),
            ),
          )
          continue
        }
      }
      match
        create_desired_link(
          io, state_path, durable_state, desired_entry, notices,
        ) {
        Created(state) => durable_state = state
        Skipped => ()
        CreationHardStop(result) => return (durable_state, Some(result))
      }
      continue
    }
    match durable_state.entries.get(identity) {
      None =>
        match kind {
          Some(_) =>
            notices.push(
              UnmanagedPathPreserved(path=desired_entry.link.path.path),
            )
          None => should_create = true
        }
      Some(recorded_entry) =>
        match kind {
          None => {
            let omitted = state_without_entry(durable_state, identity)
            match
              checkpoint_ownership(
                io, state_path, durable_state, omitted, notices,
              ) {
              Written(state) => durable_state = state
              HardStop(result) => return (durable_state, Some(result))
            }
            should_create = true
          }
          Some(@fs.FileKind::SymLink) => {
            let mut broken = false
            let live_target = try
              (io.realpath)(recorded_entry.link.path.path)
            catch {
              @os_error.OSError(_) as error if error.is_ENOENT() => {
                broken = true
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
              target => Some(target.normalize())
            }
            if broken {
              notices.push(
                BrokenOwnedLinkPreserved(path=recorded_entry.link.path.path),
              )
              let omitted = state_without_entry(durable_state, identity)
              match
                checkpoint_ownership(
                  io, state_path, durable_state, omitted, notices,
                ) {
                Written(state) => durable_state = state
                HardStop(result) => return (durable_state, Some(result))
              }
            } else {
              match live_target {
                Some(target) if target ==
                  recorded_entry.resolved_target.path.path =>
                  if desired_entry.resolved_target.path.path ==
                    recorded_entry.resolved_target.path.path {
                    if desired_entry != recorded_entry {
                      let refreshed = state_with_entry(
                        durable_state, desired_entry,
                      )
                      match
                        checkpoint_ownership(
                          io, state_path, durable_state, refreshed, notices,
                        ) {
                        Written(state) => durable_state = state
                        HardStop(result) => return (durable_state, Some(result))
                      }
                    }
                  } else {
                    match recheck_stale_link(io, recorded_entry) {
                      Matching => {
                        (io.remove)(recorded_entry.link.path.path) catch {
                          @os_error.OSError(_) as error if error.is_ENOENT() =>
                            ()
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
                        let omitted = state_without_entry(
                          durable_state, identity,
                        )
                        match
                          checkpoint_ownership(
                            io, state_path, durable_state, omitted, notices,
                          ) {
                          Written(state) => durable_state = state
                          HardStop(result) =>
                            return (durable_state, Some(result))
                        }
                        should_create = true
                      }
                      Missing => {
                        let omitted = state_without_entry(
                          durable_state, identity,
                        )
                        match
                          checkpoint_ownership(
                            io, state_path, durable_state, omitted, notices,
                          ) {
                          Written(state) => durable_state = state
                          HardStop(result) =>
                            return (durable_state, Some(result))
                        }
                        should_create = true
                      }
                      Replaced => {
                        notices.push(
                          ReplacedOwnedPathPreserved(
                            path=recorded_entry.link.path.path,
                          ),
                        )
                        let omitted = state_without_entry(
                          durable_state, identity,
                        )
                        match
                          checkpoint_ownership(
                            io, state_path, durable_state, omitted, notices,
                          ) {
                          Written(state) => durable_state = state
                          HardStop(result) =>
                            return (durable_state, Some(result))
                        }
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
                  }
                Some(_) => {
                  notices.push(
                    ReplacedOwnedPathPreserved(
                      path=recorded_entry.link.path.path,
                    ),
                  )
                  let omitted = state_without_entry(durable_state, identity)
                  match
                    checkpoint_ownership(
                      io, state_path, durable_state, omitted, notices,
                    ) {
                    Written(state) => durable_state = state
                    HardStop(result) => return (durable_state, Some(result))
                  }
                }
                None => ()
              }
            }
          }
          Some(_) => {
            notices.push(
              ReplacedOwnedPathPreserved(path=recorded_entry.link.path.path),
            )
            let omitted = state_without_entry(durable_state, identity)
            match
              checkpoint_ownership(
                io, state_path, durable_state, omitted, notices,
              ) {
              Written(state) => durable_state = state
              HardStop(result) => return (durable_state, Some(result))
            }
          }
        }
    }
    if should_create {
      match
        create_desired_link(
          io, state_path, durable_state, desired_entry, notices,
        ) {
        Created(state) => durable_state = state
        Skipped => ()
        CreationHardStop(result) => return (durable_state, Some(result))
      }
    }
  }
  (durable_state, None)
}
