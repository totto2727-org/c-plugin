///|
pub(all) enum LockDiscoveryScope {
  Project
  Global
} derive(Debug, Eq)

///|
pub(all) enum LockDiscoveryOptions {
  Global
  Project(recursive~ : Bool)
} derive(Debug, Eq)

///|
pub(all) suberror LockDiscoveryError {
  LockFileNotFound(scope~ : LockDiscoveryScope, boundary~ : @path.Path)
} derive(Debug)

///|
let lock_file_name = "c-plugin-lock.json"

///|
fn path_is_within(base : @path.Path, target : @path.Path) -> Bool {
  let normalized_base = base.normalize().to_string()
  let normalized_target = target.normalize().to_string()
  let base_prefix = if normalized_base == "/" {
    normalized_base
  } else {
    "\{normalized_base}/"
  }
  normalized_target == normalized_base ||
  normalized_target.has_prefix(base_prefix)
}

///|
async fn find_project_lock(
  home : @path.Path,
  cwd : @path.Path,
) -> @path.Path raise LockDiscoveryError {
  guard path_is_within(home, cwd) else {
    raise LockFileNotFound(scope=Project, boundary=home)
  }
  let discovered = @target_file_discovery.find_parent_target_file(
    lock_file_name,
    home.to_string(),
    cwd.to_string(),
  ) catch {
    _ => raise LockFileNotFound(scope=Project, boundary=home)
  }
  let path : @path.Path = discovered
  path.normalize()
}

///|
async fn find_global_lock(
  home : @path.Path,
) -> @path.Path raise LockDiscoveryError {
  let discovered = @target_file_discovery.find_home_target_file(
    home.to_string(),
    lock_file_name,
  ) catch {
    _ => raise LockFileNotFound(scope=Global, boundary=home)
  }
  let path : @path.Path = discovered
  path.normalize()
}

///|
async fn find_recursive_project_locks(
  home : @path.Path,
  nearest_lock : @path.Path,
) -> ReadOnlyArray[@path.Path] raise LockDiscoveryError {
  let discovered = @target_file_discovery.collect_recursive_target_files(
    nearest_lock.dirname().to_string(),
    lock_file_name,
  ) catch {
    _ => raise LockFileNotFound(scope=Project, boundary=home)
  }
  ReadOnlyArray::from_array(
    discovered[:].map(path => {
      let normalized_path : @path.Path = path
      normalized_path.normalize()
    }),
  )
}

///|
pub async fn discover_locks(
  paths : RuntimePaths,
  options : LockDiscoveryOptions,
) -> ReadOnlyArray[@path.Path] raise LockDiscoveryError {
  match options {
    Global => ReadOnlyArray::from_array([find_global_lock(paths.home.path)])
    Project(recursive~) => {
      let nearest_lock = find_project_lock(paths.home.path, paths.cwd.path)
      if recursive {
        find_recursive_project_locks(paths.home.path, nearest_lock)
      } else {
        ReadOnlyArray::from_array([nearest_lock])
      }
    }
  }
}
