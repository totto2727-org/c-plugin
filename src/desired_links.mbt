///|
pub struct ManagedSkillRoot {
  path : @x_path.AbsolutePath
} derive(Eq)

///|
pub impl Hash for ManagedSkillRoot with fn hash_combine(self, hasher) {
  Hash::hash_combine(@x_path.Path::to_string(self.path), hasher)
}

///|
pub(all) suberror ManagedSkillRootError {
  ManagedSkillRootConstructionFailed(path~ : @path.Path, cause~ : Error)
}

///|
pub impl Show for ManagedSkillRootError with fn output(self, logger) {
  match self {
    ManagedSkillRootConstructionFailed(path~, cause~) =>
      logger.write_string(
        "ManagedSkillRootConstructionFailed(path=\{path}, cause=\{cause})",
      )
  }
}

///|
pub fn ManagedSkillRoot::ManagedSkillRoot(
  path : @path.Path,
) -> ManagedSkillRoot raise ManagedSkillRootError {
  let absolute = @x_path.AbsolutePath::AbsolutePath(path) catch {
    cause => raise ManagedSkillRootConstructionFailed(path~, cause~)
  }
  { path: absolute }
}

///|
pub(all) enum RepositorySkillResolution {
  Available(
    repository~ : LockRepository,
    skills~ : ReadOnlyArray[ResolvedSkill]
  )
  Unavailable(repository~ : LockRepository, reason~ : String)
}

///|
pub struct RepositorySkillResolutions {
  entries : @immut_hashmap.HashMap[
    RepositoryIdentity,
    RepositorySkillResolution,
  ]
}

///|
pub(all) suberror RepositorySkillResolutionsError {
  DuplicateRepositoryIdentity(identity~ : RepositoryIdentity)
}

///|
pub fn RepositorySkillResolutions::RepositorySkillResolutions(
  resolutions : Array[RepositorySkillResolution],
) -> RepositorySkillResolutions raise RepositorySkillResolutionsError {
  let mut entries : @immut_hashmap.HashMap[
    RepositoryIdentity,
    RepositorySkillResolution,
  ] = @immut_hashmap.HashMap([])
  for resolution in resolutions {
    let identity = match resolution {
      Available(repository~, skills=_) | Unavailable(repository~, reason=_) =>
        repository.identity()
    }
    guard entries.get(identity) is None else {
      raise DuplicateRepositoryIdentity(identity~)
    }
    entries = entries.add(identity, resolution)
  }
  { entries, }
}

///|
pub(all) struct RepositoryUnavailable {
  repository : RepositoryIdentity
  reason : String
}

///|
pub(all) struct DesiredLinkPlan {
  ownership_state : OwnershipState
  unavailable_repositories : @immut_hashmap.HashMap[
    RepositoryIdentity,
    RepositoryUnavailable,
  ]
}

///|
pub(all) enum DesiredEntryConstructionStage {
  Link(cause~ : OwnershipLinkError)
  ResolvedTarget(cause~ : OwnershipResolvedTargetError)
  ManagedRoot(cause~ : OwnershipManagedRootError)
  Entry(cause~ : OwnershipEntryError)
}

///|
pub(all) suberror DesiredLinkPlanningError {
  InvalidDesiredEntry(
    stage~ : DesiredEntryConstructionStage,
    repository~ : RepositoryIdentity,
    managed_root~ : ManagedSkillRoot,
    skill~ : SkillName,
    skill_path~ : @x_path.AbsolutePath
  )
  InvalidOwnershipState(cause~ : OwnershipStateError)
}

///|
/// Keeps the command's existing error-rendering boundary available after the
/// planner effect narrows from Error to DesiredLinkPlanningError.
pub fn DesiredLinkPlanningError::to_string(
  self : DesiredLinkPlanningError,
) -> String {
  let error : Error = self
  error.to_string()
}

///|
fn DesiredLinkPlanningError::from_entry_failure(
  stage : DesiredEntryConstructionStage,
  root : ManagedSkillRoot,
  repository : LockRepository,
  skill : ResolvedSkill,
) -> DesiredLinkPlanningError {
  InvalidDesiredEntry(
    stage~,
    repository=repository.identity(),
    managed_root=root,
    skill=skill.skill_name,
    skill_path=skill.skill_path,
  )
}

///|
struct DesiredLinkCandidate {
  repository : RepositoryIdentity
  entry : OwnershipEntry
}

