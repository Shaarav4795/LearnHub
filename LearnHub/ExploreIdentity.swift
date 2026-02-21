import Foundation

enum ExploreIdentity {
    private static let publisherIDKey = "explore.publisher.id"

    static func publisherID() -> String {
        if let existing = UserDefaults.standard.string(forKey: publisherIDKey), !existing.isEmpty {
            return existing
        }

        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: publisherIDKey)
        return created
    }
}
