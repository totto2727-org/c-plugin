///|
pub(all) suberror RepositoryRootError {
  RelativeRepositoryRoot(path~ : @path.Path)
} derive(Debug, Eq)

///|
pub struct RepositoryRoot {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub fn RepositoryRoot::RepositoryRoot(
  path : @path.Path,
) -> RepositoryRoot raise RepositoryRootError {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    _ => raise RelativeRepositoryRoot(path=path.normalize())
  }
  { path: absolute }
}

///|
pub struct ResolvedSkill {
  plugin_name : PluginName
  plugin_path : RelativePluginPath
  skill_name : SkillName
  skill_path : @x_path.AbsolutePath
} derive(Eq)

///|
pub(all) suberror SkillResolutionError {
  IO(path~ : @path.Path, reason~ : String)
  InvalidSkillName(path~ : @path.Path, reason~ : String)
  InvalidSkillPath(path~ : @path.Path, reason~ : String)
} derive(Debug, Eq)

///|
pub async fn resolve_marketplace_skills(
  repository_root : RepositoryRoot,
  marketplace : Marketplace,
) -> ReadOnlyArray[ResolvedSkill] raise SkillResolutionError {
  let resolved = []
  for plugin in marketplace.plugins {
    let plugin_skills = resolve_plugin_skills(repository_root, plugin)
    resolved.push_iter(plugin_skills.iter())
  }
  ReadOnlyArray::from_array(resolved)
}

///|
async fn resolve_plugin_skills(
  repository_root : RepositoryRoot,
  plugin : MarketplacePlugin,
) -> Array[ResolvedSkill] raise SkillResolutionError {
  let skills_directory = repository_root.path.path
    .join(plugin.path.path.path)
    .join("skills")
  let entries = @fs.readdir(
    skills_directory.to_string(),
    include_hidden=false,
    include_special=false,
    sort=false,
  ) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return []
    error => raise IO(path=skills_directory, reason=error.to_string())
  }
  let candidates : Array[(SkillName, @path.Path)] = []
  for entry in entries {
    let candidate_path = skills_directory.join(entry)
    let marker_path = candidate_path.join("SKILL.md")
    let has_marker = @fs.exists(marker_path.to_string()) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() || error.is_ENOTDIR() =>
        false
      error => raise IO(path=marker_path, reason=error.to_string())
    }
    if has_marker {
      let skill_name = SkillName::SkillName(entry) catch {
        error =>
          raise InvalidSkillName(path=candidate_path, reason=error.to_string())
      }
      candidates.push((skill_name, candidate_path))
    }
  }
  candidates.sort_by((left, right) => left.0.compare(right.0))
  candidates.map(candidate => {
    plugin_name: plugin.name,
    plugin_path: plugin.path,
    skill_name: candidate.0,
    skill_path: @x_path.AbsolutePath::AbsolutePath(candidate.1) catch {
      error =>
        raise InvalidSkillPath(path=candidate.1, reason=error.to_string())
    },
  })
}
