import Foundation
import SwiftData

enum StudySetMode: String, Codable {
    case content = "content"  // Generated from source material
    case topic = "topic"      // Generated from topic description
}

// MARK: - Study Set Icons

struct StudySetIcon: Identifiable, Hashable {
    let id: String
    let name: String
    let systemName: String
    
    static let allIcons: [StudySetIcon] = [
        StudySetIcon(id: "book", name: "Book", systemName: "book.closed.fill"),
        StudySetIcon(id: "brain", name: "Brain", systemName: "brain.head.profile"),
        StudySetIcon(id: "lightbulb", name: "Lightbulb", systemName: "lightbulb.fill"),
        StudySetIcon(id: "star", name: "Star", systemName: "star.fill"),
        StudySetIcon(id: "bookmark", name: "Bookmark", systemName: "bookmark.fill"),
        StudySetIcon(id: "folder", name: "Folder", systemName: "folder.fill"),
        StudySetIcon(id: "doc", name: "Document", systemName: "doc.text.fill"),
        StudySetIcon(id: "graduationcap", name: "Graduation", systemName: "graduationcap.fill"),
        StudySetIcon(id: "pencil", name: "Pencil", systemName: "pencil.circle.fill"),
        StudySetIcon(id: "atom", name: "Science", systemName: "atom"),
        StudySetIcon(id: "function", name: "Math", systemName: "function"),
        StudySetIcon(id: "globe", name: "Geography", systemName: "globe.americas.fill"),
        StudySetIcon(id: "music", name: "Music", systemName: "music.note"),
        StudySetIcon(id: "paintpalette", name: "Art", systemName: "paintpalette.fill"),
        StudySetIcon(id: "heart", name: "Health", systemName: "heart.fill"),
        StudySetIcon(id: "laptopcomputer", name: "Computer", systemName: "laptopcomputer"),
        StudySetIcon(id: "building", name: "History", systemName: "building.columns.fill"),
        StudySetIcon(id: "leaf", name: "Nature", systemName: "leaf.fill"),
        StudySetIcon(id: "flask", name: "Chemistry", systemName: "flask.fill"),
        StudySetIcon(id: "sparkles", name: "Magic", systemName: "sparkles"),
    ]
    
    static let defaultIcon = allIcons[0]
    
    static func icon(for id: String) -> StudySetIcon? {
        allIcons.first { $0.id == id }
    }
}

// MARK: - Tutor Models

/// Response format type for specialized quick prompts
enum TutorResponseFormatType: String, Sendable, Codable {
    case standard
    case comparison   // Side-by-side table format
    case mnemonic     // Memory device with breakdown
    case steps        // Numbered step-by-step
    case example      // Real-world scenario format
    case simplify     // ELI5 format
    case keyPoints    // Bullet highlights
    case analogy      // Analogy-focused
    case mistakes     // Common errors format
    case mathSolver   // Step-by-step math problem solver
}

struct QuickPrompt: Identifiable, Sendable {
    let id: String
    let label: String
    let icon: String
    let prompt: String
    let format: TutorResponseFormatType
    
    nonisolated init(id: String, label: String, icon: String, prompt: String, format: TutorResponseFormatType = .standard) {
        self.id = id
        self.label = label
        self.icon = icon
        self.prompt = prompt
        self.format = format
    }
}

@Model
final class StudyFolder {
    var id: UUID
    var name: String
    var dateCreated: Date
    var iconId: String = "folder"
    
    @Relationship(deleteRule: .nullify, inverse: \StudySet.folder) var studySets: [StudySet] = []
    
    init(name: String, dateCreated: Date = Date(), iconId: String = "folder") {
        self.id = UUID()
        self.name = name
        self.dateCreated = dateCreated
        self.iconId = iconId
    }
}

@Model
final class StudySet {
    var id: UUID
    var title: String
    var originalText: String
    var dateCreated: Date
    var summary: String?
    var mode: String = "content"  // "content" or "topic" - default to content for migration
    var iconId: String = "book"   // Default icon for migration
    var sharedSnapshotId: String?
    var importedFromSharedId: String?
    
    @Relationship(deleteRule: .cascade) var flashcards: [Flashcard] = []
    @Relationship(deleteRule: .cascade) var questions: [Question] = []
    @Relationship(deleteRule: .cascade) var chatHistory: [ChatMessage] = []
    var folder: StudyFolder?
    
