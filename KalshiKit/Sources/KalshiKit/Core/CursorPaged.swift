import Foundation

/// A response page that carries a Kalshi pagination cursor.
///
/// Kalshi list endpoints return an array plus a `cursor` string; passing that
/// cursor back as `?cursor=` fetches the next page. An empty/absent cursor means
/// the end of the collection. List response models conform to this so the client
/// can offer a generic `paginate(...)` helper.
public protocol CursorPaged {
    associatedtype Element
    /// The page's items.
    var items: [Element] { get }
    /// Cursor for the next page, or `nil`/empty when exhausted.
    var cursor: String? { get }
}

public extension CursorPaged {
    /// Normalizes empty-string cursors to `nil`.
    var nextCursor: String? {
        guard let cursor, !cursor.isEmpty else { return nil }
        return cursor
    }
}
