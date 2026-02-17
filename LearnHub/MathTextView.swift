import SwiftUI
import Foundation

struct MathTextView: View {
    let text: String
    let fontSize: CGFloat
    /// When true, render all non-math segments in bold for emphasis.
    let forceBold: Bool
    private let hasMath: Bool
    private let parsedLines: [ParsedLine]
    private let attributedText: AttributedString?
    @Environment(\.multilineTextAlignment) var textAlignment
    
    init(_ text: String, fontSize: CGFloat = 17, forceBold: Bool = false) {
        self.text = text
        self.fontSize = fontSize
        self.forceBold = forceBold
        let containsMath = Self.containsMathDelimiter(in: text)
        self.hasMath = containsMath
        if containsMath {
            self.parsedLines = Self.cachedParsedLines(for: text)
            self.attributedText = nil
        } else {
            self.parsedLines = []
            self.attributedText = Self.cachedAttributedText(for: text)
        }
    }
    
    private var alignment: HorizontalAlignment {
        switch textAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    
    var body: some View {
        Group {
            if !hasMath, let attributedText {
                Text(attributedText)
                    .font(.system(size: fontSize))
                    .fontWeight(forceBold ? .bold : .regular)
                    .multilineTextAlignment(textAlignment)
            } else {
                // Math-heavy path: keep segments coarse, but preserve inline reading flow.
                LazyVStack(alignment: alignment, spacing: 8) {
                    ForEach(parsedLines) { line in
                        if let attributed = line.attributed {
                            Text(attributed)
                                .font(.system(size: fontSize))
                                .fontWeight(forceBold ? .bold : .regular)
                                .multilineTextAlignment(textAlignment)
                        } else {
                            if #available(iOS 16.0, *) {
                                FlowLayout(spacing: 4, lineSpacing: 4, alignment: alignment) {
                                    ForEach(line.segments) { segment in
                                        if segment.isMath {
                                            MathView(equation: segment.content, fontSize: fontSize + 2)
                                                .fixedSize()
                                        } else {
                                            Text(segment.content)
                                                .font(.system(size: fontSize))
                                                .fontWeight((forceBold || segment.isBold) ? .bold : .regular)
                                                .italic(segment.isItalic)
                                        }
                                    }
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) {
                                        ForEach(line.segments) { segment in
                                            if segment.isMath {
                                                MathView(equation: segment.content, fontSize: fontSize + 2)
                                                    .fixedSize()
                                            } else {
                                                Text(segment.content)
                                                    .font(.system(size: fontSize))
                                                    .fontWeight((forceBold || segment.isBold) ? .bold : .regular)
                                                    .italic(segment.isItalic)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private static let cacheLock = NSLock()
    private static var parsedLinesCache: [String: [ParsedLine]] = [:]
    private static var attributedTextCache: [String: AttributedString] = [:]
    private static let maxCacheEntries = 96
    private static let mathPattern = try! NSRegularExpression(
        pattern: #"\$\$(.+?)\$\$|\$(?!\$)(.+?)(?<!\$)\$|\\\((.+?)\\\)|\\\[(.+?)\\\]"#,
        options: []
    )
    private static let wrapTokenPattern = try! NSRegularExpression(pattern: "\\S+\\s*", options: [])
    private static let plainTextChars = CharacterSet(charactersIn: "*_#`[]")
    private static let maxWrapTokensPerSegment = 3

    private static func cachedAttributedText(for text: String) -> AttributedString {
        cacheLock.lock()
        if let cached = attributedTextCache[text] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let attributed = markdownToAttributedString(text)

        cacheLock.lock()
        attributedTextCache[text] = attributed
        if attributedTextCache.count > maxCacheEntries, let keyToRemove = attributedTextCache.keys.first {
            attributedTextCache.removeValue(forKey: keyToRemove)
        }
        cacheLock.unlock()

        return attributed
    }

    private static func cachedParsedLines(for text: String) -> [ParsedLine] {
        cacheLock.lock()
        if let cached = parsedLinesCache[text] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let lines = splitByNewlines(text)
        let parsed = lines.enumerated().map { index, line in
            if containsMathDelimiter(in: line) {
                ParsedLine(id: index, segments: parseMath(line), attributed: nil)
            } else {
                ParsedLine(id: index, segments: [], attributed: markdownToAttributedString(line))
            }
        }

        cacheLock.lock()
        parsedLinesCache[text] = parsed
        if parsedLinesCache.count > maxCacheEntries, let keyToRemove = parsedLinesCache.keys.first {
            parsedLinesCache.removeValue(forKey: keyToRemove)
        }
        cacheLock.unlock()

        return parsed
    }
    
    private struct Segment: Identifiable {
        let id: Int
        let content: String
        let isMath: Bool
        var isBold: Bool = false
        var isItalic: Bool = false
    }

    private struct ParsedLine: Identifiable {
        let id: Int
        let segments: [Segment]
        let attributed: AttributedString?
    }
    
    private static func splitByNewlines(_ text: String) -> [String] {
        // Remove empty lines to avoid rendering empty rows.
        return text.split(whereSeparator: { $0.isNewline }).map(String.init)
    }
    
    private static func parseMath(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        segments.reserveCapacity(6)
        var segmentID = 0
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = mathPattern.matches(in: text, options: [], range: fullRange)

        guard !matches.isEmpty else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(Segment(id: segmentID, content: text, isMath: false))
            }
            return segments
        }

        // Fast path for an entire-line equation wrapped in delimiters.
        if matches.count == 1,
           let only = matches.first,
           only.range.location == 0,
           only.range.length == ns.length,
           let equation = stripMathDelimiters(text),
           !equation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(Segment(id: 0, content: equation, isMath: true))
            return segments
        }

        var currentLocation = 0
        for match in matches {
            let matchRange = match.range
            if matchRange.location > currentLocation {
                let textRange = NSRange(location: currentLocation, length: matchRange.location - currentLocation)
                let plainText = ns.substring(with: textRange)
                if !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendWrapTokens(plainText, to: &segments, segmentID: &segmentID)
                }
            }

            let rawMath = ns.substring(with: matchRange)
            if let equation = stripMathDelimiters(rawMath), !equation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(Segment(id: segmentID, content: equation, isMath: true))
                segmentID += 1
            }

            currentLocation = matchRange.location + matchRange.length
        }

        if currentLocation < ns.length {
            let tailRange = NSRange(location: currentLocation, length: ns.length - currentLocation)
            let tailText = ns.substring(with: tailRange)
            if !tailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appendWrapTokens(tailText, to: &segments, segmentID: &segmentID)
            }
        }

        return segments
    }

    private static func markdownToAttributedString(_ text: String) -> AttributedString {
        if !containsMarkdownSyntax(in: text) {
            return AttributedString(text)
        }

        do {
            return try AttributedString(markdown: text)
        } catch {
            return AttributedString(text)
        }
    }

    private static func containsMathDelimiter(in value: String) -> Bool {
        if !value.contains("$") && !value.contains("\\(") && !value.contains("\\[") {
            return false
        }

        let ns = value as NSString
        let range = NSRange(location: 0, length: ns.length)
        return mathPattern.firstMatch(in: value, options: [], range: range) != nil
    }

    private static func containsMarkdownSyntax(in value: String) -> Bool {
        value.rangeOfCharacter(from: plainTextChars) != nil
    }

    private static func stripMathDelimiters(_ value: String) -> String? {
        if value.hasPrefix("$$"), value.hasSuffix("$$"), value.count >= 4 {
            return String(value.dropFirst(2).dropLast(2))
        }
        if value.hasPrefix("$") && value.hasSuffix("$") && value.count >= 2 {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("\\(") && value.hasSuffix("\\)") && value.count >= 4 {
            return String(value.dropFirst(2).dropLast(2))
        }
        if value.hasPrefix("\\[") && value.hasSuffix("\\]") && value.count >= 4 {
            return String(value.dropFirst(2).dropLast(2))
        }
        return nil
    }

    private static func appendWrapTokens(_ value: String, to segments: inout [Segment], segmentID: inout Int) {
        let ns = value as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = wrapTokenPattern.matches(in: value, options: [], range: range)

        if matches.isEmpty {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            segments.append(Segment(id: segmentID, content: trimmed, isMath: false))
            segmentID += 1
            return
        }

        var tokenBuffer = ""
        var tokenCount = 0

        for match in matches {
            tokenBuffer += ns.substring(with: match.range)
            tokenCount += 1

            if tokenCount >= maxWrapTokensPerSegment {
                segments.append(Segment(id: segmentID, content: tokenBuffer, isMath: false))
                segmentID += 1
                tokenBuffer.removeAll(keepingCapacity: true)
                tokenCount = 0
            }
        }

        if !tokenBuffer.isEmpty {
            segments.append(Segment(id: segmentID, content: tokenBuffer, isMath: false))
            segmentID += 1
        }
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    struct Cache {
        var proposalWidth: CGFloat = -1
        var subviewCount: Int = 0
        var size: CGSize = .zero
        var points: [CGPoint] = []
        var valid = false
    }

    var spacing: CGFloat
    var lineSpacing: CGFloat
    var alignment: HorizontalAlignment = .leading

    func makeCache(subviews: Subviews) -> Cache {
        Cache(subviewCount: subviews.count)
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.subviewCount != subviews.count {
            cache.subviewCount = subviews.count
            cache.valid = false
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        ensureFlow(proposal: proposal, subviews: subviews, cache: &cache)
        return cache.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        ensureFlow(proposal: proposal, subviews: subviews, cache: &cache)
        for (index, subview) in subviews.enumerated() {
            guard index < cache.points.count else { continue }
            let point = cache.points[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func ensureFlow(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = proposal.width ?? .infinity
        if cache.valid && cache.proposalWidth == maxWidth && cache.subviewCount == subviews.count {
            return
        }

        let subviewSizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = flow(maxWidth: maxWidth, subviewSizes: subviewSizes)
        cache.proposalWidth = maxWidth
        cache.subviewCount = subviews.count
        cache.size = result.size
        cache.points = result.points
        cache.valid = true
    }

    private func flow(maxWidth: CGFloat, subviewSizes: [CGSize]) -> (size: CGSize, points: [CGPoint]) {
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        
        // Store items for the current line to center-align vertically.
        struct LineItem {
            let size: CGSize
            let x: CGFloat
        }
        var currentLineItems: [LineItem] = []
        
        func finalizeLine(items: [LineItem], currentY: CGFloat, lineHeight: CGFloat) {
            let lineWidth = items.last.map { $0.x + $0.size.width } ?? 0
            let xOffset: CGFloat
            
            if maxWidth != .infinity {
                switch alignment {
                case .center:
                    xOffset = (maxWidth - lineWidth) / 2
                case .trailing:
                    xOffset = maxWidth - lineWidth
                default:
                    xOffset = 0
                }
            } else {
                xOffset = 0
            }
            
            for item in items {
                let yOffset = (lineHeight - item.size.height) / 2
                points.append(CGPoint(x: item.x + xOffset, y: currentY + yOffset))
            }
        }
        
        for size in subviewSizes {
            
            // Wrap to a new line when the current line overflows.
            if currentX + size.width > maxWidth && !currentLineItems.isEmpty {
                // Finalize positions for the current line.
                finalizeLine(items: currentLineItems, currentY: currentY, lineHeight: lineHeight)
                
                // Reset state for the next line.
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
                currentLineItems = []
            }
            
            // Add item to the active line.
            currentLineItems.append(LineItem(size: size, x: currentX))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        // Finalize the last line.
        finalizeLine(items: currentLineItems, currentY: currentY, lineHeight: lineHeight)
        
        return (CGSize(width: maxWidth == .infinity ? currentX : maxWidth, height: currentY + lineHeight), points)
    }
}
