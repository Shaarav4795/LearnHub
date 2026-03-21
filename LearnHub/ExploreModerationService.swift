import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ModerationDecision: Sendable {
    let approved: Bool
    let reason: String
    /// AI-generated subject tags (e.g. ["Mathematics", "Algebra"]). Empty if moderation failed.
    let tags: [String]
    /// AI-generated Explore description normalized to exactly 15 words.
    let generatedDescription: String
}

actor ExploreModerationService {
    static let shared = ExploreModerationService()

    private let blockedPatterns: [String] = [
        "\\bkill\\b", "\\bmurder\\b", "\\bassassinat", "\\bhow to kill\\b", "\\bmake a bomb\\b",
        "\\bshoot\\b", "\\bstab\\b", "\\bpoison\\b", "\\bterror", "\\bsuicide\\b",
        "\\bself[- ]?harm\\b", "\\bgenocide\\b", "\\brape\\b",
        "k[^a-zA-Z0-9]?ll", "m[^a-zA-Z0-9]?rder"
    ]

    private struct GroqModerationRequest: Codable {
        let model: String
        let messages: [Message]

        struct Message: Codable {
            let role: String
            let content: String
        }
    }

    private struct GroqModerationResponse: Codable {
        let choices: [Choice]

        struct Choice: Codable {
            let message: Message
        }

        struct Message: Codable {
            let content: String
        }
    }

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    // ─────────────────────────────────────────────────────────────────────
    // SYSTEM PROMPT — tag format (matches AIService.swift conventions)
    // ─────────────────────────────────────────────────────────────────────
    private let systemPrompt = """
    You are a strict moderation checker for public educational content.

    Respond using ONLY the following exact tag format — no extra text, no JSON, no markdown:

    [APPROVED]
    true or false
    [REASON]
    One sentence explaining your decision.
    [TAGS]
    Comma-separated list of 2–5 broad subject tags (e.g. Mathematics, Biology, History).
    [DESCRIPTION]
    Exactly 15 words describing this study set for the Explore feed. No hashtags.
    [END]

    Rules:
    - Reject hateful, sexual, violent, self-harm, extremist, illegal, explicit, harassment, or dangerous content.
    - Reject privacy-invasive content or instructions to cheat exams.
    - [TAGS] should reflect the educational subject(s) of the content, not the approval status.
    - Keep [REASON] brief and concrete (one sentence max).
    - [DESCRIPTION] must be exactly 15 words.
    """

    func moderate(studySet: StudySet) async -> ModerationDecision {
        if let rejected = localSafetyRejectionIfNeeded(for: studySet) {
            return rejected
        }

        if let groqDecision = await moderateWithGroqIfPossible(studySet: studySet) {
            return groqDecision
        }

        if let appleDecision = await moderateWithAppleIntelligenceIfPossible(studySet: studySet) {
            return appleDecision
        }

        return ModerationDecision(
            approved: false,
            reason: "Content safety check is unavailable. Add a Groq key or enable Apple Intelligence to publish.",
            tags: [],
            generatedDescription: fallbackDescription(for: studySet.title)
        )
    }

    private func moderateWithGroqIfPossible(studySet: StudySet) async -> ModerationDecision? {
        let key = await ModelSettings.groqApiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        let userPrompt = moderationInput(for: studySet)
        print("[ExploreModerationService] Sending prompt to Groq:\n\(userPrompt)")

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            let payload = GroqModerationRequest(
                model: "openai/gpt-oss-safeguard-20b",
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: userPrompt)
                ]
            )

            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return ModerationDecision(
                    approved: false,
                    reason: "Moderation request failed. Please try again.",
                    tags: [],
                    generatedDescription: fallbackDescription(for: studySet.title)
                )
            }

            let decoded = try JSONDecoder().decode(GroqModerationResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                return ModerationDecision(
                    approved: false,
                    reason: "Moderation response was empty.",
                    tags: [],
                    generatedDescription: fallbackDescription(for: studySet.title)
                )
            }

            print("[ExploreModerationService] Full AI response (Groq):\n\(content)")
            let decision = parseDecision(from: content, studySetTitle: studySet.title)
            logTaggedResponse(source: "Groq", decision: decision)
            return decision
        } catch {
            return ModerationDecision(
                approved: false,
                reason: "Moderation failed: \(error.localizedDescription)",
                tags: [],
                generatedDescription: fallbackDescription(for: studySet.title)
            )
        }
    }

    private func moderateWithAppleIntelligenceIfPossible(studySet: StudySet) async -> ModerationDecision? {
        #if canImport(FoundationModels)
        guard ModelSettings.appleIntelligenceAvailable else { return nil }

        if #available(iOS 26.0, macOS 26.0, *) {
            let userPrompt = moderationInput(for: studySet)

            do {
                let session = LanguageModelSession(instructions: systemPrompt)
                let response = try await session.respond(to: userPrompt)
                print("[ExploreModerationService] Full AI response (Apple Intelligence):\n\(response.content)")
                let decision = parseDecision(from: response.content, studySetTitle: studySet.title)
                logTaggedResponse(source: "AppleIntelligence", decision: decision)
                return decision
            } catch {
                return ModerationDecision(
                    approved: false,
                    reason: "Apple Intelligence moderation failed: \(error.localizedDescription)",
                    tags: [],
                    generatedDescription: fallbackDescription(for: studySet.title)
                )
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    // ─────────────────────────────────────────────────────────────────────
    // PARSER — reads the tag-format response
    // ─────────────────────────────────────────────────────────────────────
    private func parseDecision(from content: String, studySetTitle: String) -> ModerationDecision {
        let approved = extractTag("APPROVED", from: content)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) == "true"

        let reason = extractTag("REASON", from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let tagsRaw = extractTag("TAGS", from: content)
        let tags: [String] = tagsRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let rawDescription = extractTag("DESCRIPTION", from: content)
        let generatedDescription = normalizedDescription(rawDescription, title: studySetTitle, tags: tags)

        return ModerationDecision(
            approved: approved,
            reason: reason.isEmpty ? "No reason provided." : reason,
            tags: tags,
            generatedDescription: generatedDescription
        )
    }

    private func logTaggedResponse(source: String, decision: ModerationDecision) {
        let tagLine = decision.tags.isEmpty ? "None" : decision.tags.joined(separator: ", ")
        print("""
        [ExploreModerationService][\(source)]
        [APPROVED]
        \(decision.approved ? "true" : "false")
        [REASON]
        \(decision.reason)
        [TAGS]
        \(tagLine)
        [DESCRIPTION]
        \(decision.generatedDescription)
        [END]
        """)
    }

    /// Extracts the text between `[TAG_NAME]` and the next `[` or end of string.
    private func extractTag(_ tag: String, from text: String) -> String {
        let open = "[\(tag)]"
        guard let startRange = text.range(of: open) else { return "" }
        let afterOpen = text[startRange.upperBound...]

        // End at the next [TAG] marker or end of string
        if let endRange = afterOpen.range(of: "[", options: .literal) {
            return String(afterOpen[afterOpen.startIndex..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(afterOpen).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func moderationInput(for set: StudySet) -> String {
        let questionPreview = (set.questions ?? []).prefix(8).map { "Q: \($0.prompt) | A: \($0.answer)" }.joined(separator: "\n")
        let flashcardPreview = (set.flashcards ?? []).prefix(8).map { "Front: \($0.front) | Back: \($0.back)" }.joined(separator: "\n")

        return """
        Title: \(set.title)
        Summary: \(set.summary ?? "")

        Questions:
        \(questionPreview)

        Flashcards:
        \(flashcardPreview)
        """
    }

    private func fallbackDescription(for title: String) -> String {
        normalizedDescription("", title: title, tags: [])
    }

    private func localSafetyRejectionIfNeeded(for set: StudySet) -> ModerationDecision? {
        let searchableParts = [
            set.title,
            set.summary ?? "",
            (set.questions ?? []).map(\.prompt).joined(separator: "\n"),
            (set.questions ?? []).map(\.answer).joined(separator: "\n"),
            (set.flashcards ?? []).map(\.front).joined(separator: "\n"),
            (set.flashcards ?? []).map(\.back).joined(separator: "\n")
        ]
        let corpus = searchableParts.joined(separator: "\n").lowercased()

        for pattern in blockedPatterns {
            if corpus.range(of: pattern, options: .regularExpression) != nil {
                let decision = ModerationDecision(
                    approved: false,
                    reason: "Blocked by local safety filter due to unsafe or violent content.",
                    tags: [],
                    generatedDescription: fallbackDescription(for: set.title)
                )
                logTaggedResponse(source: "LocalGuard", decision: decision)
                return decision
            }
        }

        return nil
    }

    private func normalizedDescription(_ text: String, title: String, tags: [String]) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let seed: String
        let inputWordsCount = cleaned
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count

        if cleaned.isEmpty || inputWordsCount > 28 || cleaned.contains("##") {
            seed = synthesizedDescriptionSeed(title: title, tags: tags)
        } else {
            seed = cleaned
        }

        let rawWords = seed
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }

        let fallbackWords = [
            "study", "set", "for", "focused", "practice", "clear", "explanations", "quick",
            "revision", "and", "confident", "learning", "for", "every", "student"
        ]

        var words = rawWords
        if words.count < 15 {
            words.append(contentsOf: fallbackWords)
        }

        return words.prefix(15).joined(separator: " ")
    }

    private func synthesizedDescriptionSeed(title: String, tags: [String]) -> String {
        let firstTag = tags.first ?? "study"
        return "Focused \(firstTag) practice from \(title) with concise questions flashcards and exam-ready revision support for learners"
    }
}
