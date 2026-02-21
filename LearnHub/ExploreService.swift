import Foundation
import CryptoKit

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

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "Explore is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY to Info.plist."
            case .badResponse:
                return "Unexpected response from Explore server."
            case .serverError(let message):
                return message
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // SECURITY NOTE
    // The Supabase anon key is intentionally a *public* client credential —
    // it is safe to ship in the app bundle (this is Supabase's design).
    // The real security perimeter is Row-Level Security (RLS) on Supabase:
    //   • SELECT  – only rows where is_public = true
    //   • INSERT  – requires publisher_id + content_fingerprint, is_public must be true
    //   • UPDATE  – NO direct REST access; must go through signed RPC functions
    //     ╰ increment_save_count(set_id)          — additive only, harmless
    //     ╰ unpublish_study_set(snapshot_id, pub)  — verified by publisher_id match
    //     ╰ set_study_set_tags(snapshot_id, pub, tags) — verified by publisher_id match
    // Rotate the key in Supabase Dashboard if you believe it was compromised.
    // ─────────────────────────────────────────────────────────────────────
    private struct Config {
        let baseURL: URL
        let apiKey: String

        private static func envValue(_ key: String) -> String? {
            ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func load() -> Config? {
            let plistURL = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let plistKey = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let urlString = envValue("SUPABASE_URL") ?? plistURL
            let rawKey = envValue("SUPABASE_ANON_KEY") ?? plistKey

            guard
                let urlString,
                let rawKey,
                let baseURL = URL(string: urlString)
            else {
                return nil
            }

            let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let isLegacyAnon = apiKey.hasPrefix("eyJ")
            let isPublishable = apiKey.hasPrefix("sb_publishable_")
            guard !apiKey.isEmpty, isLegacyAnon || isPublishable else {
                assertionFailure("[ExploreService] SUPABASE_ANON_KEY in Info.plist looks invalid.")
                return nil
            }

            #if DEBUG
            if isLegacyAnon {
                print("[ExploreService] Using legacy anon key. Prefer sb_publishable_ key for improved security posture.")
            }
            #endif

            return Config(baseURL: baseURL, apiKey: apiKey)
        }
    }

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let shortCodeAlphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    private let shareBaseURLString = "https://learnhub.shaarav.xyz/share"

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    /// Fetches public study sets, sorted by most saves descending.
    /// This fetches headers only (no questions/flashcards) to reduce egress.
    /// - Parameters:
    ///   - limit: Maximum number of rows to return (capped at 100).
    ///   - tag: Optional subject tag to filter by (server-side GIN array contains).
    func fetchSharedStudySets(limit: Int = 40, tag: String? = nil) async throws -> [SharedStudySet] {
        guard let config = Config.load() else {
            throw ExploreError.missingConfiguration
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,short_code,title,summary,short_description,mode,icon_id,author_name,publisher_id,content_fingerprint,created_at,tags,downloads_count,questions_count,flashcards_count"),
            URLQueryItem(name: "order", value: "downloads_count.desc,created_at.desc"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
        ]

        // Server-side tag filter using PostgREST array-contains operator
        if let tag = tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: "cs.{\(tag)}"))
        }

        var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw ExploreError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(request: &request, config: config)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
            if isMissingShortCodeColumnError(message) {
                return try await fetchSharedStudySetsWithoutShortCode(limit: limit, tag: tag, config: config)
            }
            throw ExploreError.serverError(message)
        }

        return try decoder.decode([SharedStudySet].self, from: data)
    }

    /// Fetches the full content for a specific study set (questions and flashcards).
    func fetchFullStudySet(id: String) async throws -> SharedStudySet {
        guard let config = Config.load() else {
            throw ExploreError.missingConfiguration
        }

        var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            throw ExploreError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(request: &request, config: config)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
            throw ExploreError.serverError(message)
        }

        let results = try decoder.decode([SharedStudySet].self, from: data)
        guard let first = results.first else {
            throw ExploreError.badResponse
        }
        return first
    }

    /// Fetches the full content for a specific shared short code.
    func fetchFullStudySet(shortCode: String) async throws -> SharedStudySet {
        guard let config = Config.load() else {
            throw ExploreError.missingConfiguration
        }

        let code = shortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            throw ExploreError.badResponse
        }

        var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "short_code", value: "eq.\(code)"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            throw ExploreError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(request: &request, config: config)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
            if isMissingShortCodeColumnError(message), UUID(uuidString: code) != nil {
                return try await fetchFullStudySet(id: code)
            }
            throw ExploreError.serverError(message)
        }

        let results = try decoder.decode([SharedStudySet].self, from: data)
        guard let first = results.first else {
            throw ExploreError.serverError("Shared set not found.")
        }
        return first
    }

    /// Collects all unique tags across public sets (for the filter chip bar).
    func fetchAllTags() async throws -> [String] {
        guard let config = Config.load() else { throw ExploreError.missingConfiguration }

        var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "tags"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "limit", value: "200")
        ]

        guard let url = components?.url else { throw ExploreError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(request: &request, config: config)

        let (data, _) = try await URLSession.shared.data(for: request)
        struct TagsOnly: Decodable { let tags: [String] }
        let rows = (try? decoder.decode([TagsOnly].self, from: data)) ?? []
        let all = rows.flatMap { $0.tags }
        // Deduplicate, sort alphabetically
        return Array(Set(all)).sorted()
    }

    func publish(studySet: StudySet, authorName: String?, generatedDescription: String, tags: [String] = []) async throws -> PublishResult {
        guard let config = Config.load() else {
            throw ExploreError.missingConfiguration
        }

        let publisherID = ExploreIdentity.publisherID()
        let fingerprint = fingerprint(for: studySet)

        if let existing = try await existingSnapshot(
            config: config,
            publisherID: publisherID,
            fingerprint: fingerprint
        ) {
            let existingCode = try await ensureShortCode(
                config: config,
                snapshotID: existing.id,
                publisherID: publisherID,
                currentCode: existing.shortCode
            )
            return .alreadyPublished(snapshotID: existing.id, shortCode: existingCode)
        }

        let snapshot = SharedStudySet.snapshot(from: studySet, authorName: authorName, tags: tags)

        var attemptsRemaining = 6
        while attemptsRemaining > 0 {
            attemptsRemaining -= 1
            let shortCode = generateShortCode(length: 6)

            let payload = PublishPayload(
                id: snapshot.id,
                shortCode: shortCode,
                title: snapshot.title,
                summary: snapshot.summary,
                shortDescription: generatedDescription,
                mode: snapshot.mode,
                iconId: snapshot.iconId,
                authorName: snapshot.authorName,
                publisherId: publisherID,
                contentFingerprint: fingerprint,
                createdAt: snapshot.createdAt,
                isPublic: true,
                questions: snapshot.questions ?? [],
                flashcards: snapshot.flashcards ?? [],
                tags: tags
            )

            var request = URLRequest(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"))
            request.httpMethod = "POST"
            applyHeaders(request: &request, config: config)
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ExploreError.badResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                return .published(snapshotID: snapshot.id, shortCode: shortCode)
            }

            let message = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
            if isMissingShortCodeColumnError(message) {
                return try await publishWithoutShortCode(
                    snapshot: snapshot,
                    fingerprint: fingerprint,
                    generatedDescription: generatedDescription,
                    tags: tags,
                    publisherID: publisherID,
                    config: config
                )
            }
            if httpResponse.statusCode == 409, message.localizedCaseInsensitiveContains("short_code"), attemptsRemaining > 0 {
                continue
            }

            throw ExploreError.serverError(message)
        }

        throw ExploreError.serverError("Could not allocate a unique share code. Please try again.")
    }

    func shareURL(shortCode: String) -> URL? {
        let trimmed = shortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let baseURL = URL(string: shareBaseURLString) else {
            return nil
        }
        return baseURL.appendingPathComponent(trimmed)
    }

    /// Hard-deletes a published set by snapshot + publisher ownership.
    /// Requires a matching RLS delete policy for anon key usage.
    func unpublish(snapshotID: String) async throws {
        guard let config = Config.load() else {
            throw ExploreError.missingConfiguration
        }

        let publisherID = ExploreIdentity.publisherID()

        var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(snapshotID)"),
            URLQueryItem(name: "publisher_id", value: "eq.\(publisherID)")
        ]

        guard let url = components?.url else {
            throw ExploreError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyHeaders(request: &request, config: config)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ExploreError.serverError(parseErrorMessage(data: data, statusCode: httpResponse.statusCode))
        }
    }

    /// Increments downloads_count when a user saves a shared set to My Sets.
    func incrementDownloadCount(setId: String) async {
        guard let config = Config.load() else { return }

        struct Args: Encodable { let set_id: String }

        guard let uuid = UUID(uuidString: setId) else { return }
        var request = URLRequest(url: config.baseURL.appendingPathComponent("rest/v1/rpc/increment_download_count"))
        request.httpMethod = "POST"
        applyHeaders(request: &request, config: config)
        request.httpBody = try? encoder.encode(Args(set_id: uuid.uuidString))

        _ = try? await URLSession.shared.data(for: request)
    }

    func submitReview(snapshotID: String, reason: String, details: String? = nil) async throws {
        guard let config = Config.load() else {
            throw ExploreError.missingConfiguration
        }

        struct ReviewPayload: Encodable {
            let shared_set_id: String
            let reporter_id: String
            let reason: String
            let details: String?
        }

        var request = URLRequest(url: config.baseURL.appendingPathComponent("rest/v1/review"))
        request.httpMethod = "POST"
        applyHeaders(request: &request, config: config)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(
            ReviewPayload(
                shared_set_id: snapshotID,
                reporter_id: ExploreIdentity.publisherID(),
                reason: reason,
                details: details
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ExploreError.serverError(parseErrorMessage(data: data, statusCode: httpResponse.statusCode))
        }
    }

    private func applyHeaders(request: inout URLRequest, config: Config) {
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func parseErrorMessage(data: Data, statusCode: Int) -> String {
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? String
        {
            return message
        }

        return "Explore request failed with status \(statusCode)."
    }

    private func existingSnapshot(config: Config, publisherID: String, fingerprint: String) async throws -> ExistingSnapshot? {
        var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id,short_code"),
            URLQueryItem(name: "publisher_id", value: "eq.\(publisherID)"),
            URLQueryItem(name: "content_fingerprint", value: "eq.\(fingerprint)"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let url = components?.url else {
            throw ExploreError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(request: &request, config: config)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
            if isMissingShortCodeColumnError(message) {
                var fallbackComponents = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
                fallbackComponents?.queryItems = [
                    URLQueryItem(name: "select", value: "id"),
                    URLQueryItem(name: "publisher_id", value: "eq.\(publisherID)"),
                    URLQueryItem(name: "content_fingerprint", value: "eq.\(fingerprint)"),
                    URLQueryItem(name: "is_public", value: "eq.true"),
                    URLQueryItem(name: "limit", value: "1")
                ]

                guard let fallbackURL = fallbackComponents?.url else {
                    throw ExploreError.badResponse
                }

                var fallbackRequest = URLRequest(url: fallbackURL)
                fallbackRequest.httpMethod = "GET"
                applyHeaders(request: &fallbackRequest, config: config)

                let (fallbackData, fallbackResponse) = try await URLSession.shared.data(for: fallbackRequest)
                guard let fallbackHTTP = fallbackResponse as? HTTPURLResponse else {
                    throw ExploreError.badResponse
                }
                guard (200...299).contains(fallbackHTTP.statusCode) else {
                    throw ExploreError.serverError(parseErrorMessage(data: fallbackData, statusCode: fallbackHTTP.statusCode))
                }

                let existingIDs = try decoder.decode([ExistingSnapshotIDOnly].self, from: fallbackData)
                if let first = existingIDs.first {
                    return ExistingSnapshot(id: first.id, shortCode: nil)
                }
                return nil
            }
            throw ExploreError.serverError(message)
        }

        let existing = try decoder.decode([ExistingSnapshot].self, from: data)
        return existing.first
    }

    private func ensureShortCode(config: Config, snapshotID: String, publisherID: String, currentCode: String?) async throws -> String {
        if let currentCode, !currentCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return currentCode
        }

        var attemptsRemaining = 6
        while attemptsRemaining > 0 {
            attemptsRemaining -= 1
            let candidate = generateShortCode(length: 6)

            var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(snapshotID)"),
                URLQueryItem(name: "publisher_id", value: "eq.\(publisherID)")
            ]

            guard let url = components?.url else {
                throw ExploreError.badResponse
            }

            struct ShortCodePatchPayload: Encodable {
                let short_code: String
            }

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            applyHeaders(request: &request, config: config)
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            request.httpBody = try encoder.encode(ShortCodePatchPayload(short_code: candidate))

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ExploreError.badResponse
            }

            if (200...299).contains(httpResponse.statusCode) {
                let updated = try decoder.decode([ExistingSnapshot].self, from: data)
                if let updatedCode = updated.first?.shortCode, !updatedCode.isEmpty {
                    return updatedCode
                }
                return candidate
            }

            let message = parseErrorMessage(data: data, statusCode: httpResponse.statusCode)
            if isMissingShortCodeColumnError(message) {
                return snapshotID
            }
            if httpResponse.statusCode == 409, message.localizedCaseInsensitiveContains("short_code"), attemptsRemaining > 0 {
                continue
            }

            throw ExploreError.serverError(message)
        }

        throw ExploreError.serverError("Could not allocate a unique share code for an existing set.")
    }

    private func publishWithoutShortCode(
        snapshot: SharedStudySet,
        fingerprint: String,
        generatedDescription: String,
        tags: [String],
        publisherID: String,
        config: Config
    ) async throws -> PublishResult {
        let payload = PublishPayloadWithoutShortCode(
            id: snapshot.id,
            title: snapshot.title,
            summary: snapshot.summary,
            shortDescription: generatedDescription,
            mode: snapshot.mode,
            iconId: snapshot.iconId,
            authorName: snapshot.authorName,
            publisherId: publisherID,
            contentFingerprint: fingerprint,
            createdAt: snapshot.createdAt,
            isPublic: true,
            questions: snapshot.questions ?? [],
            flashcards: snapshot.flashcards ?? [],
            tags: tags
        )

        var request = URLRequest(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"))
        request.httpMethod = "POST"
        applyHeaders(request: &request, config: config)
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ExploreError.serverError(parseErrorMessage(data: data, statusCode: httpResponse.statusCode))
        }

        return .published(snapshotID: snapshot.id, shortCode: snapshot.id)
    }

    private func fetchSharedStudySetsWithoutShortCode(limit: Int, tag: String?, config: Config) async throws -> [SharedStudySet] {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,title,summary,short_description,mode,icon_id,author_name,publisher_id,content_fingerprint,created_at,tags,downloads_count,questions_count,flashcards_count"),
            URLQueryItem(name: "order", value: "downloads_count.desc,created_at.desc"),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 100))))
        ]

        if let tag = tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tags", value: "cs.{\(tag)}"))
        }

        var components = URLComponents(url: config.baseURL.appendingPathComponent("rest/v1/shared_study_sets"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw ExploreError.badResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(request: &request, config: config)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExploreError.badResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ExploreError.serverError(parseErrorMessage(data: data, statusCode: httpResponse.statusCode))
        }

        let baseRows = try decoder.decode([SharedStudySetWithoutShortCode].self, from: data)
        return baseRows.map { row in
            SharedStudySet(
                id: row.id,
                shortCode: nil,
                title: row.title,
                summary: row.summary,
                shortDescription: row.shortDescription,
                mode: row.mode,
                iconId: row.iconId,
                authorName: row.authorName,
                publisherId: row.publisherId,
                contentFingerprint: row.contentFingerprint,
                createdAt: row.createdAt,
                questions: nil,
                flashcards: nil,
                tags: row.tags,
                saveCount: row.saveCount,
                questionsCount: row.questionsCount,
                flashcardsCount: row.flashcardsCount
            )
        }
    }

    private func isMissingShortCodeColumnError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("short_code") && normalized.contains("does not exist")
    }

    private func generateShortCode(length: Int) -> String {
        String((0..<max(1, length)).map { _ in
            shortCodeAlphabet.randomElement() ?? "a"
        })
    }

    private func fingerprint(for studySet: StudySet) -> String {
        let title = studySet.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let summary = (studySet.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let questions = studySet.questions
            .map { "\($0.prompt.lowercased())|\($0.answer.lowercased())|\(($0.explanation ?? "").lowercased())|\(($0.options ?? []).joined(separator: "|").lowercased())" }
            .joined(separator: "||")
        let flashcards = studySet.flashcards
            .map { "\($0.front.lowercased())|\($0.back.lowercased())" }
            .joined(separator: "||")
        let canonical = "\(title)#\(summary)#\(studySet.mode)#\(studySet.iconId)#\(questions)#\(flashcards)"

        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private struct ExistingSnapshot: Codable {
    let id: String
    let shortCode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case shortCode = "short_code"
    }
}

private struct ExistingSnapshotIDOnly: Codable {
    let id: String
}

private struct SharedStudySetWithoutShortCode: Codable {
    let id: String
    let title: String
    let summary: String?
    let shortDescription: String?
    let mode: String
    let iconId: String
    let authorName: String?
    let publisherId: String?
    let contentFingerprint: String?
    let createdAt: Date
    let tags: [String]
    let saveCount: Int
    let questionsCount: Int?
    let flashcardsCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case shortDescription = "short_description"
        case mode
        case iconId = "icon_id"
        case authorName = "author_name"
        case publisherId = "publisher_id"
        case contentFingerprint = "content_fingerprint"
        case createdAt = "created_at"
        case tags
        case saveCount = "downloads_count"
        case questionsCount = "questions_count"
        case flashcardsCount = "flashcards_count"
    }
}

private struct PublishPayload: Codable {
    let id: String
    let shortCode: String
    let title: String
    let summary: String?
    let shortDescription: String?
    let mode: String
    let iconId: String
    let authorName: String?
    let publisherId: String
    let contentFingerprint: String
    let createdAt: Date
    let isPublic: Bool
    let questions: [SharedStudyQuestion]
    let flashcards: [SharedStudyFlashcard]
    let tags: [String]

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
        case isPublic = "is_public"
        case questions
        case flashcards
        case tags
    }
}

private struct PublishPayloadWithoutShortCode: Codable {
    let id: String
    let title: String
    let summary: String?
    let shortDescription: String?
    let mode: String
    let iconId: String
    let authorName: String?
    let publisherId: String
    let contentFingerprint: String
    let createdAt: Date
    let isPublic: Bool
    let questions: [SharedStudyQuestion]
    let flashcards: [SharedStudyFlashcard]
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case shortDescription = "short_description"
        case mode
        case iconId = "icon_id"
        case authorName = "author_name"
        case publisherId = "publisher_id"
        case contentFingerprint = "content_fingerprint"
        case createdAt = "created_at"
        case isPublic = "is_public"
        case questions
        case flashcards
        case tags
    }
}
