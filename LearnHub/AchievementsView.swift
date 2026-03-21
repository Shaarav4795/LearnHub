import SwiftUI
import SwiftData

struct AchievementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @StateObject private var gamificationManager = GamificationManager.shared
    
    @State private var selectedCategory: AchievementCategory = .all
    
    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }
    
    enum AchievementCategory: String, CaseIterable {
        case all = "All"
        case questions = "Questions"
        case streaks = "Streaks"
        case studySets = "Study Sets"
        case flashcards = "Flashcards"
        case perfection = "Perfection"
        case levels = "Levels"
        
        var types: [AchievementType] {
            switch self {
            case .all:
                return AchievementType.allCases
            case .questions:
                return [.questions5, .questions10, .questions50, .questions100, .questions500, .questions1000]
            case .streaks:
                return [.streak1, .streak7, .streak14, .streak31, .streak100, .streak365]
            case .studySets:
                return [.studySets1, .studySets5, .studySets10, .studySets25, .studySets50]
            case .flashcards:
                return [.flashcards25, .flashcards100, .flashcards500, .flashcards1000]
            case .perfection:
                return [.perfectQuiz1, .perfectQuiz5, .perfectQuiz10, .perfectQuiz25]
            case .levels:
                return [.level5, .level10, .level25, .level50, .level75]
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Progress summary for earned vs remaining achievements.
                achievementSummary
                
                // Category filter pills.
                categoryPicker
                
                // Grid of achievement cards for the selected category.
                achievementGrid
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Achievement summary
    
    private var achievementSummary: some View {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("\(profile.achievements?.count ?? 0)")
                    .font(.largeTitle.bold())
                    .foregroundColor(.primary)
                
                Text("Earned")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 50)
            
            VStack(spacing: 8) {
                Text("\(AchievementType.allCases.count - (profile.achievements?.count ?? 0))")
                    .font(.largeTitle.bold())
                    .foregroundColor(.secondary)
                
                Text("Remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 50)
            
            VStack(spacing: 8) {
                let percentage = Double(profile.achievements?.count ?? 0) / Double(AchievementType.allCases.count) * 100
                Text("\(Int(percentage))%")
                    .font(.largeTitle.bold())
                    .foregroundColor(.blue)
                
                Text("Complete")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
    }
    
    // MARK: - Category picker
    
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AchievementCategory.allCases, id: \.self) { category in
                    CategoryPill(
                        title: category.rawValue,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Achievement grid
    
    private var achievementGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(selectedCategory.types, id: \.self) { achievementType in
                AchievementCard(
                    type: achievementType,
                    isUnlocked: isUnlocked(achievementType),
                    progress: getProgress(for: achievementType)
                )
            }
        }
    }
    
    // MARK: - Helper functions
    
    private func isUnlocked(_ type: AchievementType) -> Bool {
        (profile.achievements ?? []).contains(where: { $0.type == type.rawValue })
    }
    
    private func getProgress(for type: AchievementType) -> Double {
        let current: Int
        let requirement = type.requirement
        
        switch type {
        case .questions5, .questions10, .questions50, .questions100, .questions500, .questions1000:
            current = profile.totalQuestionsCorrect
        case .streak1, .streak7, .streak14, .streak31, .streak100, .streak365:
            current = max(profile.currentStreak, profile.longestStreak)
        case .studySets1, .studySets5, .studySets10, .studySets25, .studySets50:
            current = profile.totalStudySets
        case .flashcards25, .flashcards100, .flashcards500, .flashcards1000:
            current = profile.totalFlashcardsStudied
        case .perfectQuiz1, .perfectQuiz5, .perfectQuiz10, .perfectQuiz25:
            current = profile.perfectQuizzes
        case .level5, .level10, .level25, .level50, .level75:
            current = profile.level
        }
        
        return min(1.0, Double(current) / Double(requirement))
    }
}

// MARK: - Supporting views

struct CategoryPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticsManager.shared.playTap()
            action()
        }) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .glassCard(cornerRadius: 100, strokeOpacity: isSelected ? 0.3 : 0.1)
        }
        .buttonStyle(.plain)
        .buttonStyle(PressScaleButtonStyle())
    }
}

struct AchievementCard: View {
    let type: AchievementType
    let isUnlocked: Bool
    let progress: Double
    
    var body: some View {
        VStack(spacing: 12) {
            // Icon indicates unlocked vs locked state.
            ZStack {
                Circle()
                    .fill(isUnlocked ? colorForType.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                if isUnlocked {
                    Image(systemName: type.icon)
                        .font(.title)
                        .foregroundColor(colorForType)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            
            // Achievement title.
            Text(type.title)
                .font(.subheadline.bold())
                .foregroundColor(isUnlocked ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // Short achievement description.
            Text(type.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            // Progress bar for locked achievements.
            if !isUnlocked {
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorForType)
                                .frame(width: geometry.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Reward chips shown after unlock.
            if isUnlocked {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("\(type.xpReward)")
                            .font(.caption2.bold())
                            .foregroundColor(.blue)
                    }
                    
                    HStack(spacing: 2) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                        Text("\(type.coinReward)")
                            .font(.caption2.bold())
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isUnlocked ? colorForType.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }
    
    private var colorForType: Color {
        switch type.color {
        case "green": return .green
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "cyan": return .cyan
        case "yellow": return .yellow
        case "gold": return .orange
        default: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        AchievementsView()
    }
    .modelContainer(for: [StudySet.self, UserProfile.self], inMemory: true)
}
