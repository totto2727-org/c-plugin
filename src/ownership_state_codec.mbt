///|
let ownership_source_type_lens : @lens.Lens[String] = @lens.root().string(
  "type",
)

///|
let ownership_source_github_repository_lens : @lens.Lens[GitHubRepository] = @lens.root().custom(
  "repository",
)

///|
let ownership_source_local_repository_lens : @lens.Lens[RelativeSourcePath] = @lens.root().custom(
  "repository",
)

///|
let ownership_source_plugin_lens : @lens.Lens[PluginName] = @lens.root().custom(
  "plugin",
)

///|
let ownership_source_skill_lens : @lens.Lens[SkillName] = @lens.root().custom(
  "skill",
)

///|
let ownership_entry_link_lens : @lens.Lens[OwnershipLink] = @lens.root().custom(
  "link",
)

///|
let ownership_entry_symlink_target_lens : @lens.Lens[String] = @lens.root().string(
  "symlinkTarget",
)

///|
let ownership_entry_resolved_target_lens : @lens.Lens[OwnershipResolvedTarget] = @lens.root().custom(
  "resolvedTarget",
)

///|
let ownership_entry_managed_root_lens : @lens.Lens[OwnershipManagedRoot] = @lens.root().custom(
  "managedRoot",
)

///|
let ownership_entry_source_lens : @lens.Lens[OwnershipSource] = @lens.root().custom(
  "source",
)

///|
let ownership_state_version_lens : @lens.Lens[String] = @lens.root().string(
  "version",
)

///|
let ownership_state_entries_lens : @lens.Lens[Array[OwnershipEntry]] = @lens.root()
  .custom("entries")
  .array()

///|
pub impl FromJson for OwnershipSource with fn from_json(json, path) {
  let source_type = ownership_source_type_lens.get_or_json_decode_error(
    json, path,
  )
  match source_type {
    "github" => {
      let repository = ownership_source_github_repository_lens.get_or_json_decode_error(
        json, path,
      )
      let plugin = ownership_source_plugin_lens.get_or_json_decode_error(
        json, path,
      )
      let skill = ownership_source_skill_lens.get_or_json_decode_error(
        json, path,
      )
      OwnershipSource::from_github(
        GitHubOwnershipSource::GitHubOwnershipSource(repository, plugin, skill),
      )
    }
    "local" => {
      let repository = ownership_source_local_repository_lens.get_or_json_decode_error(
        json, path,
      )
      let plugin = ownership_source_plugin_lens.get_or_json_decode_error(
        json, path,
      )
      let skill = ownership_source_skill_lens.get_or_json_decode_error(
        json, path,
      )
      OwnershipSource::from_local(
        LocalOwnershipSource::LocalOwnershipSource(repository, plugin, skill),
      )
    }
    _ =>
      raise ownership_source_type_lens.json_decode_error(
        path,
        "unsupported ownership source type: \{source_type}",
      )
  }
}

///|
pub impl ToJson for OwnershipSource with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  match self {
    GitHub(source) => {
      ownership_source_type_lens.set_or_abort(builder, "github")
      ownership_source_github_repository_lens.set_or_abort(
        builder,
        source.repository,
      )
      ownership_source_plugin_lens.set_or_abort(builder, source.plugin)
      ownership_source_skill_lens.set_or_abort(builder, source.skill)
    }
    Local(source) => {
      ownership_source_type_lens.set_or_abort(builder, "local")
      ownership_source_local_repository_lens.set_or_abort(
        builder,
        source.repository,
      )
      ownership_source_plugin_lens.set_or_abort(builder, source.plugin)
      ownership_source_skill_lens.set_or_abort(builder, source.skill)
    }
  }
  builder.to_json()
}

///|
pub impl FromJson for OwnershipLink with fn from_json(json, path) {
  let absolute : @x_path.AbsolutePath = @json.from_json(json, path~)
  OwnershipLink::OwnershipLink(absolute.path) catch {
    _ => raise @json.JsonDecodeError((path, "ownership link must be absolute"))
  }
}

///|
pub impl ToJson for OwnershipLink with fn to_json(self) -> Json {
  self.path.to_json()
}

///|
pub impl FromJson for OwnershipResolvedTarget with fn from_json(json, path) {
  let absolute : @x_path.AbsolutePath = @json.from_json(json, path~)
  OwnershipResolvedTarget::OwnershipResolvedTarget(absolute.path) catch {
    _ =>
      raise @json.JsonDecodeError(
        (path, "ownership resolved target must be absolute"),
      )
  }
}

///|
pub impl ToJson for OwnershipResolvedTarget with fn to_json(self) -> Json {
  self.path.to_json()
}

///|
pub impl FromJson for OwnershipManagedRoot with fn from_json(json, path) {
  let absolute : @x_path.AbsolutePath = @json.from_json(json, path~)
  OwnershipManagedRoot::OwnershipManagedRoot(absolute.path) catch {
    _ =>
      raise @json.JsonDecodeError(
        (path, "ownership managed root must be absolute"),
      )
  }
}

///|
pub impl ToJson for OwnershipManagedRoot with fn to_json(self) -> Json {
  self.path.to_json()
}

///|
pub impl FromJson for OwnershipEntry with fn from_json(json, path) {
  let link = ownership_entry_link_lens.get_or_json_decode_error(json, path)
  let symlink_target_value = ownership_entry_symlink_target_lens.get_or_json_decode_error(
    json, path,
  )
  let resolved_target = ownership_entry_resolved_target_lens.get_or_json_decode_error(
    json, path,
  )
  let managed_root = ownership_entry_managed_root_lens.get_or_json_decode_error(
    json, path,
  )
  let source = ownership_entry_source_lens.get_or_json_decode_error(json, path)
  OwnershipEntry::OwnershipEntry(
    link,
    @path.Path(symlink_target_value),
    resolved_target,
    managed_root,
    source,
  ) catch {
    _ =>
      raise ownership_entry_link_lens.json_decode_error(
        path, "ownership link must be a direct child of its managed root",
      )
  }
}

///|
pub impl ToJson for OwnershipEntry with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  ownership_entry_link_lens.set_or_abort(builder, self.link)
  ownership_entry_symlink_target_lens.set_or_abort(
    builder,
    self.symlink_target.to_string(),
  )
  ownership_entry_resolved_target_lens.set_or_abort(
    builder,
    self.resolved_target,
  )
  ownership_entry_managed_root_lens.set_or_abort(builder, self.managed_root)
  ownership_entry_source_lens.set_or_abort(builder, self.source)
  builder.to_json()
}

///|
pub impl FromJson for OwnershipState with fn from_json(json, path) {
  let version = ownership_state_version_lens.get_or_json_decode_error(
    json, path,
  )
  guard version == "1" else {
    raise ownership_state_version_lens.json_decode_error(
      path,
      "unsupported ownership state version: \{version}",
    )
  }
  let entries = ownership_state_entries_lens.get_or_json_decode_error(
    json, path,
  )
  OwnershipState::OwnershipState(entries) catch {
    _ =>
      raise ownership_state_entries_lens.json_decode_error(
        path, "ownership links must be unique",
      )
  }
}

///|
pub impl ToJson for OwnershipState with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  let entries = self.entries.values().collect()
  entries.sort()
  ownership_state_version_lens.set_or_abort(builder, self.version.to_string())
  ownership_state_entries_lens.set_or_abort(builder, entries)
  builder.to_json()
}
