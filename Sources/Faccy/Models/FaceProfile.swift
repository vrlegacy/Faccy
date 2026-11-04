import Foundation

/// One enrolled face. No images are kept — only Vision feature prints.
/// Faccy stores up to `AppModel.maxFaces` of these; any of them unlocks.
struct FaceProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var version: Int
    var createdAt: Date
    var sampleCount: Int
    var embeddings: [[Float]]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), embeddings: [[Float]]) {
        self.id = id
        self.name = name
        self.version = 2
        self.createdAt = createdAt
        self.sampleCount = embeddings.count
        self.embeddings = embeddings
    }

    var isEmpty: Bool {
        embeddings.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, version, createdAt, sampleCount, embeddings
    }

    /// Version 1 profiles (a single face, no id or name) still decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Face 1"
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        embeddings = try container.decode([[Float]].self, forKey: .embeddings)
        sampleCount = try container.decodeIfPresent(Int.self, forKey: .sampleCount) ?? embeddings.count
    }
}
