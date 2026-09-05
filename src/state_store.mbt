///|
/// Typed failures returned by lock and ownership-state persistence operations.
pub(all) suberror StateStoreError {
  AlreadyExists(path~ : @path.Path)
  NotFound(path~ : @path.Path)
  Decode(path~ : @path.Path, reason~ : String)
  IO(path~ : @path.Path, reason~ : String)
} derive(Debug, Eq)

///|
async fn read_json(path : @path.Path) -> Json raise StateStoreError {
  let text = @fs.read_file(path.to_string()).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => raise NotFound(path~)
    error => raise IO(path~, reason=error.to_string())
  }
  @json.parse(text) catch {
    error => raise Decode(path~, reason=error.to_string())
  }
}

///|
/// Load and decode a lock without modifying its bytes on failure.
pub async fn load_lock(path : @path.Path) -> Lock raise StateStoreError {
  let json = read_json(path)
  @json.from_json(json) catch {
    error => raise Decode(path~, reason=error.to_string())
  }
}

///|
/// Load and decode ownership state without modifying its bytes on failure.
pub async fn load_ownership_state(
  path : @path.Path,
) -> OwnershipState raise StateStoreError {
  let json = read_json(path)
  @json.from_json(json) catch {
    error => raise Decode(path~, reason=error.to_string())
  }
}

///|
async fn ensure_parent(path : @path.Path) -> Unit raise StateStoreError {
  @fs.mkdir(path.dirname().to_string(), recursive=true) catch {
    @os_error.OSError(_) as error if error.is_EEXIST() => ()
    error => raise IO(path~, reason=error.to_string())
  }
}

///|
/// Create a lock only when no file already exists at the target path.
pub async fn create_lock_exclusive(
  path : @path.Path,
  lock : Lock,
) -> Unit raise StateStoreError {
  ensure_parent(path)
  @fs.write_file(
    path.to_string(),
    lock.to_pretty_json(),
    create_mode=CreateNew,
    sync=Full,
  ) catch {
    @os_error.OSError(_) as error if error.is_EEXIST() =>
      raise AlreadyExists(path~)
    error => raise IO(path~, reason=error.to_string())
  }
}

///|
async fn replace_atomically(
  path : @path.Path,
  content : String,
) -> Unit raise StateStoreError {
  ensure_parent(path)
  let temporary_path = path.dirname().join(path.basename().to_owned() + ".tmp")
  let temporary_file = @fs.open(
    temporary_path.to_string(),
    mode=WriteOnly,
    create_mode=CreateNew,
    sync=Full,
  ) catch {
    error => raise IO(path=temporary_path, reason=error.to_string())
  }
  temporary_file.write(content) catch {
    error => {
      temporary_file.close()
      @fs.remove(temporary_path.to_string()) catch {
        _ => ()
      }
      raise IO(path=temporary_path, reason=error.to_string())
    }
  }
  temporary_file.close()
  @fs.rename(temporary_path.to_string(), path.to_string(), replace=true) catch {
    error => {
      @fs.remove(temporary_path.to_string()) catch {
        _ => ()
      }
      raise IO(path~, reason=error.to_string())
    }
  }
}

///|
/// Atomically replace a lock through an exclusive temporary sibling.
pub async fn write_lock_atomic(
  path : @path.Path,
  lock : Lock,
) -> Unit raise StateStoreError {
  replace_atomically(path, lock.to_pretty_json())
}

///|
/// Atomically replace ownership state through an exclusive temporary sibling.
pub async fn write_ownership_state_atomic(
  path : @path.Path,
  state : OwnershipState,
) -> Unit raise StateStoreError {
  replace_atomically(path, ToJson::to_json(state).stringify(indent=2) + "\n")
}
