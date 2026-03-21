import Foundation
import SwiftData
import CryptoKit
import CloudKit

final class ExploreService {
    static let shared = ExploreService()

    enum PublishResult {
        case published(snapshotID: String, shortCode: String)
        case alreadyPublished(snapshotID: String, shortCode: String)
    }

    enum ExploreError: LocalizedError {
        case missingConfiguration
        case badResponse
        case serverError(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Explore is not configured."
            case .badResponse:
                return "Unexpected response from Explore server."
            case .serverError(let message):
                return message
            case .notFound:
                return "The requested record could not be found."
            }
        }
    }

    private let shortCodeAlphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    private let shareBaseURLString = "https://learnhub.shaarav.xyz/share"
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - API Methods

    func fetchSharedStudySets(limit: Int = 40, tag: String? = nil) async throws -> [SharedStudySet] {
        let records = try await CloudKitService.shared.fetchSharedStudySets(limit: limit, tag: tag)
        return records.compactMap { try? parseSharedStudySet(from: $0) }
    }

    func fetchFullStudySet(id: String) async throws -> SharedStudySet {
        let record = try await CloudKitService.shared.fetchFullStudySet(id: id)
        return try parseSharedStudySet(from: record)
    }

    func fetchFullStudySet(shortCode: String) async throws -> SharedStudySet {
        let code = shortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw ExploreError.badResponse }
        guard let record = try await CloudKitService.shared.fetchFullStudySet(shortCode: code) else {
            throw ExploreError.notFound
        }
        return try parseSharedStudySet(from: record)
    }

    func fetchAllTags() async throws -> [String] {
        return try await CloudKitService.shared.fetchAllTags()
    }

    func publish(studySet: StudySet, authorName: String?, generatedDescription: String, tags: [String] = []) async throws -> PublishResult {
        let publisherID = ExploreIdentity.publisherID()
        let fingerprint = fingerprint(for: studySet)
        
        let existingUserRecordName = try? await CloudKitService.shared.container.userRecordID().recordName

        if let existingRecord = try await CloudKitService.shared.existingSnapshot(publisherLegacyId: publisherID, fingerprint: fingerprint) {
            let snapshotID = existingRecord.recordID.recordName
            let existingCode = try? await CloudKitService.shared.fetchShareCode(snapshotID: snapshotID)
            let shortCode: String
            if let code = existingCode {
                shortCode = code
            } else {
                shortCode = try await ensureShortCode(for: snapshotID)
            }
            return .alreadyPublished(snapshotID: snapshotID, shortCode: shortCode)
        }

        let snapshotID = UUID().uuidString
        let record = CKRecord(recordType: "ExploreSharedStudySet", recordID: CKRecord.ID(recordName: snapshotID))
        
        record["author_name"] = authorName ?? "Anonymous"
        record["content_fingerprint"] = fingerprint
        record["created_at"] = Date()
        record["downloads_count"] = 0
        
        if let fcData = try? encoder.encode((studySet.flashcards ?? []).map({ SharedStudyFlashcard(id: UUID().uuidString, front: $0.front, back: $0.back) })) {
            record["flashcards"] = fcData
        }
        record["flashcards_count"] = (studySet.flashcards ?? []).count
        
        record["icon_id"] = studySet.iconId
        record["is_public"] = 1
        record["legacy_snapshot_id"] = snapshotID
        record["mode"] = studySet.mode
        record["publisher_legacy_id"] = publisherID
        record["publisher_user_record_name"] = existingUserRecordName ?? "unknown"
        
        if let qData = try? encoder.encode((studySet.questions ?? []).map({ SharedStudyQuestion(id: UUID().uuidString, prompt: $0.prompt, answer: $0.answer, explanation: $0.explanation, options: $0.options) })) {
            record["questions"] = qData
        }
        record["questions_count"] = (studySet.questions ?? []).count
        
        record["short_description"] = generatedDescription
        record["summary"] = studySet.summary
        if !tags.isEmpty {
            record["tags"] = tags
        }
        record["title"] = studySet.title

        try await CloudKitService.shared.saveRecord(record)
        let shortCode = try await ensureShortCode(for: snapshotID)

        return .published(snapshotID: snapshotID, shortCode: shortCode)
    }

    func unpublish(snapshotID: String) async throws {
        try await CloudKitService.shared.deleteRecord(withID: snapshotID)
    }

    func incrementDownloadCount(setId: String) async {
        try? await CloudKitService.shared.incrementDownloadCount(setId: setId)
    }

    func submitReview(snapshotID: String, reason: String, details: String? = nil) async throws {
        try await CloudKitService.shared.submitReview(snapshotID: snapshotID, reason: reason, details: details)
    }

    func shareURL(shortCode: String) -> URL? {
        let trimmed = shortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let baseURL = URL(string: shareBaseURLString) else {
            return nil
        }
        return baseURL.appendingPathComponent(trimmed)
    }

    // MARK: - Helpers

    private func ensureShortCode(for snapshotID: String) async throws -> String {
        for _ in 0..<6 {
            let shortCode = generateShortCode(length: 6)
            let recordID = CKRecord.ID(recordName: shortCode)
            let scRecord = CKRecord(recordType: "ExploreShareCode", recordID: recordID)
            scRecord["snapshot_id"] = snapshotID
            
            do {
                try await CloudKitService.shared.saveRecord(scRecord)
                return shortCode
            } catch let error as CKError {
                if error.code == .serverRecordChanged {
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        throw ExploreError.serverError("Failed to generate a unique short code.")
    }

    private func generateShortCode(length: Int) -> String {
        return String((0..<length).map { _ in shortCodeAlphabet.randomElement()! })
    }

    private func fingerprint(for studySet: StudySet) -> String {
        let qHashes = (studySet.questions ?? []).map { "\($0.prompt)|\($0.answer)" }.joined(separator: "||")
        let fHashes = (studySet.flashcards ?? []).map { "\($0.front)|\($0.back)" }.joined(separator: "||")
        let raw = "\(studySet.title)|\(studySet.summary ?? "")|\(qHashes)|\(fHashes)"
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    // Convert CKRecord to SharedStudySet model
    private func parseSharedStudySet(from record: CKRecord) throws -> SharedStudySet {
        let flashcardsData = record["flashcards"] as? Data
        let questionsData = record["questions"] as? Data
        
        let parsedFlashcards = flashcardsData != nil ? (try? decoder.decode([SharedStudyFlashcard].self, from: flashcardsData!)) : nil
        let parsedQuestions = questionsData != nil ? (try? decoder.decode([SharedStudyQuestion].self, from: questionsData!)) : nil

        return SharedStudySet(
            id: record.recordID.recordName,
            shortCode: record["short_code"] as? String,
            title: record["title"] as? String ?? "Untitled",
            summary: record["summary"] as? String,
            shortDescription: record["short_description"] as? String,
            mode: record["mode"] as? String ?? "content",
            iconId: record["icon_id"] as? String ?? "",
            authorName: record["author_name"] as? String,
            publisherId: record["publisher_legacy_id"] as? String,
            contentFingerprint: record["content_fingerprint"] as? String,
            createdAt: record["created_at"] as? Date ?? Date(),
            questions: parsedQuestions,
            flashcards: parsedFlashcards,
            tags: record["tags"] as? [String] ?? [],
            saveCount: record["downloads_count"] as? Int ?? 0,
            questionsCount: record["questions_count"] as? Int,
            flashcardsCount: record["flashcards_count"] as? Int
        )
    }
}

// MARK: - CloudKitService (Direct Integration)

actor CloudKitService {
    static let shared = CloudKitService()
    
    let container = CKContainer(identifier: "iCloud.com.shaarav4795.LearnHub")
    lazy var db = container.publicCloudDatabase
    
    let recordTypeSharedStudySet = "ExploreSharedStudySet"
    let recordTypeShareCode = "ExploreShareCode"
    let recordTypeReview = "ExploreReview"
    
    private init() {}
    
    func fetchSharedStudySets(limit: Int = 40, tag: String? = nil) async throws -> [CKRecord] {
        let predicate: NSPredicate
        if let tag = tag, !tag.isEmpty {
            predicate = NSPredicate(format: "tags CONTAINS %@", tag)
        } else {
            predicate = NSPredicate(value: true) 
        }
        
        let query = CKQuery(recordType: recordTypeSharedStudySet, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        
        let (matchResults, _) = try await db.records(matching: query, resultsLimit: limit)
        return matchResults.compactMap { try? $0.1.get() }
    }
    
    func fetchFullStudySet(id: String) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: id)
        return try await db.record(for: recordID)
    }
    
    func fetchFullStudySet(shortCode: String) async throws -> CKRecord? {
        let codeRecordID = CKRecord.ID(recordName: shortCode)
        guard let codeRecord = try? await db.record(for: codeRecordID) else {
            return nil
        }
        guard let snapshotID = codeRecord["snapshot_id"] as? String else {
            return nil
        }
        return try await fetchFullStudySet(id: snapshotID)
    }
    
    func fetchShareCode(snapshotID: String) async throws -> String? {
        let predicate = NSPredicate(format: "snapshot_id == %@", snapshotID)
        let query = CKQuery(recordType: recordTypeShareCode, predicate: predicate)
        let (matchResults, _) = try await db.records(matching: query, resultsLimit: 1)
        if let record = matchResults.compactMap({ try? $0.1.get() }).first {
            return record.recordID.recordName
        }
        return nil
    }
    
    func saveRecord(_ record: CKRecord) async throws {
        try await db.save(record)
    }
    
    func deleteRecord(withID id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await db.deleteRecord(withID: recordID)
    }
    
    func fetchAllTags() async throws -> [String] {
        let query = CKQuery(recordType: recordTypeSharedStudySet, predicate: NSPredicate(value: true))
        let (matchResults, _) = try await db.records(matching: query, desiredKeys: ["tags"])
        let records = matchResults.compactMap { try? $0.1.get() }
        var allTags = Set<String>()
        for record in records {
            if let tags = record["tags"] as? [String] {
                tags.forEach { allTags.insert($0) }
            }
        }
        return Array(allTags).sorted()
    }
    
    func existingSnapshot(publisherLegacyId: String, fingerprint: String) async throws -> CKRecord? {
        let predicate = NSPredicate(format: "publisher_legacy_id == %@ AND content_fingerprint == %@", publisherLegacyId, fingerprint)
        let query = CKQuery(recordType: recordTypeSharedStudySet, predicate: predicate)
        let (matchResults, _) = try await db.records(matching: query, resultsLimit: 1)
        return matchResults.compactMap({ try? $0.1.get() }).first
    }
    
    func incrementDownloadCount(setId: String) async throws {
        let recordID = CKRecord.ID(recordName: setId)
        let record = try await db.record(for: recordID)
        let currentCount = record["downloads_count"] as? Int ?? 0
        record["downloads_count"] = currentCount + 1
        try await db.save(record)
    }
    
    func submitReview(snapshotID: String, reason: String, details: String?) async throws {
        let record = CKRecord(recordType: recordTypeReview)
        record["shared_set_id"] = snapshotID
        record["reason"] = reason
        if let details = details {
            record["details"] = details
        }
        record["created_at"] = Date()
        try await db.save(record)
    }
}
