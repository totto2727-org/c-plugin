///|
enum DesiredLinkCreationResult {
  Created(OwnershipState)
  Skipped
  CreationHardStop(LinkReconciliationResult)
}

///|
async fn create_desired_link(
  io : LinkReconciliationIO,
  state_path : OwnershipStatePath,
  durable_state : OwnershipState,
  desired_entry : OwnershipEntry,
  notices : Array[LinkReconciliationNotice],
) -> DesiredLinkCreationResult {
  (io.symlink)(desired_entry.symlink_target, desired_entry.link.path.path) catch {
    @os_error.OSError(_) as error if error.is_EEXIST() => {
      notices.push(UnmanagedPathPreserved(path=desired_entry.link.path.path))
      return Skipped
    }
    error => {
      notices.push(
        OperationFailed(
          operation=CreateLink,
          path=desired_entry.link.path.path,
          reason=error.to_string(),
        ),
      )
      return Skipped
    }
  }
  let verified = try {
    let live_kind = (io.kind)(desired_entry.link.path.path)
    let live_target = (io.realpath)(desired_entry.link.path.path).normalize()
    let still_contained = is_physically_contained(io, desired_entry)
    live_kind == @fs.FileKind::SymLink &&
    live_target == desired_entry.resolved_target.path.path &&
    still_contained
  } catch {
    _ => false
  } noraise {
    value => value
  }
  if !verified {
    notices.push(
      OperationFailed(
        operation=VerifyCreatedLink,
        path=desired_entry.link.path.path,
        reason="created link could not be verified",
      ),
    )
    return CreationHardStop({
      status: Partial,
      durable_state,
      notices: ReadOnlyArray::from_array(notices),
    })
  }
  let next_state = state_with_entry(durable_state, desired_entry)
  match
    checkpoint_ownership(io, state_path, durable_state, next_state, notices) {
    Written(state) => Created(state)
    HardStop(_) => {
      let mut rollback_check_failed = false
      let rollback_verified = try
        (io.kind)(desired_entry.link.path.path) == @fs.FileKind::SymLink &&
        (io.realpath)(desired_entry.link.path.path).normalize() ==
        desired_entry.resolved_target.path.path &&
        is_physically_contained(io, desired_entry)
      catch {
        error => {
          rollback_check_failed = true
          notices.push(
            OperationFailed(
              operation=VerifyCreatedLink,
              path=desired_entry.link.path.path,
              reason=error.to_string(),
            ),
          )
          false
        }
      } noraise {
        value => value
      }
      if rollback_verified {
        (io.remove)(desired_entry.link.path.path) catch {
          @os_error.OSError(_) as error if error.is_ENOENT() => ()
          error =>
            notices.push(
              OperationFailed(
                operation=RemoveLink,
                path=desired_entry.link.path.path,
                reason=error.to_string(),
              ),
            )
        }
      } else if !rollback_check_failed {
        notices.push(UnmanagedPathPreserved(path=desired_entry.link.path.path))
      }
      CreationHardStop({
        status: Partial,
        durable_state,
        notices: ReadOnlyArray::from_array(notices),
      })
    }
  }
}
