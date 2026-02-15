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
        self.hasMath = text.contains("$")
        if text.contains("$") {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private static let cacheLock = NSLock()
    private static var parsedLinesCache: [String: [ParsedLine]] = [:]
    private static var attributedTextCache: [String: AttributedString] = [:]
    private static let maxCacheEntries = 96

    private static func cachedAttributedText(for text: String) -> AttributedString {
        cacheLock.lock()
        if let cached = attributedTextCache[text] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let attributed: AttributedString
        do {
            attributed = try AttributedString(markdown: text)
        } catch {
            attributed = AttributedString(text)
        }

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
            ParsedLine(id: index, segments: parseMath(line))
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
    }
    
    private static func splitByNewlines(_ text: String) -> [String] {
        // Remove empty lines to avoid rendering empty rows.
        return text.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
    
    private static func parseMath(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        segments.reserveCapacity(max(2, text.count / 24))
        var segmentID = 0
        let components = text.components(separatedBy: "$")
        
        for (index, component) in components.enumerated() {
            if index % 2 == 1 {
                // Math segment between $...$ delimiters.
                if !component.isEmpty {
                    segments.append(Segment(id: segmentID, content: component, isMath: true))
                    segmentID += 1
                }
            } else {
                // Text segment parsed as Markdown using `AttributedString`.
                if !component.isEmpty {
                    if !containsMarkdownSyntax(component) {
                        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            // Split plain text into word-like tokens (preserve trailing spaces) so
                            // the FlowLayout can wrap within a line that mixes math + text.
                            let ns = component as NSString
                            if let regex = try? NSRegularExpression(pattern: "\\S+\\s*", options: []) {
                                let matches = regex.matches(in: component, options: [], range: NSRange(location: 0, length: ns.length))
                                for m in matches {
                                    let token = ns.substring(with: m.range)
                                    segments.append(Segment(id: segmentID, content: token, isMath: false))
                                    segmentID += 1
                                }
                            } else {
                                segments.append(Segment(id: segmentID, content: trimmed, isMath: false))
                                segmentID += 1
                            }
                        }
                        continue
                    }
                    do {
                        // Skip segments that are only whitespace.
                        if component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                             continue 
                        }
                        
                        let attributed = try AttributedString(markdown: component)
                        
                        for run in attributed.runs {
                            let runText = String(attributed[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !runText.isEmpty else { continue }
                            let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) ?? false
                            let isItalic = run.inlinePresentationIntent?.contains(.emphasized) ?? false

                            // Break the attributed run into smaller tokens so FlowLayout can wrap
                            // between words while preserving bold/italic flags.
                            let ns = runText as NSString
                            if let regex = try? NSRegularExpression(pattern: "\\S+\\s*", options: []) {
                                let matches = regex.matches(in: runText, options: [], range: NSRange(location: 0, length: ns.length))
                                for m in matches {
                                    let token = ns.substring(with: m.range)
                                    segments.append(Segment(id: segmentID, content: token, isMath: false, isBold: isBold, isItalic: isItalic))
                                    segmentID += 1
                                }
                            } else {
                                segments.append(Segment(id: segmentID, content: runText, isMath: false, isBold: isBold, isItalic: isItalic))
                                segmentID += 1
                            }
                        }
                    } catch {
                        // Fallback to plain text tokens if Markdown parsing fails.
                        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            segments.append(Segment(id: segmentID, content: trimmed, isMath: false))
                            segmentID += 1
                        }
                    }
                }
            }
        }
        
        return segments
    }

    private static func containsMarkdownSyntax(_ value: String) -> Bool {
        value.contains("*") || value.contains("_") || value.contains("#") || value.contains("`") || value.contains("[") || value.contains("]")
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flow(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flow(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func flow(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        
        // Store items for the current line to center-align vertically.
        struct LineItem {
            let index: Int
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
        
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            
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
            currentLineItems.append(LineItem(index: index, size: size, x: currentX))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        // Finalize the last line.
        finalizeLine(items: currentLineItems, currentY: currentY, lineHeight: lineHeight)
        
        return (CGSize(width: maxWidth == .infinity ? currentX : maxWidth, height: currentY + lineHeight), points)
    }
}
