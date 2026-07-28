import Foundation

enum AttachmentParent: String, Codable, Equatable, Sendable {
    case venue
    case vendor
}

struct Attachment: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let weddingID: UUID
    let parent: AttachmentParent
    let parentID: UUID
    let storagePath: String
    let fileName: String
    let mimeType: String?
    let sizeBytes: Int64?
    let uploadedBy: UUID?
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case weddingID = "weddingId"
        case parent = "parentType"
        case parentID = "parentId"
        case storagePath = "storagePath"
        case fileName = "fileName"
        case mimeType = "mimeType"
        case sizeBytes = "sizeBytes"
        case uploadedBy = "uploadedBy"
        case createdAt
        case updatedAt
    }
}

enum AttachmentPath {
    static func make(
        weddingID: UUID,
        parent: AttachmentParent,
        parentID: UUID,
        fileName: String,
        objectID: UUID = UUID()
    ) -> String {
        let safeName = safeFileName(fileName)
        return "\(weddingID.uuidString.lowercased())/\(parent.rawValue)/\(parentID.uuidString.lowercased())/\(objectID.uuidString.lowercased())-\(safeName)"
    }

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let name = String(result).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return name.isEmpty ? "attachment" : name
    }
}
