///|
pub struct MarketplacePlugin {
  name : PluginName
  path : RelativePluginPath
} derive(Eq)

///|
pub fn MarketplacePlugin::MarketplacePlugin(
  name : PluginName,
  path : RelativePluginPath,
) -> MarketplacePlugin {
  { name, path }
}

///|
pub struct Marketplace {
  name : String
  plugins : ReadOnlyArray[MarketplacePlugin]
} derive(Eq)

///|
pub fn Marketplace::Marketplace(
  name : String,
  plugins : Array[MarketplacePlugin],
) -> Marketplace raise {
  let plugin_names = @immut_hashset.HashSet(plugins.map(plugin => plugin.name))
  guard plugin_names.length() == plugins.length() else {
    fail("marketplace plugin names must be unique")
  }
  { name, plugins: ReadOnlyArray::from_array(plugins) }
}

///|
let marketplace_name_lens : @lens.Lens[Json] = @lens.root().json("name")

///|
let marketplace_plugins_lens : @lens.Lens[Json] = @lens.root().json("plugins")

///|
let marketplace_plugin_name_lens : @lens.Lens[Json] = @lens.root().json("name")

///|
let marketplace_plugin_source_lens : @lens.Lens[Json] = @lens.root().json(
  "source",
)

///|
let codex_source_kind_lens : @lens.Lens[Json] = @lens.root().json("source")

///|
let codex_source_path_lens : @lens.Lens[Json] = @lens.root().json("path")

///|
#alias(CursorMarketplace)
struct ClaudeMarketplace {
  name : String
  plugins : ReadOnlyArray[ClaudeMarketplacePlugin]
}

///|
impl @json.FromJson for ClaudeMarketplace with fn from_json(json, path) {
  let name : String = marketplace_name_lens.decode_from_json(json, path)
  let plugins : Array[ClaudeMarketplacePlugin] = marketplace_plugins_lens.decode_from_json(
    json, path,
  )
  let plugin_names = @immut_hashset.HashSet(plugins.map(plugin => plugin.name))
  guard plugin_names.length() == plugins.length() else {
    raise @json.JsonDecodeError(
      (
        marketplace_plugins_lens.add_to_json_path(path),
        "marketplace plugin names must be unique",
      ),
    )
  }
  { name, plugins: ReadOnlyArray::from_array(plugins) }
}

///|
/// Encode the canonical minimal Claude/Cursor marketplace shape. Plugin declaration order is preserved and unmodeled input metadata is omitted.
pub impl ToJson for ClaudeMarketplace with fn to_json(self) {
  let builder = @lens.JsonBuilder::JsonBuilder()
  marketplace_name_lens.set_or_abort(builder, self.name.to_json())
  marketplace_plugins_lens.set_or_abort(
    builder,
    self.plugins.iter().to_array().to_json(),
  )
  builder.to_json()
}

///|
#alias(CursorMarketplacePlugin)
struct ClaudeMarketplacePlugin {
  name : PluginName
  source : RelativePluginPath
}

///|
impl @json.FromJson for ClaudeMarketplacePlugin with fn from_json(json, path) {
  let name : PluginName = marketplace_plugin_name_lens.decode_from_json(
    json, path,
  )
  let source : RelativePluginPath = marketplace_plugin_source_lens.decode_from_json(
    json, path,
  )
  { name, source }
}

///|
pub impl ToJson for ClaudeMarketplacePlugin with fn to_json(self) {
  let builder = @lens.JsonBuilder::JsonBuilder()
  marketplace_plugin_name_lens.set_or_abort(builder, self.name.to_json())
  marketplace_plugin_source_lens.set_or_abort(builder, self.source.to_json())
  builder.to_json()
}

///|
struct CodexMarketplace {
  name : String
  plugins : ReadOnlyArray[CodexMarketplacePlugin]
}

///|
impl @json.FromJson for CodexMarketplace with fn from_json(json, path) {
  let name : String = marketplace_name_lens.decode_from_json(json, path)
  let plugins : Array[CodexMarketplacePlugin] = marketplace_plugins_lens.decode_from_json(
    json, path,
  )
  let plugin_names = @immut_hashset.HashSet(plugins.map(plugin => plugin.name))
  guard plugin_names.length() == plugins.length() else {
    raise @json.JsonDecodeError(
      (
        marketplace_plugins_lens.add_to_json_path(path),
        "marketplace plugin names must be unique",
      ),
    )
  }
  { name, plugins: ReadOnlyArray::from_array(plugins) }
}

