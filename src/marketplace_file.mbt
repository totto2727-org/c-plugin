///|
/// Typed failures from the marketplace file-read boundary.
pub(all) suberror MarketplaceReadError {
  IO(path~ : @path.Path, reason~ : String)
  Syntax(path~ : @path.Path, cause~ : @json.ParseError)
  Validation(path~ : @path.Path, cause~ : @json.JsonDecodeError)
} derive(Debug)

///|
/// Read and decode a marketplace without performing property-level decoding at the I/O boundary.
pub async fn read_marketplace_file(
  path : @path.Path,
  kind : MarketplaceKind,
) -> Marketplace raise MarketplaceReadError {
  let text = @fs.read_file(path.to_string()).text() catch {
    error => raise IO(path~, reason=error.to_string())
  }
  let json = @json.parse(text) catch {
    error => raise Syntax(path~, cause=error)
  }
  Marketplace::from_json(kind, json) catch {
    error => raise Validation(path~, cause=error)
  }
}
