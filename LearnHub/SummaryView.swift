import SwiftUI

struct SummaryView: View {
    let summary: String
    var isGuide: Bool = false
    private let parsedItems: [SummaryItem]?
    
    enum SummaryItem: Hashable {
        case bullet(String)
        case text(String)
        case header(String, Int)
    }

    init(summary: String, isGuide: Bool = false) {
        self.summary = summary
        self.isGuide = isGuide
        self.parsedItems = Self.cachedParsedItems(for: summary)
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: isGuide ? "book.fill" : "text.alignleft")
                        .foregroundColor(.accentColor)
                    Text(isGuide ? "Learning Guide" : "Summary")
                        .font(.title2)
                        .bold()
                }
                .padding(.bottom, 8)
                
                // Removed AI-generated caption per user request
                
                if let items = parsedItems {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            switch item {
                            case .bullet(let text):
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.primary)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 8)

                                    MathTextView(text, fontSize: 17)
                                }
                            case .text(let text):
                                MathTextView(text, fontSize: 17)
                                    .padding(.vertical, 2)
                            case .header(let text, let level):
                                let size: CGFloat = level == 1 ? 22 : (level == 2 ? 20 : 18)
                                MathTextView(text, fontSize: size, forceBold: true)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding()
                    .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                } else {
                    MathTextView(summary, fontSize: 17)
                        .padding()
                        .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                }
            }
            .padding()
        }
    }

    private static let cacheLock = NSLock()
    private static var bulletCache: [String: [SummaryItem]] = [:]
    private static var plainTextCache: Set<String> = []
    private static let maxCacheEntries = 64

    private static func cachedParsedItems(for text: String) -> [SummaryItem]? {
        cacheLock.lock()
        if let cached = bulletCache[text] {
            cacheLock.unlock()
            return cached
        }
        if plainTextCache.contains(text) {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()

        let parsed: [SummaryItem]?
        if Self.isBulletPoints(text) {
            parsed = Self.parseBulletPoints(text)
        } else {
            parsed = nil
        }

        cacheLock.lock()
        if let parsed {
            bulletCache[text] = parsed
            if bulletCache.count > maxCacheEntries, let keyToRemove = bulletCache.keys.first {
                bulletCache.removeValue(forKey: keyToRemove)
            }
        } else {
            plainTextCache.insert(text)
            if plainTextCache.count > maxCacheEntries, let keyToRemove = plainTextCache.first {
                plainTextCache.remove(keyToRemove)
            }
        }
        cacheLock.unlock()

        return parsed
    }
    
    private static func isBulletPoints(_ text: String) -> Bool {
        let rawLines = text.components(separatedBy: .newlines)
        let nonEmptyLines = rawLines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard nonEmptyLines.count >= 2 else { return false }

        var markerCount = 0
        for line in nonEmptyLines {
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                markerCount += 1
            } else if let _ = line.range(of: "^\\d+\\. ", options: .regularExpression) {
                markerCount += 1
            }
        }

        // Treat as a bullet list when at least one line uses an explicit list marker
        return markerCount >= 1
    }
    
    private static func parseBulletPoints(_ text: String) -> [SummaryItem] {
        let lines = text.components(separatedBy: .newlines)
        var results: [SummaryItem] = []
        results.reserveCapacity(lines.count)

        var currentType: ItemType? = nil
        var currentContent: String? = nil
        
        enum ItemType {
            case bullet
            case text
        }

        func finishCurrent() {
            if let content = currentContent?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty {
                if currentType == .bullet {
                    results.append(.bullet(content))
                } else {
                    results.append(.text(content))
                }
            }
            currentContent = nil
            currentType = nil
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            if trimmed.hasPrefix("- ") {
                finishCurrent()
                currentType = .bullet
                currentContent = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("* ") {
                finishCurrent()
                currentType = .bullet
                currentContent = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("• ") {
                finishCurrent()
                currentType = .bullet
                currentContent = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let match = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) {
                finishCurrent()
                currentType = .bullet
                let after = trimmed[match.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                currentContent = String(after)
            } else if trimmed.hasPrefix("#") {
                finishCurrent()
                let hashCount = trimmed.prefix(while: { $0 == "#" }).count
                let content = String(trimmed.dropFirst(hashCount)).trimmingCharacters(in: .whitespaces)
                results.append(.header(content, hashCount))
            } else {
                // Continuation or plain text
                if let type = currentType {
                    if type == .bullet {
                        currentContent = (currentContent! + " " + trimmed)
                    } else {
                        // type is .text
                        currentContent = (currentContent! + " " + trimmed)
                    }
                } else {
                    // No current item. Start as text.
                    currentType = .text
                    currentContent = trimmed
                }
            }
        }

        finishCurrent()

        return results
    }
}
