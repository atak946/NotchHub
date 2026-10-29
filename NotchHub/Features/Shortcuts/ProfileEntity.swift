import AppIntents
import Foundation

/// A client profile exposed to Shortcuts.
struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Profil"
    static let defaultQuery = ProfileEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ profile: IntentProfile) {
        self.init(id: profile.id, name: profile.name)
    }
}

/// Looks profiles up through the bridge (so it works only while the app is ready).
struct ProfileEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        let wanted = Set(identifiers)
        return try await IntentServicesBridge.shared.profiles()
            .filter { wanted.contains($0.id) }
            .map(ProfileEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [ProfileEntity] {
        try await IntentServicesBridge.shared.profiles().map(ProfileEntity.init)
    }
}
