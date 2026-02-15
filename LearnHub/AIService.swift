import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIError: LocalizedError {
    case generationFailed
    case invalidResponse
    case parsingFailed
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .generationFailed:
            return "The AI failed to generate a response. Please try again."
        case .invalidResponse:
            return "The AI returned an invalid response format."
        case .parsingFailed:
            return "Failed to parse the AI response into the required format."
        case .apiError(let message):
            return "AI Error: \(message)"
        }
    }
}

actor AIService {
    static let shared = AIService()

    /// Formats an error for display to the user, ensuring error codes are included.
    static func formatError(_ error: Error) -> String {
        if let aiError = error as? AIError {
            return aiError.localizedDescription
        }
        
        let nsError = error as NSError
        let code = nsError.code
        let description = nsError.localizedDescription
        
        if code != 0 {
            return "\(description) (Error Code: \(code))"
        } else {
            return description
        }
    }

    private enum Provider {
        case appleIntelligence
        case groq
    }

    private struct ProviderSelection {
        let provider: Provider
        let fallbackNotice: String?
    }

    private var fallbackNotice: String?
    
    // Helper structs for JSON parsing
    private struct QuestionResponse: Codable, Sendable {
        let question: String
        let answer: String
        let options: [String]
        let explanation: String?
    }

    private struct FlashcardResponse: Codable, Sendable {
        let front: String
        let back: String
    }

    // Groq API Structs
    private struct GroqRequest: Codable, Sendable {
        let model: String
        let messages: [Message]
        
        struct Message: Codable, Sendable {
            let role: String
            let content: String
        }
    }

    private struct GroqResponse: Codable, Sendable {
        let choices: [Choice]
        
        struct Choice: Codable, Sendable {
            let message: Message
        }
        
        struct Message: Codable, Sendable {
            let content: String
        }
    }

    private struct GroqErrorResponse: Codable, Sendable {
        let error: ErrorDetails
        
        struct ErrorDetails: Codable, Sendable {
            let message: String
            let type: String?
            let code: String?
        }
    }
    
    // Groq Multimodal (Vision) API Structs
    private struct GroqMultimodalRequest: Codable, Sendable {
        let model: String
        let messages: [MultimodalMessage]
        
        struct MultimodalMessage: Codable, Sendable {
            let role: String
            let content: [ContentPart]
        }
        
        struct ContentPart: Codable, Sendable {
            let type: String  // "text" or "image_url"
            let text: String?
            let image_url: ImageURL?
            
            init(text: String) {
                self.type = "text"
                self.text = text
                self.image_url = nil
            }
            
            init(imageURL: String) {
                self.type = "image_url"
                self.text = nil
                self.image_url = ImageURL(url: imageURL)
            }
        }
        
        struct ImageURL: Codable, Sendable {
            let url: String  // "data:image/jpeg;base64,..."
        }
    }
    
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    
    private init() {}

    // Small randomised delay to reduce rate-limiting (0.5 - 1.0 seconds)
    private func applyRateLimitDelay() async {
        // Longer delay to avoid hitting Groq's rate limits
        let millis = UInt64(Int.random(in: 500...1500))
        do {
            try await Task.sleep(nanoseconds: millis * 1_000_000)
        } catch {
            // Ignored: if the task is cancelled, proceed without delay
        }
    }
    
    private func performRequest(systemPrompt: String, userPrompt: String) async throws -> String {
        let selection = await selectProvider()

        switch selection.provider {
        case .appleIntelligence:
            do {
                return try await runAppleIntelligence(systemPrompt: systemPrompt, userPrompt: userPrompt)
            } catch {
                let reason = "Apple Intelligence unavailable (\(error.localizedDescription)). Falling back to Groq (BYOK)."
                setFallbackNoticeIfNeeded(selection.fallbackNotice ?? reason)
                return try await runGroq(systemPrompt: systemPrompt, userPrompt: userPrompt)
            }
        case .groq:
            setFallbackNoticeIfNeeded(selection.fallbackNotice)
            return try await runGroq(systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }

    /// Performs a request with automatic retry on parsing failures.
    /// If parsing fails, retries with the same provider.
    private func performRequestWithParsingRetry(systemPrompt: String, userPrompt: String) async throws -> String {
        let preference = await ModelSettings.preference()
        
        do {
            return try await performRequest(systemPrompt: systemPrompt, userPrompt: userPrompt)
        } catch let error as AIError {
            // Only retry on parsing failures
            guard case .parsingFailed = error else {
                throw error
            }
            
            print("AI Generation - Parsing failed, retrying with same provider...")
            
            // Retry with the same provider
            switch preference {
            case .automatic:
                // Determine which provider was used and retry with it
                if Self.appleIntelligenceAvailable {
                    do {
                        print("AI - Retrying with Apple Intelligence...")
                        return try await runAppleIntelligence(systemPrompt: systemPrompt, userPrompt: userPrompt)
                    } catch {
                        print("AI - Apple Intelligence retry failed: \(error)")
                        throw error
                    }
                } else {
                    do {
                        print("AI - Retrying with Groq...")
                        return try await runGroq(systemPrompt: systemPrompt, userPrompt: userPrompt)
                    } catch {
                        print("AI - Groq retry failed: \(error)")
                        throw error
                    }
                }
            case .groqOnly:
                do {
                    print("AI - Retrying with Groq...")
                    return try await runGroq(systemPrompt: systemPrompt, userPrompt: userPrompt)
                } catch {
                    print("AI - Groq retry failed: \(error)")
                    throw error
                }
            }
        } catch {
            throw error
        }
    }

    private func runGroq(systemPrompt: String, userPrompt: String) async throws -> String {
        let apiKey = try await groqApiKey()
        let primaryModel = await ModelSettings.groqModel()
        let modelsToTry = getTextModelFallbacks(primaryModel: primaryModel)
        
        var lastError: Error?
        
        for model in modelsToTry {
            do {
                let result = try await attemptGroqRequest(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    model: model,
                    apiKey: apiKey
                )
                if model != primaryModel {
                    print("AI (Groq) - Fell back to model: \(model)")
                }
                return result
            } catch {
                // Capture any per-model error, save it and continue to the next fallback model.
                lastError = error
                print("AI (Groq) - Model \(model) failed with error: \(error). Trying next fallback...")
                continue
            }
        }
        
        // If we get here, all models failed with rate limits
        if let error = lastError {
            throw error
        }
        throw AIError.generationFailed
    }
    
    private func attemptGroqRequest(
        systemPrompt: String,
        userPrompt: String,
        model: String,
        apiKey: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = GroqRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: userPrompt)
            ]
        )

        request.httpBody = try JSONEncoder().encode(payload)

        await applyRateLimitDelay()

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.generationFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var errorDetail = "Status code: \(httpResponse.statusCode)"
            if let errorResponse = try? JSONDecoder().decode(GroqErrorResponse.self, from: data) {
                errorDetail = "\(errorResponse.error.message) (Code: \(errorResponse.error.code ?? "\(httpResponse.statusCode)"))"
            } else if let errorText = String(data: data, encoding: .utf8) {
                print("Groq API Error: \(errorText)")
            }
            throw AIError.apiError(errorDetail)
        }

        let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        guard let content = decodedResponse.choices.first?.message.content else {
            throw AIError.invalidResponse
        }

        print("AI (Groq) response:\n\(content)\n--- end response ---")

        return content
    }
    
    private func getTextModelFallbacks(primaryModel: String) -> [String] {
        // Define fallback chain for text models
        // Default primary is now openai/gpt-oss-120b -> fallback to openai/gpt-oss-20b -> llama-3.3-70b-versatile
        let fallbackChain: [String: [String]] = [
            "openai/gpt-oss-120b": ["openai/gpt-oss-20b", "llama-3.3-70b-versatile"],
            "openai/gpt-oss-20b": ["llama-3.3-70b-versatile"],
            "llama-3.3-70b-versatile": []
        ]
        
        var modelsToTry = [primaryModel]
        if let fallbacks = fallbackChain[primaryModel] {
            modelsToTry.append(contentsOf: fallbacks)
        }
        return modelsToTry
    }

    private func runAppleIntelligence(systemPrompt: String, userPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: systemPrompt)
            let response = try await session.respond(to: userPrompt)
            print("AI (Apple Intelligence) response:\n\(response.content)\n--- end response ---")
            return response.content
        } else {
            throw AIError.apiError("Apple Intelligence requires iOS 26 or later.")
        }
        #else
        throw AIError.apiError("FoundationModels framework is unavailable in this SDK.")
        #endif
    }

    private func selectProvider() async -> ProviderSelection {
        let preference = await ModelSettings.preference()

        switch preference {
        case .groqOnly:
            return ProviderSelection(provider: .groq, fallbackNotice: nil)
        case .automatic:
            if Self.appleIntelligenceAvailable {
                return ProviderSelection(provider: .appleIntelligence, fallbackNotice: nil)
            }
            let notice = "Apple Intelligence requires iOS 26+ with supported hardware and enabled in Settings. Falling back to Groq (BYOK)."
            return ProviderSelection(provider: .groq, fallbackNotice: notice)
        }
    }

    private func groqApiKey() async throws -> String {
        let key = await ModelSettings.groqApiKey()
        guard key.isEmpty == false else {
            throw AIError.apiError("Missing Groq API key. Add it in Model Settings.")
        }
        return key
    }

    private func setFallbackNoticeIfNeeded(_ notice: String?) {
        guard fallbackNotice == nil else { return }
        guard let notice = notice else { return }
        fallbackNotice = notice
    }

    func popFallbackNotice() -> String? {
        let note = fallbackNotice
        fallbackNotice = nil
        return note
    }

    func clearFallbackNotice() {
        fallbackNotice = nil
    }

    func previewFallbackNoticeForCurrentPreference() async -> String? {
        let selection = await selectProvider()
        return selection.fallbackNotice
    }

    nonisolated static var appleIntelligenceAvailable: Bool {
        ModelSettings.appleIntelligenceAvailable
    }
    
    enum SummaryStyle: String, CaseIterable, Identifiable {
        case paragraph = "Paragraph"
        case bulletPoints = "Bullet Points"
        
        var id: String { self.rawValue }
    }
    
    enum SummaryDifficulty: String, CaseIterable, Identifiable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        
        var id: String { self.rawValue }
    }

    enum RelativeDifficulty: String, CaseIterable, Identifiable {
        case easier = "Easier"
        case same = "Same"
        case harder = "Harder"
        
        var id: String { self.rawValue }
        
        var guidance: String {
            switch self {
            case .easier:
                return "Simplify language and focus on foundational, one-step ideas. Avoid edge cases."
            case .same:
                return "Match the current difficulty and tone of the learner's existing material."
            case .harder:
                return "Increase complexity with multi-step reasoning, trickier distractors, and deeper concepts."
            }
        }
    }
    
    private func cleanJSON(_ jsonString: String) -> String {
        // Deprecated: No longer used with custom text format parsing
        return jsonString
    }

    private func normalizeWhitespace(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeTags(_ text: String) -> String {
        let tags = ["[QUESTION]", "[ANSWER]", "[OPTION]", "[EXPLANATION]", "[FRONT]", "[BACK]", "[TITLE]", "[DESCRIPTION]", "[CATEGORY]", "[DIFFICULTY]", "[TIME]", "[ICON]", "[END]"]
        let closing = ["[/QUESTION]", "[/ANSWER]", "[/OPTION]", "[/EXPLANATION]", "[/FRONT]", "[/BACK]", "[/TITLE]", "[/DESCRIPTION]", "[/CATEGORY]", "[/DIFFICULTY]", "[/TIME]", "[/ICON]", "[/END]"]

        var result = text
        for tag in tags {
            result = result.replacingOccurrences(of: tag, with: "\n\(tag)\n")
        }
        for close in closing {
            result = result.replacingOccurrences(of: close, with: "\n")
        }
        return result
    }

    private func cleanMath(_ text: String) -> String {
        var result = text
        // Replace \[ ... \] with $$ ... $$
        result = result.replacingOccurrences(of: "\\[", with: "$$")
        result = result.replacingOccurrences(of: "\\]", with: "$$")
        // Replace \( ... \) with $ ... $
        result = result.replacingOccurrences(of: "\\(", with: "$")
        result = result.replacingOccurrences(of: "\\)", with: "$")
        return result
    }

    private func removeAngleBracketPlaceholders(_ text: String) -> String {
        // Remove angle bracket placeholders like <Question text>, <Correct answer text>, etc.
        // Pattern: < followed by any text ending in >
        var result = text
        result = result.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionsContainAnswer(_ options: [String], answer: String) -> Bool {
        let normAnswer = normalizeWhitespace(answer)
        return options.contains { normalizeWhitespace($0) == normAnswer }
    }

    func generateSummary(from text: String, style: SummaryStyle = .paragraph, wordCount: Int = 150, difficulty: SummaryDifficulty = .intermediate) async throws -> String {
        do {
            let systemPrompt = "You are a concise study assistant. Produce clean, well-formatted output that follows instructions exactly. Do not add headings, labels, bullets, or extra commentary."
            let styleInstruction: String
            if style == .bulletPoints {
                styleInstruction = "FORMAT AS BULLETS ONLY. Each bullet must be its own line and start with '- ' exactly. No numbering. No paragraph text. Do NOT break bullets across multiple lines. Example exactly:\n- Key idea one\n- Key idea two\n- Key idea three"
            } else {
                styleInstruction = "FORMAT AS ONE SINGLE PARAGRAPH (4-7 sentences). ABSOLUTELY NO BULLET POINTS. NO LISTS. NO HEADINGS. NO EXTRA SECTIONS. Just one continuous block of text."
            }
            let difficultyInstruction: String
            switch difficulty {
            case .beginner:
                difficultyInstruction = "Use simple language suitable for a beginner. Avoid jargon where possible."
            case .intermediate:
                difficultyInstruction = "Use standard language suitable for an intermediate learner."
            case .advanced:
                difficultyInstruction = "Use advanced, academic language suitable for an expert."
            }
            
            let userPrompt = """
            Summarise the following text. Follow formatting instructions EXACTLY. Do NOT add headings or labels. Keep it tight and avoid filler.
            \(styleInstruction)
            Target length: aim for \(max(80, wordCount - 30))-\(wordCount + 30) words (soft target, stay concise).
            Difficulty level: \(difficulty.rawValue) (\(difficultyInstruction)).
            
            MATH FORMATTING RULES (follow exactly):
            - Wrap ALL math expressions in single dollar signs: $...$
            - Use \\frac{a}{b} for fractions, NOT a/b for complex fractions
            - Use \\sqrt{x} or \\sqrt[n]{x} for roots
            - Use \\sum_{i=1}^{n}, \\int_{a}^{b}, \\prod for summation, integrals, products
            - Use ^{} for superscripts and _{} for subscripts (e.g., $x^{2}$, $a_{n}$)
            - Use \\left( and \\right) for auto-sizing parentheses
            - Use \\cdot for multiplication, \\times for cross product
            - Greek letters: \\alpha, \\beta, \\pi, \\theta, \\Delta, etc.
            - Examples: $\\frac{-b \\pm \\sqrt{b^{2} - 4ac}}{2a}$, $\\int_{0}^{\\infty} e^{-x^{2}} dx$
            
            Text:
            \(text)
            """
            
            return try await performRequest(systemPrompt: systemPrompt, userPrompt: userPrompt)
        } catch {
            print("AI Generation failed: \(error)")
            throw error
        }
    }
    
    func generateQuestions(from text: String, count: Int, relativeDifficulty: RelativeDifficulty? = nil) async throws -> [(question: String, answer: String, options: [String], explanation: String?)] {
        do {
            let systemPrompt = "You are a precise quiz generator. Output ONLY the requested format. No conversational text."
            let difficultyAdjustment: String
            if let relativeDifficulty {
                difficultyAdjustment = """
                Difficulty adjustment: \(relativeDifficulty.rawValue). \(relativeDifficulty.guidance)
                """
            } else {
                difficultyAdjustment = "Difficulty: Match the current set's complexity."
            }
            let userPrompt = """
            Generate \(count) multiple choice study questions based on the text below.

            \(difficultyAdjustment)
            
            STRICT OUTPUT FORMAT (Tag-based):
            
            [QUESTION]
            Question text
            [ANSWER]
            Correct answer text
            [OPTION]
            Correct answer text
            [OPTION]
            Distractor 1
            [OPTION]
            Distractor 2
            [OPTION]
            Distractor 3
            [EXPLANATION]
            Explanation
            [END]
            
            RULES:
            1. Use [QUESTION], [ANSWER], [OPTION], [EXPLANATION], [END] tags exactly as shown.
            2. Put content on the lines following the tags. Do NOT wrap content in < > brackets.
            3. Provide exactly 4 [OPTION] tags. One MUST match [ANSWER] exactly.
            4. MATH: Use LaTeX with single dollar signs ($...$) for ALL math.
               - CORRECT: $x^2 + 2x$
               - WRONG: \\[ x^2 + 2x \\]
               - WRONG: [ x^2 + 2x ]
               - WRONG: \\( x^2 + 2x \\)
            5. Do not use markdown code blocks (```).
            6. Ensure there are exactly 4 options for every question.
            
            Text:
            \(text)
            """
            
            let rawContent = try await performRequestWithParsingRetry(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let content = normalizeTags(rawContent)
            
            var questions: [(String, String, [String], String?)] = []
            let blocks = content.components(separatedBy: "[END]")
            
            for block in blocks {
                let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedBlock.isEmpty else { continue }
                
                var question = ""
                var answer = ""
                var options: [String] = []
                var explanation: String? = nil
                
                let lines = trimmedBlock.components(separatedBy: .newlines)
                var currentTag = ""
                var currentText = ""
                
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedLine == "[QUESTION]" || trimmedLine == "[ANSWER]" || trimmedLine == "[OPTION]" || trimmedLine == "[EXPLANATION]" {
                        
                        // Save previous tag content
                        if !currentTag.isEmpty {
                            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                switch currentTag {
                                case "[QUESTION]": question = removeAngleBracketPlaceholders(cleanMath(value))
                                case "[ANSWER]": answer = removeAngleBracketPlaceholders(cleanMath(value))
                                case "[OPTION]": options.append(removeAngleBracketPlaceholders(cleanMath(value)))
                                case "[EXPLANATION]": explanation = removeAngleBracketPlaceholders(cleanMath(value))
                                default: break
                                }
                            }
                        }
                        
                        currentTag = trimmedLine
                        currentText = ""
                    } else {
                        currentText += line + "\n"
                    }
                }
                
                // Save last tag content
                if !currentTag.isEmpty {
                    let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        switch currentTag {
                        case "[QUESTION]": question = removeAngleBracketPlaceholders(cleanMath(value))
                        case "[ANSWER]": answer = removeAngleBracketPlaceholders(cleanMath(value))
                        case "[OPTION]": options.append(removeAngleBracketPlaceholders(cleanMath(value)))
                        case "[EXPLANATION]": explanation = removeAngleBracketPlaceholders(cleanMath(value))
                        default: break
                        }
                    }
                }
                
                if !question.isEmpty && !answer.isEmpty {
                    // Fix options if needed
                    if !optionsContainAnswer(options, answer: answer) {
                        // Insert answer at the beginning instead of overwriting
                        options.insert(answer, at: 0)
                    }
                    
                    // Ensure 4 options
                    while options.count < 4 {
                        options.append("Option \(options.count + 1)")
                    }
                    if options.count > 4 {
                        options = Array(options.prefix(4))
                    }
                    
                    questions.append((question, answer, options.shuffled(), explanation))
                }
            }
            
            if questions.isEmpty { throw AIError.parsingFailed }
            return questions
            
        } catch {
            print("AI Generation failed: \(error)")
            throw error
        }
    }
    
    func generateFlashcards(from text: String, count: Int, relativeDifficulty: RelativeDifficulty? = nil) async throws -> [(front: String, back: String)] {
        do {
            let systemPrompt = "You are a precise flashcard generator. Follow the exact tag format. No markdown, no numbering, no extra prose. Front and back must be plain text."
            let difficultyAdjustment: String
            if let relativeDifficulty {
                difficultyAdjustment = """
                Difficulty adjustment: \(relativeDifficulty.rawValue). \(relativeDifficulty.guidance)
                """
            } else {
                difficultyAdjustment = "Difficulty: Match the current set's complexity."
            }
            let userPrompt = """
            Generate \(count) flashcards (like in Quizlet) based on the following text.

            Use the following EXACT format for each flashcard (no extra blank lines between tags):

            [FRONT]
            Term text
            [BACK]
            Definition text
            [END]

            IMPORTANT - FOLLOW ALL:
            1) Do NOT use JSON or markdown.
            2) Do NOT use headings (#, ##) or bold/italics. No numbering of cards.
            3) Keep the 'front' very short (3-9 words) and the 'back' concise (under 20 words).
            4) Keep EXACT tags as shown. No extra tags or bullets.
            5) Produce exactly \(count) flashcards.

            \(difficultyAdjustment)

            GOOD EXAMPLE (copy structure, change content):
            [FRONT]
            Factorising purpose
            [BACK]
            Reveal common factors to simplify.
            [END]
            
            MATH FORMATTING RULES (follow exactly):
            - Wrap ALL math expressions in single dollar signs: $...$
            - Use \\frac{a}{b} for fractions, NOT a/b for complex fractions
            - Use \\sqrt{x} or \\sqrt[n]{x} for roots
            - Use \\sum_{i=1}^{n}, \\int_{a}^{b}, \\prod for summation, integrals, products
            - Use ^{} for superscripts and _{} for subscripts (e.g., $x^{2}$, $a_{n}$)
            - Use \\left( and \\right) for auto-sizing parentheses
            - Use \\cdot for multiplication, \\times for cross product
            - Greek letters: \\alpha, \\beta, \\pi, \\theta, \\Delta, etc.
            - Examples: $\\frac{-b \\pm \\sqrt{b^{2} - 4ac}}{2a}$, $\\int_{0}^{\\infty} e^{-x^{2}} dx$
            
            Text:
            \(text)
            """
            
            let rawContent = try await performRequestWithParsingRetry(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let content = normalizeTags(rawContent)
            
            var cards: [(String, String)] = []
            let blocks = content.components(separatedBy: "[END]")
            
            for block in blocks {
                let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedBlock.isEmpty else { continue }
                
                var front = ""
                var back = ""
                
                let lines = trimmedBlock.components(separatedBy: .newlines)
                var currentTag = ""
                var currentText = ""
                
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedLine == "[FRONT]" || trimmedLine == "[BACK]" {
                        
                        // Save previous tag content
                        if !currentTag.isEmpty {
                            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                switch currentTag {
                                case "[FRONT]": front = value
                                case "[BACK]": back = value
                                default: break
                                }
                                // If we've gathered both front and back within the same block,
                                // append the card immediately so multiple pairs in one block
                                // (when AI omitted [END] separators) are preserved.
                                if !front.isEmpty && !back.isEmpty {
                                    cards.append((front, back))
                                    front = ""
                                    back = ""
                                }
                            }
                        }
                        
                        currentTag = trimmedLine
                        currentText = ""
                    } else {
                        currentText += line + "\n"
                    }
                }
                
                // Save last tag content
                if !currentTag.isEmpty {
                    let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        switch currentTag {
                        case "[FRONT]": front = value
                        case "[BACK]": back = value
                        default: break
                        }
                    }
                }
                
                if !front.isEmpty && !back.isEmpty {
                    cards.append((front, back))
                }
            }
            
            if cards.isEmpty { throw AIError.parsingFailed }
            return cards
            
        } catch {
            print("AI Generation failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Topic-Based Generation (Learn a new topic)
    
    /// Generates a learning guide/tutorial for a topic the user wants to learn
    func generateTopicGuide(topic: String, style: SummaryStyle = .paragraph, wordCount: Int = 300, difficulty: SummaryDifficulty = .intermediate) async throws -> String {
        do {
            let systemPrompt = "You are a concise study assistant. Produce clean, well-formatted output that follows instructions exactly. Do not add headings, labels, bullets, or extra commentary."
            let styleInstruction: String
            if style == .bulletPoints {
                styleInstruction = "FORMAT AS BULLETS ONLY. Each bullet must be its own line and start with '- ' exactly. No numbering. No paragraph text. Do NOT break bullets across multiple lines. Example exactly:\n- Key idea one\n- Key idea two\n- Key idea three"
            } else {
                styleInstruction = "FORMAT AS PROSE (PARAGRAPHS). Use standard paragraphs to structure the content. ABSOLUTELY NO BULLET POINTS. NO LISTS. Write in full sentences."
            }
            let difficultyInstruction: String
            switch difficulty {
            case .beginner:
                difficultyInstruction = "Use simple language suitable for a beginner. Avoid jargon where possible. Explain like the user is 5."
            case .intermediate:
                difficultyInstruction = "Use standard language suitable for an intermediate learner."
            case .advanced:
                difficultyInstruction = "Use advanced, academic language suitable for an expert."
            }
            
            let userPrompt = """
            Create a comprehensive learning guide about: \(topic)
            Follow formatting instructions EXACTLY. Do NOT add headings or labels. Keep it tight and avoid filler.
            \(styleInstruction)
            Target length: aim for \(max(80, wordCount - 30))-\(wordCount + 30) words (soft target, stay concise).
            Difficulty level: \(difficulty.rawValue) (\(difficultyInstruction)).
            
            Structure your guide to include these sections in order (use plain text paragraphs; do not use bullet points):
            1. A brief introduction to the topic
            2. Key concepts and fundamentals
            3. Step-by-step instructions or explanations (if applicable)
            4. Common mistakes to avoid or tips for success
            5. How to practice or apply this knowledge
            
            MATH FORMATTING RULES (follow exactly):
            - Wrap ALL math expressions in single dollar signs: $...$
            - Use \\frac{a}{b} for fractions, NOT a/b for complex fractions
            - Use \\sqrt{x} or \\sqrt[n]{x} for roots
            - Use \\sum_{i=1}^{n}, \\int_{a}^{b}, \\prod for summation, integrals, products
            - Use ^{} for superscripts and _{} for subscripts (e.g., $x^{2}$, $a_{n}$)
            - Use \\left( and \\right) for auto-sizing parentheses
            - Use \\cdot for multiplication, \\times for cross product
            - Greek letters: \\alpha, \\beta, \\pi, \\theta, \\Delta, etc.
            - Examples: $\\frac{-b \\pm \\sqrt{b^{2} - 4ac}}{2a}$, $\\int_{0}^{\\infty} e^{-x^{2}} dx$
            """
            
            return try await performRequest(systemPrompt: systemPrompt, userPrompt: userPrompt)
        } catch {
            print("AI Generation failed: \(error)")
            throw error
        }
    }
    
    /// Generates quiz questions about a topic for learning purposes
    func generateTopicQuestions(topic: String, count: Int, difficulty: SummaryDifficulty = .intermediate) async throws -> [(question: String, answer: String, options: [String], explanation: String?)] {
        do {
            let systemPrompt = "You are a precise quiz generator. Output ONLY the requested format. No conversational text."
            let difficultyInstruction: String
            switch difficulty {
            case .beginner:
                difficultyInstruction = "Create basic questions testing fundamental understanding."
            case .intermediate:
                difficultyInstruction = "Create moderately challenging questions testing practical application."
            case .advanced:
                difficultyInstruction = "Create challenging questions testing deep understanding and edge cases."
            }
            
            let userPrompt = """
            Generate \(count) multiple choice study questions about: \(topic)
            
            Difficulty: \(difficulty.rawValue) - \(difficultyInstruction)
            
            STRICT OUTPUT FORMAT (Tag-based):
            
            [QUESTION]
            Question text
            [ANSWER]
            Correct answer text
            [OPTION]
            Correct answer text
            [OPTION]
            Distractor 1
            [OPTION]
            Distractor 2
            [OPTION]
            Distractor 3
            [EXPLANATION]
            Explanation
            [END]
            
            RULES:
            1. Use [QUESTION], [ANSWER], [OPTION], [EXPLANATION], [END] tags exactly as shown.
            2. Put content on the lines following the tags. Do NOT wrap content in < > brackets.
            3. Provide exactly 4 [OPTION] tags. One MUST match [ANSWER] exactly.
            4. MATH: Use LaTeX with single dollar signs ($...$) for ALL math.
               - CORRECT: $x^2 + 2x$
               - WRONG: \\[ x^2 + 2x \\]
               - WRONG: [ x^2 + 2x ]
               - WRONG: \\( x^2 + 2x \\)
            5. Do not use markdown code blocks (```).
            6. Ensure there are exactly 4 options for every question.
            """
            
            let rawContent = try await performRequestWithParsingRetry(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let content = normalizeTags(rawContent)
            
            var questions: [(String, String, [String], String?)] = []
            let blocks = content.components(separatedBy: "[END]")
            
            for block in blocks {
                let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedBlock.isEmpty else { continue }
                
                var question = ""
                var answer = ""
                var options: [String] = []
                var explanation: String? = nil
                
                let lines = trimmedBlock.components(separatedBy: .newlines)
                var currentTag = ""
                var currentText = ""
                
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedLine == "[QUESTION]" || trimmedLine == "[ANSWER]" || trimmedLine == "[OPTION]" || trimmedLine == "[EXPLANATION]" {
                        if !currentTag.isEmpty {
                            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                switch currentTag {
                                case "[QUESTION]": question = removeAngleBracketPlaceholders(cleanMath(value))
                                case "[ANSWER]": answer = removeAngleBracketPlaceholders(cleanMath(value))
                                case "[OPTION]": options.append(removeAngleBracketPlaceholders(cleanMath(value)))
                                case "[EXPLANATION]": explanation = removeAngleBracketPlaceholders(cleanMath(value))
                                default: break
                                }
                            }
                        }
                        currentTag = trimmedLine
                        currentText = ""
                    } else {
                        currentText += line + "\n"
                    }
                }
                
                if !currentTag.isEmpty {
                    let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        switch currentTag {
                        case "[QUESTION]": question = removeAngleBracketPlaceholders(cleanMath(value))
                        case "[ANSWER]": answer = removeAngleBracketPlaceholders(cleanMath(value))
                        case "[OPTION]": options.append(removeAngleBracketPlaceholders(cleanMath(value)))
                        case "[EXPLANATION]": explanation = removeAngleBracketPlaceholders(cleanMath(value))
                        default: break
                        }
                    }
                }
                
                if !question.isEmpty && !answer.isEmpty {
                    // Fix options if needed
                    if !optionsContainAnswer(options, answer: answer) {
                        // Insert answer at the beginning instead of overwriting
                        options.insert(answer, at: 0)
                    }
                    
                    // Ensure 4 options
                    while options.count < 4 {
                        options.append("Option \(options.count + 1)")
                    }
                    if options.count > 4 {
                        options = Array(options.prefix(4))
                    }
                    
                    questions.append((question, answer, options.shuffled(), explanation))
                }
            }
            
            if questions.isEmpty { throw AIError.parsingFailed }
            return questions
            
        } catch {
            print("AI Generation failed: \(error)")
            throw error
        }
    }
    
    /// Generates flashcards to help learn a new topic
    func generateTopicFlashcards(topic: String, count: Int, difficulty: SummaryDifficulty = .intermediate) async throws -> [(front: String, back: String)] {
        do {
            let systemPrompt = "You are a precise flashcard generator. Follow the exact tag format. No markdown, no numbering, no extra prose."
            let difficultyInstruction: String
            switch difficulty {
            case .beginner:
                difficultyInstruction = "Focus on basic terminology and fundamental concepts."
            case .intermediate:
                difficultyInstruction = "Include practical applications and important techniques."
            case .advanced:
                difficultyInstruction = "Cover advanced concepts, nuances, and expert-level knowledge."
            }
            
            let userPrompt = """
            Generate \(count) flashcards (like in Quizlet) about: \(topic)
            
            Difficulty: \(difficulty.rawValue) - \(difficultyInstruction)

            Use the following EXACT format for each flashcard (no extra blank lines between tags):

            [FRONT]
            Term text
            [BACK]
            Definition text
            [END]

            IMPORTANT - FOLLOW ALL:
            1) Do NOT use JSON or markdown.
            2) Do NOT use headings (#, ##) or bold/italics. No numbering of cards.
            3) Keep the 'front' very short (3-9 words) and the 'back' concise (under 20 words).
            4) Keep EXACT tags as shown. No extra tags or bullets.
            5) Produce exactly \(count) flashcards.

            GOOD EXAMPLE (copy structure, change content):
            [FRONT]
            Factorising purpose
            [BACK]
            Reveal common factors to simplify.
            [END]
            
            MATH FORMATTING RULES (follow exactly):
            - Wrap ALL math expressions in single dollar signs: $...$
            - Use \\frac{a}{b} for fractions, NOT a/b for complex fractions
            - Use \\sqrt{x} or \\sqrt[n]{x} for roots
            - Use \\sum_{i=1}^{n}, \\int_{a}^{b}, \\prod for summation, integrals, products
            - Use ^{} for superscripts and _{} for subscripts (e.g., $x^{2}$, $a_{n}$)
            - Use \\left( and \\right) for auto-sizing parentheses
            - Use \\cdot for multiplication, \\times for cross product
            - Greek letters: \\alpha, \\beta, \\pi, \\theta, \\Delta, etc.
            - Examples: $\\frac{-b \\pm \\sqrt{b^{2} - 4ac}}{2a}$, $\\int_{0}^{\\infty} e^{-x^{2}} dx$
            """
            
            let rawContent = try await performRequestWithParsingRetry(systemPrompt: systemPrompt, userPrompt: userPrompt)
            let content = normalizeTags(rawContent)
            
            var cards: [(String, String)] = []
            let blocks = content.components(separatedBy: "[END]")
            
            for block in blocks {
                let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedBlock.isEmpty else { continue }
                
                var front = ""
                var back = ""
                
                let lines = trimmedBlock.components(separatedBy: .newlines)
                var currentTag = ""
                var currentText = ""
                
                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedLine == "[FRONT]" || trimmedLine == "[BACK]" {
                        if !currentTag.isEmpty {
                            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !value.isEmpty {
                                switch currentTag {
                                case "[FRONT]": front = value
                                case "[BACK]": back = value
                                default: break
                                }
                                // Handle multiple front/back pairs inside a single block
                                if !front.isEmpty && !back.isEmpty {
                                    cards.append((front, back))
                                    front = ""
                                    back = ""
                                }
                            }
                        }
                        currentTag = trimmedLine
                        currentText = ""
                    } else {
                        currentText += line + "\n"
                    }
                }
                
                if !currentTag.isEmpty {
                    let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        switch currentTag {
                        case "[FRONT]": front = value
                        case "[BACK]": back = value
                        default: break
                        }
                    }
                }
                
                if !front.isEmpty && !back.isEmpty {
                    cards.append((front, back))
                }
            }
            
            if cards.isEmpty { throw AIError.parsingFailed }
            return cards
            
        } catch {
            print("AI Generation failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Tutor Chat
    
    /// Describes what context to include in the tutor chat
    struct TutorContext: Sendable {
        let originalText: String
        let summary: String?
        let studySetTitle: String
        
        /// Creates context with only original text and summary (no flashcards/quiz)
        static func create(from studySet: StudySet) -> TutorContext {
            return TutorContext(
                originalText: studySet.originalText,
                summary: studySet.summary,
                studySetTitle: studySet.title
            )
        }
        
        /// Builds the context string for the AI prompt and logs what's included
        func buildContextString() -> String {
            var contextParts: [String] = []
            
            // Always include original text
            contextParts.append("originalText")
            
            var context = """
            STUDY MATERIAL:
            \(originalText)
            """
            
            if let summary = summary, !summary.isEmpty {
                contextParts.append("summary")
                context += """
                
                
                SUMMARY:
                \(summary)
                """
            }
            
            // Console log what context is being sent
            print("[LearnHub Tutor] Context sent to AI: [\(contextParts.joined(separator: ", "))] for study set: \(studySetTitle)")
            
            return context
        }
    }
    
    /// Chat message for conversational context
    struct ChatTurn: Sendable {
        let role: String // "user" or "assistant"
        let content: String
    }
    
    /// Typealias for backwards compatibility
    typealias TutorResponseFormat = TutorResponseFormatType
    
    /// Performs a chat request with conversation history and study set context
    func performChat(
        messages: [ChatTurn],
        context: TutorContext,
        format: TutorResponseFormat = .standard
    ) async throws -> String {
        // Build context string (this also logs what's included)
        let contextString = context.buildContextString()
        
        // Get format-specific output instructions
        let formatBlock = getFormatInstructions(for: format)
        
        // SYSTEM PROMPT: Role + rules only (no user content)
        let systemPrompt = """
        You are a concise study tutor. Follow these rules EXACTLY:
        
        CRITICAL RULES:
        1. Start with content immediately. NEVER say "Certainly", "Sure", "Here's", etc.
        2. MAXIMUM 100 words total unless solving a math problem. Be extremely concise.
        3. Use **bold** for key terms only.
        4. Use • for bullets, numbered lists (1. 2. 3.) for steps.
        5. Never echo instructions or study set name.
        
        MATH FORMATTING (CRITICAL - use LaTeX with $ delimiters):
        - Wrap ALL math expressions in single dollar signs: $...$
        - Fractions: $\\frac{a}{b}$ (NOT a/b for complex fractions)
        - Exponents: $x^{2}$, $e^{-x}$
        - Roots: $\\sqrt{x}$, $\\sqrt[3]{x}$
        - Greek: $\\alpha$, $\\beta$, $\\pi$, $\\theta$
        - Operators: $\\times$, $\\div$, $\\pm$, $\\cdot$
        - Example: The quadratic formula is $x = \\frac{-b \\pm \\sqrt{b^{2} - 4ac}}{2a}$
        
        MATH PROBLEM DETECTION:
        If the user asks to solve, calculate, or work out a specific math problem (equation, expression, word problem with numbers), you MUST:
        1. Start your response with [MATHSTEP] tag
        2. Show step-by-step solution with each step numbered
        3. Use → to show transformations
        4. End with [SOLUTION] tag containing the final answer
        5. Optionally add [TIP] with the key concept used
        
        CRITICAL RULES:
        1. Start with content immediately. NEVER say "Certainly", "Sure", "Here's", etc.
        2. Use **bold** for key terms only (not for section headings).
        3. Use • for bullets and 1./2./3. for steps.
        4. SECTION HEADINGS MUST BE TAGS like [SKILL], [STEPS], [SOLUTION] (no markdown bold headings, no colons).
        - Tags are optional for simple conversational responses.
        
        \(formatBlock)
        """
        
        // USER PROMPT: Context + actual question (sent as the user message)
        // We inject context into the first user message or prepend to current
        var augmentedMessages = messages
        if let lastUserIndex = messages.lastIndex(where: { $0.role == "user" }) {
            let originalContent = messages[lastUserIndex].content
            let augmentedContent = """
            [CONTEXT]
            \(contextString)
            [END CONTEXT]
            
            [QUESTION]
            \(originalContent)
            """
            augmentedMessages[lastUserIndex] = ChatTurn(role: "user", content: augmentedContent)
        }
        
        print("[LearnHub Tutor] Sending request with format: \(format)")
        
        return try await performConversationalRequest(
            systemPrompt: systemPrompt,
            messages: augmentedMessages
        )
    }
    
    /// Performs a conversational request with message history
    private func performConversationalRequest(
        systemPrompt: String,
        messages: [ChatTurn]
    ) async throws -> String {
        let selection = await selectProvider()
        
        switch selection.provider {
        case .appleIntelligence:
            do {
                return try await runAppleIntelligenceConversation(
                    systemPrompt: systemPrompt,
                    messages: messages
                )
            } catch {
                let reason = "Apple Intelligence unavailable. Falling back to Groq."
                setFallbackNoticeIfNeeded(selection.fallbackNotice ?? reason)
                return try await runGroqConversation(
                    systemPrompt: systemPrompt,
                    messages: messages
                )
            }
        case .groq:
            setFallbackNoticeIfNeeded(selection.fallbackNotice)
            return try await runGroqConversation(
                systemPrompt: systemPrompt,
                messages: messages
            )
        }
    }
    
    private func runGroqConversation(
        systemPrompt: String,
        messages: [ChatTurn]
    ) async throws -> String {
        let apiKey = try await groqApiKey()
        let model = await ModelSettings.groqModel()
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build messages array with system prompt and conversation history
        var apiMessages: [GroqRequest.Message] = [
            .init(role: "system", content: systemPrompt)
        ]
        
        for msg in messages {
            apiMessages.append(.init(role: msg.role, content: msg.content))
        }
        
        let payload = GroqRequest(model: model, messages: apiMessages)
        request.httpBody = try JSONEncoder().encode(payload)
        
        await applyRateLimitDelay()
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.generationFailed
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorDetail = "Status code: \(httpResponse.statusCode)"
            if let errorResponse = try? JSONDecoder().decode(GroqErrorResponse.self, from: data) {
                errorDetail = "\(errorResponse.error.message) (Code: \(errorResponse.error.code ?? "\(httpResponse.statusCode)"))"
            } else if let errorText = String(data: data, encoding: .utf8) {
                print("Groq API Error: \(errorText)")
            }
            throw AIError.apiError(errorDetail)
        }
        
        let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        guard let content = decodedResponse.choices.first?.message.content else {
            throw AIError.invalidResponse
        }
        
        return content
    }
    
    private func runAppleIntelligenceConversation(
        systemPrompt: String,
        messages: [ChatTurn]
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let session = LanguageModelSession(instructions: systemPrompt)
            
            // Only send the last user message to avoid echoing system prompts
            // The session already has the instructions (system prompt)
            if let lastMessage = messages.last, lastMessage.role == "user" {
                let response = try await session.respond(to: lastMessage.content)
                return response.content
            } else {
                throw AIError.invalidResponse
            }
        } else {
            throw AIError.apiError("Apple Intelligence requires iOS 26 or later.")
        }
        #else
        throw AIError.apiError("FoundationModels framework is unavailable.")
        #endif
    }
    
    // MARK: - Vision Chat (Image Analysis)
    
    /// Performs a vision chat request with an image attachment
    /// Always uses Groq (Apple Intelligence does not support vision)
    func performVisionChat(
        imageData: Data,
        userMessage: String,
        context: TutorContext
    ) async throws -> String {
        let visionModel = await MainActor.run { ModelSettings.visionModel }
        print("[LearnHub Vision] Uploading image, size: \(imageData.count) bytes")
        print("[LearnHub Vision] Model: \(visionModel)")
        
        // Build context string
        let contextString = context.buildContextString()
        
        // Vision-specific system prompt
                let systemPrompt = #"""
                You are a study tutor analyzing an image. Output must use TAGS ONLY (no markdown headings/colons). If you cannot include the required tags, return: [SKILL] Unable to comply\n[KEYTAKEAWAY] Add tags and retry.

                TAGS:
                - Math: [SKILL], [MATHSTEP] (one block with numbered steps), [SOLUTION], [KEYTAKEAWAY], optional [TIP]
                - Work check: [WORKCHECK], [ERROR STEP], [CORRECTION], [SOLUTION], [KEYTAKEAWAY]
                - Science/graphs: [SKILL], [KEYPOINTS] or [EXPLANATION], [KEYTAKEAWAY], optional [TIP]
                - Code: [SKILL], [STEPS] (numbered), [KEYTAKEAWAY], optional [TIP]
                - Writing: [SKILL], [KEYPOINTS], [EXPLANATION], [KEYTAKEAWAY]
                - Notes/screens: [SUMMARY], [STEPS] or [KEYPOINTS], [KEYTAKEAWAY]

                HARD RULES:
                - Start immediately; no preamble. DO NOT output anything outside tags.
                - For math, use a SINGLE [MATHSTEP] block containing at least 2 numbered lines showing transformations. No multiple [MATHSTEP] tags.
                - Math must be LaTeX inside single $...$ only. Allowed: $\frac{a}{b}$, $x^{2}$, $\sqrt{x}$, $\times$, $\div$, $\pm$, $\cdot$. Forbidden: \( \), \[ \], $$, \boxed, code fences.
                - Keep only the tags relevant to the chosen template. Do NOT add extra sections (e.g., no [KEYPOINTS]/[EXPLANATION] for math unless asked).
                - Be concise; prefer numbered steps/bullets.

                TEMPLATES (choose one):
                - Math solve:
                    [SKILL] ...
                    [MATHSTEP] 1) ... → ...\n2) ... → ... (show algebra)
                    [SOLUTION] ...
                    [KEYTAKEAWAY] ...
                    [TIP] ... (optional)
                - Work check:
                    [WORKCHECK]\n[ERROR STEP] ...\n[CORRECTION] ...\n[SOLUTION] ...\n[KEYTAKEAWAY] ...
                - Science/diagram/graph:
                    [SKILL]\n[KEYPOINTS] ...\n[KEYTAKEAWAY] ...\n[TIP] ...
                - Code/debugging:
                    [SKILL]\n[STEPS] 1) ...\n2) ...\n[KEYTAKEAWAY] ...\n[TIP] ...
                - Writing/grammar:
                    [SKILL]\n[KEYPOINTS] ...\n[EXPLANATION] ...\n[KEYTAKEAWAY] ...
                - General notes/screens:
                    [SUMMARY]\n[STEPS] or [KEYPOINTS] ...\n[KEYTAKEAWAY] ...

                STRONG EXAMPLES (copy the tag order and brevity):
                - Math (one [MATHSTEP] block with numbered transformations):
                    [SKILL] Simplify negative exponents
                    [MATHSTEP] 1) $\frac{4x^{-2}y^{3}}{ka^{-3}}$ → $\frac{4y^{3}}{k} \cdot \frac{a^{3}}{x^{2}}$ (move $a^{-3}$ up, $x^{-2}$ down)\n2) Multiply numerators/denominators → $\frac{4a^{3}y^{3}}{kx^{2}}$
                    [SOLUTION] $\frac{4a^{3}y^{3}}{kx^{2}}$
                    [KEYTAKEAWAY] Flip negatives across the fraction to make exponents positive.
                - Work check (no extra tags):
                    [WORKCHECK]\n[ERROR STEP] Sign flipped on line 2\n[CORRECTION] Distribute: $-3(x-2)=-3x+6$\n[SOLUTION] $y=-3x+11$\n[KEYTAKEAWAY] Track negatives when distributing.
                - Science/diagram (keep it lean):
                    [SKILL] Circuit analysis\n[KEYPOINTS] Series circuit; $R_{eq}=R_{1}+R_{2}$; current identical everywhere\n[KEYTAKEAWAY] Series voltages add, current shared.\n[TIP] Label current direction before summing voltages.
                - Graph/data:
                    [SKILL] Velocity-time graph\n[KEYPOINTS] Slope=acceleration; area=displacement\n[KEYTAKEAWAY] Area under curve gives distance.
                - Code:
                    [SKILL] Python loop bug\n[STEPS] 1) Use range(n), not range(n+1)\n2) Init sum outside loop\n[KEYTAKEAWAY] Loop bounds and init placement matter.
                - Writing:
                    [SKILL] Thesis clarity\n[KEYPOINTS] Add a claim sentence; fix tense drift\n[EXPLANATION] Insert a 1-line claim; keep past tense consistent\n[KEYTAKEAWAY] Lead with claim; keep tense steady.

                USE-CASE REMINDERS:
                - Math: [SKILL] → [MATHSTEP] → [SOLUTION] → [KEYTAKEAWAY] (+[TIP] optional).
                - Work check: [WORKCHECK] → [ERROR STEP] → [CORRECTION] → [SOLUTION] → [KEYTAKEAWAY].
                - Science/graphs: [SKILL] → [KEYPOINTS]/[EXPLANATION] → [KEYTAKEAWAY] → [TIP].
                - Code: [SKILL] → [STEPS] → [KEYTAKEAWAY] (+[TIP]).
                - Writing: [SKILL] → [KEYPOINTS] → [EXPLANATION] → [KEYTAKEAWAY].
                - Notes/screens: [SUMMARY] → [STEPS]/[KEYPOINTS] → [KEYTAKEAWAY].

                CONTEXT (for reference - may be empty):
                \#(contextString.isEmpty ? "No additional context provided." : contextString)
                """#
        
        // Build the user message with context
        let fullUserMessage = userMessage.isEmpty ? "Analyze this image and help me understand it." : userMessage
        
        return try await runGroqVision(
            systemPrompt: systemPrompt,
            userMessage: fullUserMessage,
            imageData: imageData,
            visionModel: visionModel
        )
    }
    
    private func runGroqVision(
        systemPrompt: String,
        userMessage: String,
        imageData: Data,
        visionModel: String
    ) async throws -> String {
        let apiKey = try await groqApiKey()
        let modelsToTry = getVisionModelFallbacks(primaryModel: visionModel)
        
        var lastError: Error?
        
        for model in modelsToTry {
            do {
                let result = try await attemptGroqVisionRequest(
                    systemPrompt: systemPrompt,
                    userMessage: userMessage,
                    imageData: imageData,
                    model: model,
                    apiKey: apiKey
                )
                if model != visionModel {
                    print("AI (Groq Vision) - Fell back to model: \(model)")
                }
                return result
            } catch {
                // Capture any per-model error, save it and continue to the next fallback model.
                lastError = error
                print("AI (Groq Vision) - Model \(model) failed with error: \(error). Trying next fallback...")
                continue
            }
        }
        
        // If we get here, all models failed with rate limits
        if let error = lastError {
            throw error
        }
        throw AIError.generationFailed
    }
    
    private func attemptGroqVisionRequest(
        systemPrompt: String,
        userMessage: String,
        imageData: Data,
        model: String,
        apiKey: String
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert image to base64
        let base64Image = imageData.base64EncodedString()
        let imageURL = "data:image/jpeg;base64,\(base64Image)"
        
        print("[LearnHub Vision] Base64 encoded, length: \(base64Image.count) characters")
        
        // Build multimodal messages
        let systemMessage = GroqMultimodalRequest.MultimodalMessage(
            role: "system",
            content: [GroqMultimodalRequest.ContentPart(text: systemPrompt)]
        )
        
        let userContent: [GroqMultimodalRequest.ContentPart] = [
            GroqMultimodalRequest.ContentPart(imageURL: imageURL),
            GroqMultimodalRequest.ContentPart(text: userMessage)
        ]
        
        let userMessageObj = GroqMultimodalRequest.MultimodalMessage(
            role: "user",
            content: userContent
        )
        
        let payload = GroqMultimodalRequest(
            model: model,
            messages: [systemMessage, userMessageObj]
        )
        
        request.httpBody = try JSONEncoder().encode(payload)
        
        await applyRateLimitDelay()
        
        print("[LearnHub Vision] Sending request to Groq...")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("[LearnHub Vision] Error: No HTTP response received")
            throw AIError.generationFailed
        }
        
        print("[LearnHub Vision] Response status code: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorDetail = "Vision API status code: \(httpResponse.statusCode)"
            if let errorResponse = try? JSONDecoder().decode(GroqErrorResponse.self, from: data) {
                errorDetail = "\(errorResponse.error.message) (Code: \(errorResponse.error.code ?? "\(httpResponse.statusCode)"))"
            } else if let errorText = String(data: data, encoding: .utf8) {
                print("[LearnHub Vision] API Error: \(errorText)")
            }
            throw AIError.apiError(errorDetail)
        }
        
        let decodedResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        guard let content = decodedResponse.choices.first?.message.content else {
            print("[LearnHub Vision] Error: No content in response")
            throw AIError.invalidResponse
        }
        
        print("[LearnHub Vision] Successfully received response")
        print("AI (Vision) response:\n\(content)\n--- end response ---")
        
        return content
    }
    
    private func getVisionModelFallbacks(primaryModel: String) -> [String] {
        // Define fallback chain for vision models
        // If primary is meta-llama/llama-4-maverick-17b-128e-instruct, fallback to meta-llama/llama-4-scout-17b-16e-instruct
        let fallbackChain: [String: [String]] = [
            "meta-llama/llama-4-maverick-17b-128e-instruct": ["meta-llama/llama-4-scout-17b-16e-instruct"],
            "meta-llama/llama-4-scout-17b-16e-instruct": []
        ]
        
        var modelsToTry = [primaryModel]
        if let fallbacks = fallbackChain[primaryModel] {
            modelsToTry.append(contentsOf: fallbacks)
        }
        return modelsToTry
    }
    
    // MARK: - Format Instructions for Specialized Responses
    
    private func getFormatInstructions(for format: TutorResponseFormat) -> String {
        switch format {
        case .standard:
            return """
            For general questions, respond in 2-4 sentences. Max 80 words.
            If you need to list points, start with [KEYPOINTS] tag.
            If explaining steps, start with [STEPS] tag.
            Otherwise, just answer directly without any tags.
            """
        case .comparison:
            return """
            YOU MUST START YOUR RESPONSE WITH: [COMPARE]
            
            EXACT FORMAT:
            [COMPARE]
            **[Topic A]** vs **[Topic B]**
            [KEYPOINTS]
            • **Similarity**: [What they share]
            • **Difference**: [How A differs] vs [How B differs]
            • **Difference**: [Another contrast]
            [SUMMARY]
            [One sentence: the key distinction.]
            
            All tags MUST be ALL CAPS. Max 80 words total.
            """
        case .mnemonic:
            return """
            YOU MUST START YOUR RESPONSE WITH: [MNEMONIC]
            
            EXACT FORMAT:
            [MNEMONIC]
            **[Catchy phrase or acronym]**
            [BREAKDOWN]
            • [Letter/Word] → [What it stands for]
            • [Letter/Word] → [What it stands for]
            [TIP]
            [One sentence on why this helps you remember.]
            
            All tags MUST be ALL CAPS. Max 80 words total.
            """
        case .steps:
            return """
            YOU MUST START YOUR RESPONSE WITH: [STEPS]
            
            EXACT FORMAT:
            [STEPS]
            1. **[Action verb]**: [Brief explanation]
            2. **[Action verb]**: [Brief explanation]
            3. **[Action verb]**: [Brief explanation]
            
            Max 5 steps. Each step = ONE line only. Max 80 words total.
            """
        case .example:
            return """
            YOU MUST START YOUR RESPONSE WITH: [SCENARIO]
            
            EXACT FORMAT:
            [SCENARIO]
            [A relatable real-world situation in 1-2 sentences]
            [CONNECTION]
            [How it connects to the concept in 1-2 sentences]
            [TAKEAWAY]
            [One sentence lesson.]
            
            All tags MUST be ALL CAPS. Max 80 words total.
            """
        case .simplify:
            return """
            YOU MUST START YOUR RESPONSE WITH: [SIMPLE]
            
            EXACT FORMAT:
            [SIMPLE]
            [2-3 sentences explaining in everyday language. No jargon. Like explaining to a friend who knows nothing about this.]
            
            Max 60 words after the tag.
            """
        case .keyPoints:
            return """
            YOU MUST START YOUR RESPONSE WITH: [KEYPOINTS]
            
            EXACT FORMAT:
            [KEYPOINTS]
            • [Most important point]
            • [Second point]
            • [Third point]
            
            Max 4 bullets. Each bullet = one clear sentence. Max 60 words total.
            """
        case .analogy:
            return """
            YOU MUST START YOUR RESPONSE WITH: [ANALOGY]
            
            EXACT FORMAT:
            [ANALOGY]
            **[Familiar comparison - kitchen, sports, daily life]**
            [MAPPING]
            • [Concept part] ↔ [Analogy part]
            • [Concept part] ↔ [Analogy part]
            [INSIGHT]
            [One sentence takeaway.]
            
            All tags MUST be ALL CAPS. Max 80 words total.
            """
        case .mistakes:
            return """
            YOU MUST START YOUR RESPONSE WITH: [MISTAKES]
            
            EXACT FORMAT:
            [MISTAKES]
            ✗ **[Error 1]** → [Why it's wrong]
            ✓ [How to do it correctly]
            ✗ **[Error 2]** → [Why it's wrong]
            ✓ [How to do it correctly]
            [EXAMPLE]
            [One concrete worked example: "e.g., To simplify 12/18: GCF=6, so 12/6=2, 18/6=3, answer=2/3"]
            
            All tags MUST be ALL CAPS. Max 2 mistakes. Max 100 words total.
            """
        case .mathSolver:
            return """
            YOU MUST START YOUR RESPONSE WITH: [MATHSTEP]
            
            You are solving a specific math problem step by step. Break it down clearly.
            
            FORMAT:
            [MATHSTEP]
            **Problem:** [Restate the problem briefly]
            
            **Step 1:** [Description of what you're doing]
            → $[LaTeX expression showing the work]$
            
            **Step 2:** [Next operation]
            → $[LaTeX expression]$
            
            **Step 3:** [Continue as needed]
            → $[LaTeX expression]$
            
            [SOLUTION]
            **Answer:** $[Final answer in LaTeX]$
            
            [TIP]
            [One sentence explaining the key concept or method used.]
            
            MATH FORMATTING (use LaTeX with $ delimiters):
            - Wrap ALL math in $...$
            - Fractions: $\\frac{numerator}{denominator}$
            - Exponents: $x^{2}$, $a^{n}$
            - Roots: $\\sqrt{x}$, $\\sqrt[n]{x}$
            - Equals/arrows: use → for step transitions, $=$ inside expressions
            - Example: $2x + 5 = 15$ → $2x = 10$ → $x = 5$
            
            Keep steps atomic (one operation per step). Maximum 6 steps.
            """
        }
    }
    
    // MARK: - Smart Quick Prompts
    
    /// Generates context-aware quick prompt suggestions based on user input and recent chat
    func generateQuickPrompts(
        partialInput: String,
        recentMessages: [ChatTurn],
        context: TutorContext
    ) -> [QuickPrompt] {
        var prompts: [QuickPrompt] = []
        let lowercased = partialInput.lowercased()
        
        // Static base prompts with specialized formats
        let basePrompts: [QuickPrompt] = [
            QuickPrompt(
                id: "simplify",
                label: "Simplify",
                icon: "lightbulb.min",
                prompt: "[FORMAT:simplify] Explain the main concept here in the simplest possible terms.",
                format: .simplify
            ),
            QuickPrompt(
                id: "example",
                label: "Example",
                icon: "globe",
                prompt: "[FORMAT:example] Give me a real-world example of this concept.",
                format: .example
            ),
            QuickPrompt(
                id: "mnemonic",
                label: "Memory trick",
                icon: "brain.head.profile",
                prompt: "[FORMAT:mnemonic] What's a catchy phrase or mnemonic that could help me study and remember the main ideas here?",
                format: .mnemonic
            ),
            QuickPrompt(
                id: "compare",
                label: "Compare",
                icon: "arrow.left.arrow.right",
                prompt: "[FORMAT:comparison] Contrast the two main ideas: where are they similar, where do they differ?",
                format: .comparison
            ),
            QuickPrompt(
                id: "steps",
                label: "Step by step",
                icon: "list.number",
                prompt: "[FORMAT:steps] Break down the main process or concept into clear steps.",
                format: .steps
            ),
            QuickPrompt(
                id: "keypoints",
                label: "Key points",
                icon: "list.bullet",
                prompt: "[FORMAT:keypoints] What are the most important points I need to know?",
                format: .keyPoints
            ),
            QuickPrompt(
                id: "analogy",
                label: "Analogy",
                icon: "arrow.triangle.branch",
                prompt: "[FORMAT:analogy] Help me understand this using a familiar everyday comparison.",
                format: .analogy
            ),
            QuickPrompt(
                id: "mistakes",
                label: "Common mistakes",
                icon: "exclamationmark.triangle",
                prompt: "[FORMAT:mistakes] What are the top mistakes, how to fix them, and one quick example?",
                format: .mistakes
            ),
            QuickPrompt(
                id: "mathsolve",
                label: "Solve math",
                icon: "function",
                prompt: "[FORMAT:mathSolver] Solve this math problem step by step, showing all work.",
                format: .mathSolver
            ),
            QuickPrompt(
                id: "why",
                label: "Why it matters",
                icon: "questionmark.circle",
                prompt: "[FORMAT:simple] In one paragraph (max 60 words), explain why this topic matters.",
                format: .simplify
            ),
            QuickPrompt(
                id: "formula",
                label: "Formulas",
                icon: "function",
                prompt: "[FORMAT:keypoints] List the key formulas as bullets with what each variable means.",
                format: .keyPoints
            ),
            QuickPrompt(
                id: "cheatsheet",
                label: "Cheat sheet",
                icon: "note.text",
                prompt: "[FORMAT:keypoints] Give me a tiny cheat sheet: 5 bullets max with the most actionable reminders.",
                format: .keyPoints
            )
        ]
        
        // If user is typing something, filter/prioritize based on input
        if !lowercased.isEmpty {
            // Check for specific query patterns and suggest relevant prompts
            if lowercased.contains("why") || lowercased.contains("how") {
                prompts.append(basePrompts.first { $0.id == "simplify" }!)
                prompts.append(basePrompts.first { $0.id == "steps" }!)
                prompts.append(basePrompts.first { $0.id == "why" }!)
            }
            
            if lowercased.contains("remember") || lowercased.contains("memorize") {
                prompts.append(basePrompts.first { $0.id == "mnemonic" }!)
            }
            
            if lowercased.contains("difference") || lowercased.contains("compare") || lowercased.contains("vs") {
                prompts.append(basePrompts.first { $0.id == "compare" }!)
            }
            
            if lowercased.contains("wrong") || lowercased.contains("mistake") || lowercased.contains("error") {
                prompts.append(basePrompts.first { $0.id == "mistakes" }!)
                prompts.append(basePrompts.first { $0.id == "cheatsheet" }!)
            }
            
            // Add remaining prompts not already added
            for prompt in basePrompts {
                if !prompts.contains(where: { $0.id == prompt.id }) {
                    prompts.append(prompt)
                }
            }
        } else {
            // No input - return base prompts in default order
            prompts = basePrompts
        }
        
        // Limit to 12 prompts for UI
        return Array(prompts.prefix(12))
    }
    
    /// Converts an AI response into flashcard format
    func convertToFlashcards(
        aiResponse: String,
        context: TutorContext
    ) async throws -> [(front: String, back: String)] {
        let systemPrompt = """
        You are a flashcard generator. You MUST output ONLY the exact tag format below. No other text allowed.
        """
        
        let userPrompt = """
        Convert this into flashcards. Create only as many as truly needed (1-3 max). If one flashcard captures it well, just make one.
        
        Output ONLY this format, nothing else:
        
        [FRONT]
        short term or question
        [BACK]
        brief answer
        [END]
        
        EXAMPLE OUTPUT:
        [FRONT]
        What is photosynthesis?
        [BACK]
        Process where plants convert sunlight to energy using chlorophyll.
        [END]
        
        STRICT RULES:
        - Start IMMEDIATELY with [FRONT] - no intro text
        - Each [FRONT] must have exactly one [BACK] and one [END]
        - Front: 2-8 words (term or question)
        - Back: 5-20 words (definition or answer)
        - NO markdown, NO bullets, NO numbering
        - Create 1-3 cards only (not more)
        
        TEXT TO CONVERT:
        \(aiResponse)
        """
        
        let rawContent = try await performRequestWithParsingRetry(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let content = normalizeTags(rawContent)
        
        var cards: [(String, String)] = []
        let blocks = content.components(separatedBy: "[END]")
        
        for block in blocks {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBlock.isEmpty else { continue }
            
            var front = ""
            var back = ""
            
            let lines = trimmedBlock.components(separatedBy: .newlines)
            var currentTag = ""
            var currentText = ""
            
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine == "[FRONT]" || trimmedLine == "[BACK]" {
                    if !currentTag.isEmpty {
                        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            switch currentTag {
                            case "[FRONT]": front = value
                            case "[BACK]": back = value
                            default: break
                            }
                        }
                    }
                    currentTag = trimmedLine
                    currentText = ""
                } else {
                    currentText += line + "\n"
                }
            }
            
            if !currentTag.isEmpty {
                let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    switch currentTag {
                    case "[FRONT]": front = value
                    case "[BACK]": back = value
                    default: break
                    }
                }
            }
            
            if !front.isEmpty && !back.isEmpty {
                cards.append((front, back))
            }
        }
        
        if cards.isEmpty { throw AIError.parsingFailed }
        return Array(cards.prefix(5)) // Limit to 5 max
    }
    
}