///|
/// Encode the canonical minimal Codex marketplace shape. Plugin declaration order is preserved and unmodeled input metadata is omitted.
pub impl ToJson for CodexMarketplace with fn to_json(self) {
  let builder = @lens.JsonBuilder::JsonBuilder()
  marketplace_name_lens.set_or_abort(builder, self.name.to_json())
  marketplace_plugins_lens.set_or_abort(
    builder,
    self.plugins.iter().to_array().to_json(),
  )
  builder.to_json()
}

///|
struct CodexMarketplacePlugin {
  name : PluginName
  source : CodexMarketplaceSource
}

///|
impl @json.FromJson for CodexMarketplacePlugin with fn from_json(json, path) {
  let name : PluginName = marketplace_plugin_name_lens.decode_from_json(
    json, path,
  )
  let source : CodexMarketplaceSource = marketplace_plugin_source_lens.decode_from_json(
    json, path,
  )
  { name, source }
}

///|
pub impl ToJson for CodexMarketplacePlugin with fn to_json(self) {
  let builder = @lens.JsonBuilder::JsonBuilder()
  marketplace_plugin_name_lens.set_or_abort(builder, self.name.to_json())
  marketplace_plugin_source_lens.set_or_abort(
    builder,
    ToJson::to_json(self.source),
  )
  builder.to_json()
}

///|
struct CodexMarketplaceSource {
  source : CodexMarketplaceSourceKind
  path : RelativePluginPath
}

///|
enum CodexMarketplaceSourceKind {
  Local
}

///|
impl @json.FromJson for CodexMarketplaceSourceKind with fn from_json(json, path) {
  let value : String = @json.from_json(json, path~)
  match value {
    "local" => Local
    unsupported =>
      raise @json.JsonDecodeError(
        (path, "unsupported Codex plugin source: \{unsupported}"),
      )
  }
}

///|
pub impl ToJson for CodexMarketplaceSourceKind with fn to_json(self) {
  match self {
    CodexMarketplaceSourceKind::Local => "local".to_json()
  }
}

///|
impl @json.FromJson for CodexMarketplaceSource with fn from_json(json, path) {
  let source : CodexMarketplaceSourceKind = codex_source_kind_lens.decode_from_json(
    json, path,
  )
  let plugin_path : RelativePluginPath = codex_source_path_lens.decode_from_json(
    json, path,
  )
  { source, path: plugin_path }
}

///|
pub impl ToJson for CodexMarketplaceSource with fn to_json(self) {
  let builder = @lens.JsonBuilder::JsonBuilder()
  codex_source_kind_lens.set_or_abort(builder, ToJson::to_json(self.source))
  codex_source_path_lens.set_or_abort(builder, self.path.to_json())
  builder.to_json()
}

///|
fn ClaudeMarketplace::normalize(self : ClaudeMarketplace) -> Marketplace {
  {
    name: self.name,
    plugins: self.plugins.map(plugin => {
      MarketplacePlugin(plugin.name, plugin.source)
    }),
  }
}

///|
fn CodexMarketplace::normalize(self : CodexMarketplace) -> Marketplace {
  {
    name: self.name,
    plugins: self.plugins.map(plugin => {
      match plugin.source.source {
        Local => MarketplacePlugin(plugin.name, plugin.source.path)
      }
    }),
  }
}

///|
pub fn Marketplace::from_json(
  kind : MarketplaceKind,
  json : Json,
) -> Marketplace raise @json.JsonDecodeError {
  match kind {
    Claude => {
      let marketplace : ClaudeMarketplace = @json.from_json(json)
      marketplace.normalize()
    }
    Cursor => {
      let marketplace : CursorMarketplace = @json.from_json(json)
      marketplace.normalize()
    }
    Codex => {
      let marketplace : CodexMarketplace = @json.from_json(json)
      marketplace.normalize()
    }
  }
}
