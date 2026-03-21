import WidgetKit
import SwiftUI
import AppIntents

struct FlashcardEntry: TimelineEntry {
    let date: Date
    let studySet: WidgetStudySet?
    let currentCard: WidgetFlashcard?
    let isFlipped: Bool
    let cardIndex: Int
    let totalCards: Int
}

struct FlashcardProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FlashcardEntry {
        FlashcardEntry(
            date: Date(),
            studySet: nil,
            currentCard: WidgetFlashcard(id: UUID(), front: "Front", back: "Back", isMastered: false),
            isFlipped: false,
            cardIndex: 1,
            totalCards: 10
        )
    }

    func snapshot(for configuration: SelectStudySetIntent, in context: Context) async -> FlashcardEntry {
        await getEntry(for: configuration)
    }

    func timeline(for configuration: SelectStudySetIntent, in context: Context) async -> Timeline<FlashcardEntry> {
        let entry = await getEntry(for: configuration)
        return Timeline(entries: [entry], policy: .never)
    }
    
    private func getEntry(for configuration: SelectStudySetIntent) async -> FlashcardEntry {
        let data = WidgetData.load()
        
        // If no set is selected, fall back to the first available set.
        let setID = configuration.studySet?.id ?? data.studySets.first?.id
        
        guard let targetID = setID,
              let set = data.studySets.first(where: { $0.id == targetID }) else {
            return FlashcardEntry(
                date: Date(),
                studySet: nil,
                currentCard: nil,
                isFlipped: false,
                cardIndex: 0,
                totalCards: 0
            )
        }
        
        let defaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub.hf")
        let indexKey = "cardIndex_\(set.id.uuidString)"
        let flipKey = "flipState_\(set.id.uuidString)"
        
        let index = defaults?.integer(forKey: indexKey) ?? 0
        let isFlipped = defaults?.bool(forKey: flipKey) ?? false
        
        let card = set.flashcards.indices.contains(index) ? set.flashcards[index] : set.flashcards.first
        
        return FlashcardEntry(
            date: Date(),
            studySet: set,
            currentCard: card,
            isFlipped: isFlipped,
            cardIndex: index + 1,
            totalCards: set.flashcards.count
        )
    }
}

struct FlashcardWidgetEntryView: View {
    var entry: FlashcardProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(spacing: 0) {
            if let set = entry.studySet, let card = entry.currentCard {
                // Header with set title and position.
                HStack {
                    Label(set.title, systemImage: set.icon.isEmpty ? "book.fill" : set.icon)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(entry.cardIndex) / \(entry.totalCards)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)
                
                // Main flashcard surface (tap to flip).
                Button(intent: FlipFlashcardIntent(setID: set.id)) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(UIColor.systemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                            )
                        
                        VStack {
                            Spacer()
                            
                            Text(entry.isFlipped ? card.back : card.front)
                                .font(.system(size: entry.isFlipped ? 18 : 22, weight: entry.isFlipped ? .regular : .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(Color.primary)
                                .id(card.id.uuidString + (entry.isFlipped ? "_back" : "_front"))
                            
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)
                
                // Footer action to advance to the next card.
                HStack {
                    Spacer()
                    Button(intent: NextFlashcardIntent(setID: set.id)) {
                        HStack(spacing: 4) {
                            Text("Next")
                                .fontWeight(.semibold)
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
                
            } else {
                // Empty state when no study set is configured.
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.blue.opacity(0.8))
                    Text("No Flashcards")
                        .font(.headline)
                    Text("Select a study set to start learning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetURL(entry.studySet.map { URL(string: "learnhub://flashcards?setID=\($0.id.uuidString)") } ?? nil)
    }
}

struct FlashcardWidget: Widget {
    let kind: String = "LearnHubFlashcardWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectStudySetIntent.self, provider: FlashcardProvider()) { entry in
            if #available(iOS 17.0, *) {
                FlashcardWidgetEntryView(entry: entry)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .containerBackground(for: .widget) {
                        Color(UIColor.secondarySystemBackground)
                    }
            } else {
                FlashcardWidgetEntryView(entry: entry)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .configurationDisplayName("Flashcards")
        .description("Study your flashcards directly from the Home Screen.")
        .supportedFamilies([.systemLarge])
    }
}
