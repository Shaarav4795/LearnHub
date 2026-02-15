import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// User-configurable model preference and BYOK key storage.
enum AIModelPreference: String, CaseIterable, Identifiable {
    case automatic
    case groqOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .groqOnly: return "Groq Only"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Prefers Apple Intelligence when available; otherwise uses Groq with your key."
        case .groqOnly:
            return "Always uses your Groq BYOK key."
        }
    }
}

enum ModelSettings {
    enum Keys {
        static let preference = "ai.modelPreference"
        static let groqApiKey = "ai.groq.apiKey"
        static let groqModel = "ai.groq.model"
    }

    // Default Groq model is now the compound family (falls back to smaller / OSS models)
    static let defaultGroqModel = "groq/compound"
    static let visionModel = "meta-llama/llama-4-maverick-17b-128e-instruct"

    static func preference() async -> AIModelPreference {
        await MainActor.run {
            let raw = UserDefaults.standard.string(forKey: Keys.preference) ?? AIModelPreference.automatic.rawValue
            // Migration: map legacy values to the current `groqOnly` option.
            if raw == "openRouterOnly" || raw == "GroqOnly" { return .groqOnly }
            return AIModelPreference(rawValue: raw) ?? .automatic
        }
    }

    static func setPreference(_ value: AIModelPreference) async {
        await MainActor.run {
            UserDefaults.standard.set(value.rawValue, forKey: Keys.preference)
        }
    }

    static func groqApiKey() async -> String {
        await MainActor.run {
            UserDefaults.standard.string(forKey: Keys.groqApiKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    static func setGroqApiKey(_ value: String) async {
        await MainActor.run {
            UserDefaults.standard.set(value, forKey: Keys.groqApiKey)
        }
    }

    static func groqModel() async -> String {
        await MainActor.run {
            let raw = UserDefaults.standard.string(forKey: Keys.groqModel)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw?.isEmpty == false ? raw! : defaultGroqModel
        }
    }

    static func setGroqModel(_ value: String) async {
        await MainActor.run {
            UserDefaults.standard.set(value, forKey: Keys.groqModel)
        }
    }

    nonisolated(unsafe) static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            // Apple recommends checking the system model availability before use.
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                return true
            case .unavailable:
                return false
            @unknown default:
                return false
            }
        }
        return false
        #else
        return false
        #endif
    }
}
