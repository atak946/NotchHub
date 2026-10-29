import Foundation

/// Persisted index entry. Payloads live in `ShelfPayloadStorage`; files are bookmarks.
struct ShelfRecord: Codable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case file
        case text
        case image
    }

    let id: UUID
    let kind: String
    let addedAt: Date
    let bookmark: Data?

    var knownKind: Kind? { Kind(rawValue: kind) }

    init(id: UUID, kind: Kind, addedAt: Date, bookmark: Data? = nil) {
        self.id = id
        self.kind = kind.rawValue
        self.addedAt = addedAt
        self.bookmark = bookmark
    }

    /// Decodes an index, skipping entries that are malformed instead of failing the whole list.
    static func decodeList(from data: Data) -> [ShelfRecord]? {
        guard let entries = try? JSONDecoder().decode([LenientEntry].self, from: data) else { return nil }
        return entries.compactMap(\.record)
    }

    private struct LenientEntry: Decodable {
        let record: ShelfRecord?

        init(from decoder: any Decoder) throws {
            record = try? ShelfRecord(from: decoder)
        }
    }
}
