import AppIntents
import WidgetKit
import Foundation

// MARK: - Study-set entity

struct StudySetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Study Set"
    static var defaultQuery = StudySetQuery()
    
    var id: UUID
    var title: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
    
    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

struct StudySetQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [StudySetEntity] {
        let data = WidgetData.load()
        return data.studySets
            .filter { identifiers.contains($0.id) }
            .map { StudySetEntity(id: $0.id, title: $0.title) }
    }
    
    func suggestedEntities() async throws -> [StudySetEntity] {
        let data = WidgetData.load()
        return data.studySets.map { StudySetEntity(id: $0.id, title: $0.title) }
    }
    
    func defaultResult() async -> StudySetEntity? {
        try? await suggestedEntities().first
    }
}

// MARK: - Widget configuration intent

struct SelectStudySetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Study Set"
    static var description: IntentDescription = "Choose a flashcard set to display."
    
    @Parameter(title: "Study Set")
    var studySet: StudySetEntity?
}

// MARK: - Stats configuration intent

enum StatsType: String, AppEnum {
    case streak
    case reviewCount
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Stats Type"
    static var caseDisplayRepresentations: [StatsType : DisplayRepresentation] = [
        .streak: "Study Streak",
        .reviewCount: "Next Review Count"
    ]
}

struct StatsConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Stats Configuration"
    static var description: IntentDescription = "Choose which statistic to display."
    
    @Parameter(title: "Statistic", default: .streak)
    var statsType: StatsType
}

// MARK: - Interaction intents

struct FlipFlashcardIntent: AppIntent {
    static var title: LocalizedStringResource = "Flip Card"
    
    @Parameter(title: "Set ID")
    var setID: String
    
    init() {}
    init(setID: UUID) {
        self.setID = setID.uuidString
    }
    
    func perform() async throws -> some IntentResult {
        let key = "flipState_\(setID)"
        let defaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub.hf")
        let current = defaults?.bool(forKey: key) ?? false
        defaults?.set(!current, forKey: key)
        return .result()
    }
}

struct NextFlashcardIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Card"
    
    @Parameter(title: "Set ID")
    var setID: String
    
    init() {}
    init(setID: UUID) {
        self.setID = setID.uuidString
    }
    
    func perform() async throws -> some IntentResult {
        let key = "cardIndex_\(setID)"
        let defaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub.hf")
        let current = defaults?.integer(forKey: key) ?? 0
        
        let data = WidgetData.load()
        if let set = data.studySets.first(where: { $0.id.uuidString == setID }) {
            let count = set.flashcards.count
            if count > 0 {
                defaults?.set((current + 1) % count, forKey: key)
                // Reset flip state when advancing to the next card.
                defaults?.set(false, forKey: "flipState_\(setID)")
            }
        }
        
        return .result()
    }
}
