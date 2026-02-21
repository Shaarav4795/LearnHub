import Foundation
import SwiftData

struct SharedStudyQuestion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let prompt: String
    let answer: String
    let explanation: String?
    let options: [String]?
}

struct SharedStudyFlashcard: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let front: String
    let back: String
}

struct SharedStudySet: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let shortCode: String?
    let title: String
    let summary: String?
    let shortDescription: String?
    let mode: String
    let iconId: String
    let authorName: String?
    let publisherId: String?
    let contentFingerprint: String?
    let createdAt: Date
    let questions: [SharedStudyQuestion]?
    let flashcards: [SharedStudyFlashcard]?
    /// AI-generated subject tags (populated at publish time by the moderation pass)
    let tags: [String]
    /// Number of times users have downloaded this set to My Sets
    let saveCount: Int

    /// Computed counts for display when full content is not loaded
    let questionsCount: Int?
    let flashcardsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case shortCode = "short_code"
        case title
        case summary
        case shortDescription = "short_description"
        case mode
        case iconId = "icon_id"
        case authorName = "author_name"
        case publisherId = "publisher_id"
        case contentFingerprint = "content_fingerprint"
        case createdAt = "created_at"
        case questions
        case flashcards
        case tags
        case saveCount = "downloads_count"
        case questionsCount = "questions_count"
        case flashcardsCount = "flashcards_count"
    }

    static func snapshot(from studySet: StudySet, authorName: String?, tags: [String] = []) -> SharedStudySet {
        SharedStudySet(
            id: UUID().uuidString,
            shortCode: nil,
            title: studySet.title,
            summary: studySet.summary,
            shortDescription: nil,
            mode: studySet.mode,
            iconId: studySet.iconId,
            authorName: authorName,
            publisherId: nil,
            contentFingerprint: nil,
            createdAt: Date(),
            questions: studySet.questions.map {
                SharedStudyQuestion(
                    id: UUID().uuidString,
                    prompt: $0.prompt,
                    answer: $0.answer,
                    explanation: $0.explanation,
                    options: $0.options
                )
            },
            flashcards: studySet.flashcards.map {
                SharedStudyFlashcard(
                    id: UUID().uuidString,
                    front: $0.front,
                    back: $0.back
                )
            },
            tags: tags,
            saveCount: 0,
            questionsCount: studySet.questions.count,
            flashcardsCount: studySet.flashcards.count
        )
    }
}

enum ExploreCloneBuilder {
    static func cloneToLocalStudySet(from sharedSet: SharedStudySet) -> StudySet {
        let title = sharedSet.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.isEmpty ? "Imported Study Set" : title

        let local = StudySet(
            title: cleanTitle,
            originalText: "Imported from Explore",
            summary: sharedSet.summary,
            dateCreated: Date(),
            mode: StudySetMode(rawValue: sharedSet.mode) ?? .content,
            iconId: sharedSet.iconId
        )

        local.questions = (sharedSet.questions ?? []).map { remoteQuestion in
            Question(
                prompt: remoteQuestion.prompt,
                answer: remoteQuestion.answer,
                options: remoteQuestion.options,
                explanation: remoteQuestion.explanation,
                reviewDueDate: nil,
                reviewIntervalDays: 0,
                reviewStability: 0,
                reviewDifficulty: 5,
                reviewRepetitions: 0,
                reviewLastReviewedAt: nil,
                reviewLapses: 0
            )
        }

        local.flashcards = (sharedSet.flashcards ?? []).map { remoteFlashcard in
            Flashcard(
                front: remoteFlashcard.front,
                back: remoteFlashcard.back,
                isMastered: false,
                reviewDueDate: nil,
                reviewIntervalDays: 0,
                reviewStability: 0,
                reviewDifficulty: 5,
                reviewRepetitions: 0,
                reviewLastReviewedAt: nil,
                reviewLapses: 0
            )
        }

        local.importedFromSharedId = sharedSet.id

        return local
    }
}