///|
fn enabled_plugin(
  repository : LockRepository,
  skill : ResolvedSkill,
) -> Plugin? {
  match repository {
    GitHub(repository) => repository.plugins.get(skill.plugin_name)
    Local(repository) => repository.plugins.get(skill.plugin_name)
  }
}

///|
fn ownership_source(
  repository : LockRepository,
  skill : ResolvedSkill,
) -> OwnershipSource {
  match repository {
    GitHub(repository) =>
      OwnershipSource::from_github(
        GitHubOwnershipSource::GitHubOwnershipSource(
          repository.repository,
          skill.plugin_name,
          skill.skill_name,
        ),
      )
    Local(repository) =>
      OwnershipSource::from_local(
        LocalOwnershipSource::LocalOwnershipSource(
          repository.path,
          skill.plugin_name,
          skill.skill_name,
        ),
      )
  }
}

///|
fn desired_entry(
  root : ManagedSkillRoot,
  repository : LockRepository,
  skill : ResolvedSkill,
) -> OwnershipEntry raise DesiredLinkPlanningError {
  let link = OwnershipLink::OwnershipLink(
    root.path.path.join(skill.skill_name.value),
  ) catch {
    OwnershipLinkConstructionFailed(..) as cause =>
      raise DesiredLinkPlanningError::from_entry_failure(
        Link(cause~),
        root,
        repository,
        skill,
      )
  }
  let resolved_target = OwnershipResolvedTarget::OwnershipResolvedTarget(
    skill.skill_path.path,
  ) catch {
    OwnershipResolvedTargetConstructionFailed(..) as cause =>
      raise DesiredLinkPlanningError::from_entry_failure(
        ResolvedTarget(cause~),
        root,
        repository,
        skill,
      )
  }
  let managed_root = OwnershipManagedRoot::OwnershipManagedRoot(root.path.path) catch {
    OwnershipManagedRootConstructionFailed(..) as cause =>
      raise DesiredLinkPlanningError::from_entry_failure(
        ManagedRoot(cause~),
        root,
        repository,
        skill,
      )
  }
  OwnershipEntry::OwnershipEntry(
    link,
    skill.skill_path.path.relative(base=root.path.path),
    resolved_target,
    managed_root,
    ownership_source(repository, skill),
  ) catch {
    OwnershipLinkOutsideManagedRoot(..) as cause =>
      raise DesiredLinkPlanningError::from_entry_failure(
        Entry(cause~),
        root,
        repository,
        skill,
      )
  }
}

///|
fn desired_ownership_state(
  entries : Array[OwnershipEntry],
) -> OwnershipState raise DesiredLinkPlanningError {
  OwnershipState::OwnershipState(entries) catch {
    DuplicateOwnershipLink(..) as cause => raise InvalidOwnershipState(cause~)
  }
}

///|
pub fn plan_desired_skill_links(
  managed_roots : @immut_hashset.HashSet[ManagedSkillRoot],
  repositories : RepositorySkillResolutions,
) -> DesiredLinkPlan raise DesiredLinkPlanningError {
  let mut candidates : @immut_hashmap.HashMap[
    OwnershipLinkIdentity,
    DesiredLinkCandidate,
  ] = @immut_hashmap.HashMap([])
  let mut unavailable : @immut_hashmap.HashMap[
    RepositoryIdentity,
    RepositoryUnavailable,
  ] = @immut_hashmap.HashMap([])
  for pair in repositories.entries.to_array() {
    match pair.1 {
      Unavailable(repository~, reason~) => {
        let identity = repository.identity()
        unavailable = unavailable.add(identity, { repository: identity, reason })
      }
      Available(repository~, skills~) => {
        let identity = repository.identity()
        for skill in skills {
          match enabled_plugin(repository, skill) {
            Some(plugin) if plugin.enabled_skills.contains(skill.skill_name) =>
              for root in managed_roots {
                let entry = desired_entry(root, repository, skill)
                let link_identity = OwnershipLinkIdentity::OwnershipLinkIdentity(
                  entry.link.path,
                )
                match candidates.get(link_identity) {
                  Some(existing) if Compare::compare(
                      identity,
                      existing.repository,
                    ) <
                    0 => ()
                  _ =>
                    candidates = candidates.add(link_identity, {
                      repository: identity,
                      entry,
                    })
                }
              }
            _ => ()
          }
        }
      }
    }
  }
  let entries = candidates.to_array().map(pair => pair.1.entry)
  {
    ownership_state: desired_ownership_state(entries),
    unavailable_repositories: unavailable,
  }
}
