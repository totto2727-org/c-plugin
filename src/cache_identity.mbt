///|
pub(all) suberror CacheIdentityError {
  RelativePath(name~ : String, path~ : @path.Path)
  UnsupportedMetadataVersion(version~ : Int)
} derive(Debug)

///|
let cache_scope_metadata_version_lens : @lens.Lens[Int] = @lens.root().int(
  "version",
)

///|
let cache_scope_metadata_lock_path_lens : @lens.Lens[@x_path.AbsolutePath] = @lens.root().custom(
  "lockPath",
)

///|
pub struct CacheScopeMetadata {
  version : Int
  lock_path : @x_path.AbsolutePath
} derive(Eq, Debug)

///|
pub fn CacheScopeMetadata::CacheScopeMetadata(
  version : Int,
  lock_path : @path.Path,
) -> CacheScopeMetadata raise CacheIdentityError {
  guard version == 1 else { raise UnsupportedMetadataVersion(version~) }
  { version, lock_path: normalized_absolute_path("lock path", lock_path) }
}

///|
pub impl FromJson for CacheScopeMetadata with fn from_json(json, path) {
  let version = cache_scope_metadata_version_lens.get_or_json_decode_error(
    json, path,
  )
  let lock_path = cache_scope_metadata_lock_path_lens.get_or_json_decode_error(
    json, path,
  )
  CacheScopeMetadata::CacheScopeMetadata(version, lock_path.path) catch {
    _ =>
      raise cache_scope_metadata_version_lens.json_decode_error(
        path, "unsupported cache scope metadata version",
      )
  }
}

///|
pub impl ToJson for CacheScopeMetadata with fn to_json(self) -> Json {
  let builder = @lens.JsonBuilder::JsonBuilder()
  cache_scope_metadata_version_lens.set_or_abort(builder, self.version)
  cache_scope_metadata_lock_path_lens.set_or_abort(builder, self.lock_path)
  builder.to_json()
}

///|
pub struct CacheScope {
  lock_path : @x_path.AbsolutePath
  scope_key : String
} derive(Eq)

///|
pub fn CacheScope::CacheScope(
  lock_path : @path.Path,
) -> CacheScope raise CacheIdentityError {
  let normalized_lock_path = normalized_absolute_path("lock path", lock_path)
  let scope_key = @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode(
        "lock\u{0000}\{@x_path.Path::to_string(normalized_lock_path)}",
      ),
    ),
  )
  { lock_path: normalized_lock_path, scope_key }
}

///|
pub fn CacheScope::cache_path(
  self : CacheScope,
  cache_root : @path.Path,
  repository : GitHubRepository,
) -> @path.Path raise CacheIdentityError {
  normalized_absolute_path("cache root", cache_root).path
  .join(self.scope_key)
  .join(repository.owner.value)
  .join(repository.name.value)
}

///|
pub fn CacheScope::metadata(
  self : CacheScope,
) -> CacheScopeMetadata raise CacheIdentityError {
  CacheScopeMetadata::CacheScopeMetadata(1, self.lock_path.path)
}

///|
fn normalized_absolute_path(
  name : String,
  path : @path.Path,
) -> @x_path.AbsolutePath raise CacheIdentityError {
  @x_path.AbsolutePath::AbsolutePath(path) catch {
    _ => raise RelativePath(name~, path~)
  }
}
