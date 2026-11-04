import Foundation

/// A locally stored face profile. No images are kept — only Vision feature prints.
struct FaceProfile: Codable {
    var version: Int
    var createdAt: Date
    var sampleCount: Int
    var embeddings: [[Float]]

    init(createdAt: Date = Date(), embeddings: [[Float]]) {
        self.version = 1
        self.createdAt = createdAt
        self.sampleCount = embeddings.count
        self.embeddings = embeddings
    }

    var isEmpty: Bool {
        embeddings.isEmpty
    }
}