    init(title: String, originalText: String, summary: String? = nil, dateCreated: Date = Date(), mode: StudySetMode = .content, iconId: String = "book") {
        self.id = UUID()
        self.title = title
        self.originalText = originalText
        self.summary = summary
        self.dateCreated = dateCreated
        self.mode = mode.rawValue
        self.iconId = iconId
        self.sharedSnapshotId = nil
        self.importedFromSharedId = nil
    }
    
    var studySetMode: StudySetMode {
        StudySetMode(rawValue: mode) ?? .content
    }
    
    var icon: StudySetIcon {
        StudySetIcon.icon(for: iconId) ?? StudySetIcon.defaultIcon
    }
    
    /// Returns sorted chat history by timestamp
    var sortedChatHistory: [ChatMessage] {
        chatHistory.sorted { $0.timestamp < $1.timestamp }
    }
}

@Model
final class Flashcard {
    var id: UUID
    var front: String
    var back: String
    var isMastered: Bool
    var reviewDueDate: Date?
    var reviewIntervalDays: Double = 0
    var reviewStability: Double = 0
    var reviewDifficulty: Double = 5
    var reviewRepetitions: Int = 0
    var reviewLastReviewedAt: Date?
    var reviewLapses: Int = 0
    
    var studySet: StudySet?
    
    init(
        front: String,
        back: String,
        isMastered: Bool = false,
        reviewDueDate: Date? = nil,
        reviewIntervalDays: Double = 0,
        reviewStability: Double = 0,
        reviewDifficulty: Double = 5,
        reviewRepetitions: Int = 0,
        reviewLastReviewedAt: Date? = nil,
        reviewLapses: Int = 0
    ) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.isMastered = isMastered
        self.reviewDueDate = reviewDueDate
        self.reviewIntervalDays = reviewIntervalDays
        self.reviewStability = reviewStability
        self.reviewDifficulty = reviewDifficulty
        self.reviewRepetitions = reviewRepetitions
        self.reviewLastReviewedAt = reviewLastReviewedAt
        self.reviewLapses = reviewLapses
    }

    var isNewForReview: Bool {
        reviewDueDate == nil && reviewRepetitions == 0
    }

    var isDueForReview: Bool {
        guard let reviewDueDate else { return false }
        return reviewDueDate <= Date()
    }
}

@Model
final class Question {
    var id: UUID
    var prompt: String
    var answer: String
    var options: [String]? // For multiple choice if needed later
    var explanation: String?
    var reviewDueDate: Date?
    var reviewIntervalDays: Double = 0
    var reviewStability: Double = 0
    var reviewDifficulty: Double = 5
    var reviewRepetitions: Int = 0
    var reviewLastReviewedAt: Date?
    var reviewLapses: Int = 0
    
    var studySet: StudySet?
    
    init(
        prompt: String,
        answer: String,
        options: [String]? = nil,
        explanation: String? = nil,
        reviewDueDate: Date? = nil,
        reviewIntervalDays: Double = 0,
        reviewStability: Double = 0,
        reviewDifficulty: Double = 5,
        reviewRepetitions: Int = 0,
        reviewLastReviewedAt: Date? = nil,
        reviewLapses: Int = 0
    ) {
        self.id = UUID()
        self.prompt = prompt
        self.answer = answer
        self.options = options
        self.explanation = explanation
        self.reviewDueDate = reviewDueDate
        self.reviewIntervalDays = reviewIntervalDays
        self.reviewStability = reviewStability
        self.reviewDifficulty = reviewDifficulty
        self.reviewRepetitions = reviewRepetitions
        self.reviewLastReviewedAt = reviewLastReviewedAt
        self.reviewLapses = reviewLapses
    }

    var isNewForReview: Bool {
        reviewDueDate == nil && reviewRepetitions == 0
    }

    var isDueForReview: Bool {
        guard let reviewDueDate else { return false }
        return reviewDueDate <= Date()
    }
}

// MARK: - Tutor Chat Message

@Model
final class ChatMessage {
    var id: UUID
    var text: String
    var isUser: Bool
    var timestamp: Date
    
    var studySet: StudySet?
    
    init(text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }
}
