///|
pub(all) suberror RuntimePathsError {
  RelativeRoot(name~ : String, path~ : @path.Path)
} derive(Debug)

///|
pub struct RuntimePaths {
  home : @x_path.AbsolutePath
  cwd : @x_path.AbsolutePath
  cache_root : @x_path.AbsolutePath
}

///|
fn normalized_absolute_root(
  name : String,
  path : @path.Path,
) -> @x_path.AbsolutePath raise RuntimePathsError {
  @x_path.AbsolutePath::AbsolutePath(path) catch {
    _ => raise RelativeRoot(name~, path~)
  }
}

///|
pub fn RuntimePaths::RuntimePaths(
  home : @path.Path,
  cwd : @path.Path,
  cache_root : @path.Path,
) -> RuntimePaths raise RuntimePathsError {
  RuntimePaths::{
    home: normalized_absolute_root("home", home),
    cwd: normalized_absolute_root("cwd", cwd),
    cache_root: normalized_absolute_root("cache root", cache_root),
  }
}

///|
pub fn RuntimePaths::project_lock_path(
  self : RuntimePaths,
  project_root : @path.Path,
) -> @path.Path raise RuntimePathsError {
  ignore(self)
  normalized_absolute_root("project root", project_root).path.join(
    "c-plugin-lock.json",
  )
}

///|
pub fn RuntimePaths::global_lock_path(self : RuntimePaths) -> @path.Path {
  self.home.path.join("c-plugin-lock.json")
}

///|
pub fn RuntimePaths::project_ownership_state_path(
  self : RuntimePaths,
  project_root : @path.Path,
) -> OwnershipStatePath raise {
  ignore(self)
  OwnershipStatePath::OwnershipStatePath(
    normalized_absolute_root("project root", project_root).path
    .join(".agents")
    .join("c-plugin-state.json"),
  )
}

///|
pub fn RuntimePaths::global_ownership_state_path(
  self : RuntimePaths,
) -> OwnershipStatePath raise {
  OwnershipStatePath::OwnershipStatePath(
    self.home.path.join(".agents").join("c-plugin-state.json"),
  )
}

///|
pub fn RuntimePaths::project_managed_skill_root(
  self : RuntimePaths,
  project_root : @path.Path,
) -> @path.Path raise RuntimePathsError {
  ignore(self)
  normalized_absolute_root("project root", project_root).path
  .join(".agents")
  .join("skills")
}

///|
pub fn RuntimePaths::global_managed_skill_root(
  self : RuntimePaths,
) -> @path.Path {
  self.home.path.join(".agents").join("skills")
}
