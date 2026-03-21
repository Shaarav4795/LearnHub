// Widget timelines and views for LearnHub.

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Shared widget data model

struct WidgetFlashcard: Codable, Identifiable {
    var id: UUID
    var front: String
    var back: String
    var isMastered: Bool
}

struct WidgetStudySet: Codable, Identifiable {
    var id: UUID
    var title: String
    var icon: String
    var flashcards: [WidgetFlashcard]
}

struct WidgetData: Codable {
    var level: Int
    var totalXP: Int
    var xpProgress: Double
    var xpToNextLevel: Int
    var currentStreak: Int
    var coins: Int
    var cardsToReview: Int = 0
    var studySets: [WidgetStudySet] = []
    
    static let placeholder = WidgetData(
        level: 1,
        totalXP: 0,
        xpProgress: 0.0,
        xpToNextLevel: 100,
        currentStreak: 0,
        coins: 100,
        cardsToReview: 5,
        studySets: []
    )
    
    static func load() -> WidgetData {
        guard let userDefaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub.hf"),
              let data = userDefaults.data(forKey: "widgetData"),
              let widgetData = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return .placeholder
        }
        return widgetData
    }
}

// MARK: - Timeline entry

struct LearnHubEntry: TimelineEntry {
    let date: Date
    let widgetData: WidgetData
    var statsType: StatsType = .streak
}

// MARK: - Progress widget provider (medium)

struct ProgressWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LearnHubEntry {
        LearnHubEntry(date: Date(), widgetData: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (LearnHubEntry) -> ()) {
        let entry = LearnHubEntry(date: Date(), widgetData: WidgetData.load())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LearnHubEntry>) -> ()) {
        let currentDate = Date()
        let entry = LearnHubEntry(date: currentDate, widgetData: WidgetData.load())
        
        // Refresh every 15 minutes.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Stats widget provider (small)

struct StatsWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LearnHubEntry {
        LearnHubEntry(date: Date(), widgetData: .placeholder, statsType: .streak)
    }

    func snapshot(for configuration: StatsConfigurationIntent, in context: Context) async -> LearnHubEntry {
        LearnHubEntry(date: Date(), widgetData: WidgetData.load(), statsType: configuration.statsType)
    }

    func timeline(for configuration: StatsConfigurationIntent, in context: Context) async -> Timeline<LearnHubEntry> {
        let currentDate = Date()
        let entry = LearnHubEntry(date: currentDate, widgetData: WidgetData.load(), statsType: configuration.statsType)
        
        // Refresh every 15 minutes.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Progress widget view (medium)

struct ProgressWidgetEntryView: View {
    var entry: ProgressWidgetProvider.Entry
    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        HStack(spacing: 16) {
            // Level and XP summary.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.body)
                        .foregroundColor(.yellow)
                    Text("Level \(entry.widgetData.level)")
                        .font(.headline.bold())
                        .foregroundColor(.primary)
                }
                
                // XP progress bar.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 12)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * entry.widgetData.xpProgress), height: 12)
                    }
                }
                .frame(height: 12)
                
                Text("\(entry.widgetData.xpToNextLevel) XP to next")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Divider between sections.
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1, height: 55)
            
            // Streak summary.
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundColor(entry.widgetData.currentStreak > 0 ? .orange : .gray)
                    Text("\(entry.widgetData.currentStreak)")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
                Text("Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Divider between sections.
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1, height: 55)
            
            // Coin balance summary.
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    Text("\(entry.widgetData.coins)")
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                }
                Text("Coins")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Stats widget view (small)

struct StatsWidgetEntryView: View {
    var entry: LearnHubEntry

    var body: some View {
        VStack(spacing: 8) {
            if entry.statsType == .streak {
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundColor(entry.widgetData.currentStreak > 0 ? .orange : .gray)
                    .shadow(color: entry.widgetData.currentStreak > 0 ? .orange.opacity(0.5) : .clear, radius: 8, x: 0, y: 4)
                
                Text("\(entry.widgetData.currentStreak)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Day Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Text("\(entry.widgetData.cardsToReview)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("To Review")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "learnhub://stats?type=\(entry.statsType.rawValue)"))
    }
}

// MARK: - Progress widget (medium)

struct LearnHubProgressWidget: Widget {
    let kind: String = "LearnHubProgressWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProgressWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                ProgressWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                ProgressWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(uiColor: .systemBackground))
            }
        }
        .configurationDisplayName("Study Progress")
        .description("View your level, XP progress, streak, and coins at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Stats widget (small)

struct LearnHubStatsWidget: Widget {
    let kind: String = "LearnHubStatsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StatsConfigurationIntent.self, provider: StatsWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                StatsWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                StatsWidgetEntryView(entry: entry)
                    .padding()
                    .background(Color(uiColor: .systemBackground))
            }
        }
        .configurationDisplayName("Study Stats")
        .description("Track your streak or cards to review.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Previews

#Preview("Progress Widget", as: .systemMedium) {
    LearnHubProgressWidget()
} timeline: {
    LearnHubEntry(date: .now, widgetData: WidgetData(level: 5, totalXP: 450, xpProgress: 0.6, xpToNextLevel: 80, currentStreak: 7, coins: 250))
    LearnHubEntry(date: .now, widgetData: WidgetData(level: 10, totalXP: 1200, xpProgress: 0.3, xpToNextLevel: 150, currentStreak: 14, coins: 500))
}

#Preview("Stats Widget", as: .systemSmall) {
    LearnHubStatsWidget()
} timeline: {
    LearnHubEntry(date: .now, widgetData: WidgetData(level: 5, totalXP: 450, xpProgress: 0.6, xpToNextLevel: 80, currentStreak: 7, coins: 250))
    LearnHubEntry(date: .now, widgetData: WidgetData(level: 1, totalXP: 0, xpProgress: 0.0, xpToNextLevel: 100, currentStreak: 0, coins: 100))
}
