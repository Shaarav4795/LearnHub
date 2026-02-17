import Foundation
import SwiftData
import SwiftUI
import Combine
import WidgetKit
import UserNotifications

// MARK: - Widget data structures (shared with extension)

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
        cardsToReview: 0,
        studySets: []
    )
}

// MARK: - Gamification manager

final class GamificationManager: ObservableObject {
    static let shared = GamificationManager()

    enum BoosterDurationUnit {
        case hours
        case days
    }

    struct HybridPrice {
        let coins: Int
        let xp: Int
    }
    
    @Published var showAchievementUnlocked: Bool = false
    @Published var unlockedAchievement: AchievementType?
    @Published var showXPGained: Bool = false
    @Published var xpGained: Int = 0
    @Published var showLevelUp: Bool = false
    @Published var newLevel: Int = 0
    @Published var showCoinsEarned: Bool = false
    @Published var coinsEarned: Int = 0

    private enum PracticeKeys {
        static let wrongQuestionIDs = "dailyMix.wrongQuestionIDs"
    }
    
    private init() {}

    // MARK: - Practice memory

    func recordQuestionResult(questionID: UUID, wasCorrect: Bool) {
        var ids = Set(fetchIncorrectQuestionIDs())
        if wasCorrect {
            ids.remove(questionID)
        } else {
            ids.insert(questionID)
        }
        let payload = ids.map(\.uuidString)
        UserDefaults.standard.set(payload, forKey: PracticeKeys.wrongQuestionIDs)
    }

    func fetchIncorrectQuestionIDs() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: PracticeKeys.wrongQuestionIDs) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }
    
    // MARK: - Widget data sync
    
    func syncStudySets(_ sets: [StudySet]) {
        let widgetSets = sets.map { set in
            WidgetStudySet(
                id: set.id,
                title: set.title,
                icon: set.iconId,
                flashcards: set.flashcards.map { card in
                    WidgetFlashcard(id: card.id, front: card.front, back: card.back, isMastered: card.isMastered)
                }
            )
        }
        
        // Load existing widget data so we can preserve non-study-set fields.
        var widgetData: WidgetData
        if let userDefaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub"),
           let data = userDefaults.data(forKey: "widgetData"),
           let existing = try? JSONDecoder().decode(WidgetData.self, from: data) {
            widgetData = existing
            widgetData.studySets = widgetSets
            
            // Update the derived "cards to review" count based on due spaced-repetition cards.
            widgetData.cardsToReview = dueFlashcardCount(from: sets)
            
        } else {
            // Fallback if no widget data exists yet.
            widgetData = WidgetData.placeholder
            widgetData.studySets = widgetSets
            widgetData.cardsToReview = dueFlashcardCount(from: sets)
        }
        
        if let userDefaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub"),
           let data = try? JSONEncoder().encode(widgetData) {
            userDefaults.set(data, forKey: "widgetData")
            userDefaults.synchronize()
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    func updateWidgetData(from profile: UserProfile, studySets: [StudySet]? = nil) {
        // Load existing sets when none are provided.
        var currentSets: [WidgetStudySet] = []
        if let userDefaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub"),
           let data = userDefaults.data(forKey: "widgetData"),
           let existing = try? JSONDecoder().decode(WidgetData.self, from: data) {
            currentSets = existing.studySets
        }
        
        let setsToSave: [WidgetStudySet]
        if let studySets = studySets {
            setsToSave = studySets.map { set in
                WidgetStudySet(
                    id: set.id,
                    title: set.title,
                    icon: set.iconId,
                    flashcards: set.flashcards.map { card in
                        WidgetFlashcard(id: card.id, front: card.front, back: card.back, isMastered: card.isMastered)
                    }
                )
            }
        } else {
            setsToSave = currentSets
        }
        
        let cardsToReview: Int
        if let studySets {
            cardsToReview = dueFlashcardCount(from: studySets)
        } else {
            cardsToReview = setsToSave.reduce(0) { count, set in
                count + set.flashcards.filter { !$0.isMastered }.count
            }
        }
        
        let widgetData = WidgetData(
            level: profile.level,
            totalXP: profile.totalXP,
            xpProgress: profile.xpProgress,
            xpToNextLevel: profile.xpToNextLevel,
            currentStreak: profile.currentStreak,
            coins: profile.coins,
            cardsToReview: cardsToReview,
            studySets: setsToSave
        )
        
        if let userDefaults = UserDefaults(suiteName: "group.com.shaarav4795.LearnHub"),
           let data = try? JSONEncoder().encode(widgetData) {
            userDefaults.set(data, forKey: "widgetData")
            userDefaults.synchronize()
        }
        
        // Trigger a widget timeline reload.
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func dueFlashcardCount(from sets: [StudySet]) -> Int {
        let now = Date()
        return sets.reduce(0) { count, set in
            count + set.flashcards.filter { card in
                guard let due = card.reviewDueDate else { return false }
                return due <= now
            }.count
        }
    }
    
    // MARK: - User profile management
    
    @MainActor
    func getOrCreateProfile(context: ModelContext) -> UserProfile {
        let descriptor = FetchDescriptor<UserProfile>()
        if let profiles = try? context.fetch(descriptor), let profile = profiles.first {
            updateWidgetData(from: profile)
            return profile
        }
        
        let newProfile = UserProfile()
        context.insert(newProfile)
        try? context.save()
        updateWidgetData(from: newProfile)
        return newProfile
    }
    
    // MARK: - XP and coin management
    
    @MainActor
    func addXP(_ amount: Int, to profile: UserProfile, context: ModelContext) {
        let previousLevel = profile.level
        let multiplier = totalXPMultiplier(for: profile, context: context)
        let actualXP = Int(Double(amount) * multiplier)
        
        profile.totalXP += actualXP
        
        // Determine whether a level-up occurred.
        let newLevelValue = profile.level
        if newLevelValue > previousLevel {
            self.newLevel = newLevelValue
            self.showLevelUp = true
            
            // Evaluate level-based achievements.
            checkLevelAchievements(profile: profile, context: context)
            
            // Auto-dismiss the level-up banner after a short delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.showLevelUp = false
            }
        }
        
        self.xpGained = actualXP
        self.showXPGained = true
        
        try? context.save()
        updateWidgetData(from: profile)
        
        // Auto-hide the XP banner after a short delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showXPGained = false
        }
    }
    
    @MainActor
    func addCoins(_ amount: Int, to profile: UserProfile, context: ModelContext) {
        profile.coins += amount
        self.coinsEarned = amount
        self.showCoinsEarned = true
        try? context.save()
        updateWidgetData(from: profile)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showCoinsEarned = false
        }
    }
    
    @MainActor
    func spendCoins(_ amount: Int, from profile: UserProfile, context: ModelContext) -> Bool {
        guard profile.coins >= amount else { return false }
        profile.coins -= amount
        try? context.save()
        updateWidgetData(from: profile)
        return true
    }

    @MainActor
    func spendXP(_ amount: Int, from profile: UserProfile, context: ModelContext) -> Bool {
        guard profile.totalXP >= amount else { return false }
        profile.totalXP -= amount
        try? context.save()
        updateWidgetData(from: profile)
        return true
    }

    func currentShopTier(for profile: UserProfile) -> ShopXPTier {
        ShopXPTier.forTotalXP(profile.totalXP)
    }

    func totalXPMultiplierPreview(for profile: UserProfile, at date: Date = Date()) -> Double {
        let streakMultiplier = XPRewards.streakMultiplier(for: profile.currentStreak)
        let boosterMultiplier = profile.activeXPBoosters
            .filter { $0.endsAt > date }
            .reduce(1.0) { partial, booster in
                partial * (1.0 + Double(booster.percentBonus) / 100.0)
            }
        return streakMultiplier * min(ShopEconomy.maxEffectiveBoosterMultiplier, boosterMultiplier)
    }

    @MainActor
    private func totalXPMultiplier(for profile: UserProfile, context: ModelContext) -> Double {
        removeExpiredBoosters(for: profile, context: context)
        return totalXPMultiplierPreview(for: profile)
    }

    @MainActor
    private func removeExpiredBoosters(for profile: UserProfile, context: ModelContext) {
        let now = Date()
        let expired = profile.activeXPBoosters.filter { $0.endsAt <= now }
        guard expired.isEmpty == false else { return }

        for booster in expired {
            context.delete(booster)
        }
        profile.activeXPBoosters.removeAll { $0.endsAt <= now }
        try? context.save()
    }

    func streakFreezeCoinCost(currentTokens: Int) -> Int {
        let safeTokenCount = max(0, min(currentTokens, ShopEconomy.maxStreakFreezeTokens))
        let exponential = 45.0 * pow(1.18, Double(safeTokenCount))
        let surcharge = Double(max(0, safeTokenCount - 4) * 5)
        let raw = exponential + surcharge
        return max(10, Int((raw / 5.0).rounded() * 5.0))
    }

    func xpBoosterCoinCost(percent: Int, durationValue: Int, unit: BoosterDurationUnit, activeCount: Int) -> Int {
        let boundedPercent = max(25, min(percent, 300))
        let durationHours = unit == .hours ? max(1, durationValue) : max(1, durationValue) * 24
        let durationComponent = 5.0 * sqrt(Double(durationHours))
        let interaction = 0.08 * Double(boundedPercent) * log(1.0 + Double(durationHours))
        let base = 12.0 + (0.35 * Double(boundedPercent)) + durationComponent + interaction
        let stackFactor = 1.0 + (0.22 * Double(max(0, activeCount)))
        let raw = base * stackFactor
        return max(15, Int((raw / 5.0).rounded() * 5.0))
    }

    func xpBoosterTierRequirement(percent: Int, durationHours: Int) -> ShopXPTier {
        let tierByPercent: ShopXPTier
        switch percent {
        case ...50:
            tierByPercent = .novice
        case ...100:
            tierByPercent = .learner
        case ...150:
            tierByPercent = .scholar
        case ...250:
            tierByPercent = .expert
        default:
            tierByPercent = .master
        }

        if durationHours >= 24 && tierByPercent.rawValue < ShopXPTier.scholar.rawValue {
            return .scholar
        }
        return tierByPercent
    }

    func hybridPrice(forCoinPrice coinPrice: Int, xpShare: Double) -> HybridPrice {
        let clampedShare = max(0, min(xpShare, ShopEconomy.maxXPShare))
        let coins = max(0, Int((Double(coinPrice) * (1.0 - clampedShare)).rounded()))
        let xp = max(0, Int((Double(coinPrice) * clampedShare * ShopEconomy.xpPerCoinRate).rounded()))
        return HybridPrice(coins: coins, xp: xp)
    }

    func canAffordHybridPrice(_ price: HybridPrice, profile: UserProfile) -> Bool {
        profile.coins >= price.coins && profile.totalXP >= price.xp
    }

    @MainActor
    func spendHybridPrice(_ price: HybridPrice, from profile: UserProfile, context: ModelContext) -> Bool {
        guard canAffordHybridPrice(price, profile: profile) else { return false }
        profile.coins -= price.coins
        profile.totalXP -= price.xp
        try? context.save()
        updateWidgetData(from: profile)
        return true
    }

    @MainActor
    func purchaseStreakFreeze(for profile: UserProfile, xpShare: Double, context: ModelContext) -> Bool {
        guard profile.streakFreezeTokens < ShopEconomy.maxStreakFreezeTokens else { return false }
        guard currentShopTier(for: profile).rawValue >= ShopXPTier.learner.rawValue else { return false }

        let coinPrice = streakFreezeCoinCost(currentTokens: profile.streakFreezeTokens)
        let hybrid = hybridPrice(forCoinPrice: coinPrice, xpShare: xpShare)
        guard spendHybridPrice(hybrid, from: profile, context: context) else { return false }

        profile.streakFreezeTokens += 1
        try? context.save()
        updateWidgetData(from: profile)
        return true
    }

    @MainActor
    func purchaseXPBooster(
        percent: Int,
        durationValue: Int,
        durationUnit: BoosterDurationUnit,
        xpShare: Double,
        for profile: UserProfile,
        context: ModelContext
    ) -> Bool {
        removeExpiredBoosters(for: profile, context: context)

        let tier = currentShopTier(for: profile)
        let clampedPercent = max(25, min(percent, 300))
        let durationHours = durationUnit == .hours ? max(1, durationValue) : max(1, durationValue) * 24
        guard clampedPercent <= tier.maxBoosterPercent else { return false }
        let requiredTier = xpBoosterTierRequirement(percent: clampedPercent, durationHours: durationHours)
        guard tier.rawValue >= requiredTier.rawValue else { return false }

        let coinPrice = xpBoosterCoinCost(percent: clampedPercent, durationValue: durationValue, unit: durationUnit, activeCount: profile.activeXPBoosters.count)
        let hybrid = hybridPrice(forCoinPrice: coinPrice, xpShare: xpShare)
        guard spendHybridPrice(hybrid, from: profile, context: context) else { return false }

        let now = Date()
        if let matchingActive = profile.activeXPBoosters.first(where: { $0.percentBonus == clampedPercent && $0.endsAt > now }) {
            matchingActive.endsAt = matchingActive.endsAt.addingTimeInterval(TimeInterval(durationHours * 3600))
        } else {
            let booster = ActiveXPBooster(
                percentBonus: clampedPercent,
                startsAt: now,
                endsAt: now.addingTimeInterval(TimeInterval(durationHours * 3600))
            )
            booster.userProfile = profile
            context.insert(booster)
            profile.activeXPBoosters.append(booster)
        }

        try? context.save()
        updateWidgetData(from: profile)
        return true
    }
    
    // MARK: - Streak management
    
    @MainActor
    func updateStreak(for profile: UserProfile, context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if let lastStudy = profile.lastStudyDate {
            let lastStudyDay = calendar.startOfDay(for: lastStudy)
            let daysDifference = calendar.dateComponents([.day], from: lastStudyDay, to: today).day ?? 0
            
            if daysDifference == 0 {
                // Already studied today; do not change the streak.
                return
            } else if daysDifference == 1 {
                // Consecutive day: increment streak and update longest.
                profile.currentStreak += 1
                if profile.currentStreak > profile.longestStreak {
                    profile.longestStreak = profile.currentStreak
                }
                
                // Daily login bonus for maintaining a streak.
                addXP(XPRewards.dailyLoginBonus + (XPRewards.streakBonus * profile.currentStreak), to: profile, context: context)
                addCoins(CoinRewards.dailyLogin, to: profile, context: context)
                
                // Evaluate streak achievements.
                checkStreakAchievements(profile: profile, context: context)
            } else {
                // Consume freeze tokens for missed days; reset if uncovered days remain.
                let missedDays = max(0, daysDifference - 1)
                let freezeNeeded = missedDays
                let freezeUsed = min(profile.streakFreezeTokens, freezeNeeded)
                profile.streakFreezeTokens -= freezeUsed

                if freezeUsed == freezeNeeded {
                    profile.currentStreak += 1
                    if profile.currentStreak > profile.longestStreak {
                        profile.longestStreak = profile.currentStreak
                    }
                    addXP(XPRewards.dailyLoginBonus + (XPRewards.streakBonus * profile.currentStreak), to: profile, context: context)
                    addCoins(CoinRewards.dailyLogin, to: profile, context: context)
                    checkStreakAchievements(profile: profile, context: context)
                } else {
                    profile.currentStreak = 1
                    addXP(XPRewards.dailyLoginBonus, to: profile, context: context)
                    addCoins(CoinRewards.dailyLogin, to: profile, context: context)
                }
            }
        } else {
            // First-ever study session initializes the streak.
            profile.currentStreak = 1
            addXP(XPRewards.dailyLoginBonus, to: profile, context: context)
            addCoins(CoinRewards.dailyLogin, to: profile, context: context)
            checkStreakAchievements(profile: profile, context: context)
        }
        
        profile.lastStudyDate = Date()
        try? context.save()
        updateWidgetData(from: profile)

        // Refresh reminders to avoid nudging immediately after study.
        Task {
            await NotificationManager.shared.refreshStudyReminders(
                lastStudyDate: profile.lastStudyDate,
                streak: profile.currentStreak
            )
        }
    }
    
    // MARK: - Quiz completion
    
    @MainActor
    func recordQuizCompletion(
        score: Int,
        totalQuestions: Int,
        profile: UserProfile,
        context: ModelContext
    ) {
        // Update quiz counters.
        profile.totalQuestionsCorrect += score
        profile.totalQuizzesTaken += 1
        
        let isPerfect = score == totalQuestions && totalQuestions > 0
        if isPerfect {
            profile.perfectQuizzes += 1
        }
        
        // Calculate XP earned from this quiz.
        var xp = XPRewards.quizCompleted
        xp += score * XPRewards.questionCorrect
        if isPerfect {
            xp += XPRewards.perfectQuiz
        }
        
        addXP(xp, to: profile, context: context)
        
        // Calculate coins earned from this quiz.
        var coins = CoinRewards.quizCompleted
        if isPerfect {
            coins += CoinRewards.perfectQuiz
        }
        addCoins(coins, to: profile, context: context)
        
        // Update the study streak for today.
        updateStreak(for: profile, context: context)
        
        // Evaluate related achievements.
        checkQuestionAchievements(profile: profile, context: context)
        checkPerfectQuizAchievements(profile: profile, context: context)
        
        try? context.save()
    }
    
    // MARK: - Daily Mix completion
    
    /// Returns true when Daily Mix has already been completed today.
    func hasDailyMixCompletedToday(profile: UserProfile) -> Bool {
        guard let lastMixDate = profile.lastDailyMixDate else { return false }
        return Calendar.current.isDateInToday(lastMixDate)
    }
    
    @MainActor
    func recordDailyMixCompletion(
        questionsCorrect: Int,
        flashcardsStudied: Int,
        profile: UserProfile,
        context: ModelContext
    ) {
        // Prevent duplicate rewards on the same day.
        guard !hasDailyMixCompletedToday(profile: profile) else { return }
        
        // Calculate XP earned from Daily Mix.
        var xp = XPRewards.dailyMixBase
        xp += questionsCorrect * XPRewards.dailyMixQuestionCorrect
        xp += flashcardsStudied * XPRewards.dailyMixFlashcard
        
        addXP(xp, to: profile, context: context)
        
        // Calculate coins earned from Daily Mix.
        let coins = CoinRewards.dailyMixBase + (questionsCorrect * CoinRewards.dailyMixQuestionCorrect) + (flashcardsStudied * CoinRewards.dailyMixFlashcard)
        addCoins(coins, to: profile, context: context)
        
        // Daily Mix counts as study activity, so update the streak.
        updateStreak(for: profile, context: context)
        
        // Record completion date to block repeat rewards.
        profile.lastDailyMixDate = Date()
        
        try? context.save()
        updateWidgetData(from: profile)
    }
    
    // MARK: - Flashcard completion
    
    @MainActor
    func recordFlashcardStudied(
        count: Int,
        mastered: Int,
        profile: UserProfile,
        context: ModelContext
    ) {
        profile.totalFlashcardsStudied += count
        
        var xp = count * XPRewards.flashcardStudied
        xp += mastered * XPRewards.flashcardMastered
        
        addXP(xp, to: profile, context: context)
        
        // Update the study streak for today.
        updateStreak(for: profile, context: context)
        
        // Evaluate flashcard achievements.
        checkFlashcardAchievements(profile: profile, context: context)
        
        try? context.save()
    }
    
    // MARK: - Study-set creation
    
    @MainActor
    func recordStudySetCreated(profile: UserProfile, context: ModelContext) {
        profile.totalStudySets += 1
        
        addXP(XPRewards.studySetCreated, to: profile, context: context)
        addCoins(CoinRewards.studySetCreated, to: profile, context: context)
        
        // Update the study streak for today.
        updateStreak(for: profile, context: context)
        
        // Evaluate study-set achievements.
        checkStudySetAchievements(profile: profile, context: context)
        
        try? context.save()
    }
    
    // MARK: - Achievement checks
    
    @MainActor
    private func checkQuestionAchievements(profile: UserProfile, context: ModelContext) {
        let milestones: [(Int, AchievementType)] = [
            (5, .questions5),
            (10, .questions10),
            (50, .questions50),
            (100, .questions100),
            (500, .questions500),
            (1000, .questions1000)
        ]
        
        for (threshold, achievement) in milestones {
            if profile.totalQuestionsCorrect >= threshold {
                unlockAchievement(achievement, for: profile, context: context)
            }
        }
    }
    
    @MainActor
    private func checkStreakAchievements(profile: UserProfile, context: ModelContext) {
        let milestones: [(Int, AchievementType)] = [
            (1, .streak1),
            (7, .streak7),
            (14, .streak14),
            (31, .streak31),
            (100, .streak100),
            (365, .streak365)
        ]
        
        for (threshold, achievement) in milestones {
            if profile.currentStreak >= threshold {
                unlockAchievement(achievement, for: profile, context: context)
            }
        }
    }
    
    @MainActor
    private func checkStudySetAchievements(profile: UserProfile, context: ModelContext) {
        let milestones: [(Int, AchievementType)] = [
            (1, .studySets1),
            (5, .studySets5),
            (10, .studySets10),
            (25, .studySets25),
            (50, .studySets50)
        ]
        
        for (threshold, achievement) in milestones {
            if profile.totalStudySets >= threshold {
                unlockAchievement(achievement, for: profile, context: context)
            }
        }
    }
    
    @MainActor
    private func checkFlashcardAchievements(profile: UserProfile, context: ModelContext) {
        let milestones: [(Int, AchievementType)] = [
            (25, .flashcards25),
            (100, .flashcards100),
            (500, .flashcards500),
            (1000, .flashcards1000)
        ]
        
        for (threshold, achievement) in milestones {
            if profile.totalFlashcardsStudied >= threshold {
                unlockAchievement(achievement, for: profile, context: context)
            }
        }
    }
    
    @MainActor
    private func checkPerfectQuizAchievements(profile: UserProfile, context: ModelContext) {
        let milestones: [(Int, AchievementType)] = [
            (1, .perfectQuiz1),
            (5, .perfectQuiz5),
            (10, .perfectQuiz10),
            (25, .perfectQuiz25)
        ]
        
        for (threshold, achievement) in milestones {
            if profile.perfectQuizzes >= threshold {
                unlockAchievement(achievement, for: profile, context: context)
            }
        }
    }
    
    @MainActor
    private func checkLevelAchievements(profile: UserProfile, context: ModelContext) {
        let milestones: [(Int, AchievementType)] = [
            (5, .level5),
            (10, .level10),
            (25, .level25),
            (50, .level50),
            (75, .level75)
        ]
        
        for (threshold, achievement) in milestones {
            if profile.level >= threshold {
                unlockAchievement(achievement, for: profile, context: context)
            }
        }
    }
    
    // MARK: - Achievement unlocking
    
    @MainActor
    private func unlockAchievement(_ type: AchievementType, for profile: UserProfile, context: ModelContext) {
        // Skip if the achievement is already unlocked.
        if profile.achievements.contains(where: { $0.type == type.rawValue }) {
            return
        }
        
        // Create and persist the unlocked achievement.
        let achievement = Achievement(type: type)
        achievement.userProfile = profile
        context.insert(achievement)
        
        // Award XP and coins immediately.
        profile.totalXP += type.xpReward
        profile.coins += type.coinReward
        
        try? context.save()
        
        // Show the achievement banner.
        self.unlockedAchievement = type
        self.showAchievementUnlocked = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.showAchievementUnlocked = false
        }
    }
    
    // MARK: - Shop functions

    @MainActor
    func activeBoosters(for profile: UserProfile, context: ModelContext) -> [ActiveXPBooster] {
        removeExpiredBoosters(for: profile, context: context)
        return profile.activeXPBoosters.sorted { $0.endsAt < $1.endsAt }
    }
    
    @MainActor
    func purchaseAvatar(_ avatar: AvatarItem, for profile: UserProfile, context: ModelContext) -> Bool {
        // Prevent purchasing duplicates.
        if profile.unlockedItems.contains(where: { $0.itemId == avatar.id && $0.itemType == "avatar" }) {
            return false
        }
        
        // Enforce level requirement.
        guard profile.level >= avatar.requiredLevel else { return false }
        
        // Ensure sufficient coin balance.
        guard spendCoins(avatar.cost, from: profile, context: context) else { return false }
        
        // Record the purchase in unlocked items.
        let item = UnlockedItem(itemId: avatar.id, itemType: "avatar")
        item.userProfile = profile
        context.insert(item)
        
        try? context.save()
        return true
    }

    @MainActor
    func purchaseAvatar(_ avatar: AvatarItem, xpShare: Double, for profile: UserProfile, context: ModelContext) -> Bool {
        if profile.unlockedItems.contains(where: { $0.itemId == avatar.id && $0.itemType == "avatar" }) {
            return false
        }

        guard profile.level >= avatar.requiredLevel else { return false }
        let price = hybridPrice(forCoinPrice: avatar.cost, xpShare: xpShare)
        guard spendHybridPrice(price, from: profile, context: context) else { return false }

        let item = UnlockedItem(itemId: avatar.id, itemType: "avatar")
        item.userProfile = profile
        context.insert(item)

        try? context.save()
        return true
    }
    
    @MainActor
    func purchaseTheme(_ theme: ThemeItem, for profile: UserProfile, context: ModelContext) -> Bool {
        // Prevent purchasing duplicates.
        if profile.unlockedItems.contains(where: { $0.itemId == theme.id && $0.itemType == "theme" }) {
            return false
        }
        
        // Enforce level requirement.
        guard profile.level >= theme.requiredLevel else { return false }
        
        // Ensure sufficient coin balance.
        guard spendCoins(theme.cost, from: profile, context: context) else { return false }
        
        // Record the purchase in unlocked items.
        let item = UnlockedItem(itemId: theme.id, itemType: "theme")
        item.userProfile = profile
        context.insert(item)
        
        try? context.save()
        return true
    }

    @MainActor
    func purchaseTheme(_ theme: ThemeItem, xpShare: Double, for profile: UserProfile, context: ModelContext) -> Bool {
        if profile.unlockedItems.contains(where: { $0.itemId == theme.id && $0.itemType == "theme" }) {
            return false
        }

        guard profile.level >= theme.requiredLevel else { return false }
        let price = hybridPrice(forCoinPrice: theme.cost, xpShare: xpShare)
        guard spendHybridPrice(price, from: profile, context: context) else { return false }

        let item = UnlockedItem(itemId: theme.id, itemType: "theme")
        item.userProfile = profile
        context.insert(item)

        try? context.save()
        return true
    }
    
    @MainActor
    func selectAvatar(_ avatarId: String, for profile: UserProfile, context: ModelContext) -> Bool {
        // Verify ownership; default avatar is always owned.
        let isOwned = avatarId == "default_avatar" ||
            profile.unlockedItems.contains(where: { $0.itemId == avatarId && $0.itemType == "avatar" })
        
        guard isOwned else { return false }
        
        profile.selectedAvatarId = avatarId
        try? context.save()
        return true
    }
    
    @MainActor
    func selectTheme(_ themeId: String, for profile: UserProfile, context: ModelContext) -> Bool {
        // Verify ownership; default theme is always owned.
        let isOwned = themeId == "default_theme" ||
            profile.unlockedItems.contains(where: { $0.itemId == themeId && $0.itemType == "theme" })
        
        guard isOwned else { return false }
        
        profile.selectedThemeId = themeId
        try? context.save()
        
        // Apply the new theme immediately.
        ThemeManager.shared.updateTheme(for: themeId)
        
        return true
    }
    
    func isItemOwned(_ itemId: String, itemType: String, profile: UserProfile) -> Bool {
        if itemType == "avatar" && itemId == "default_avatar" { return true }
        if itemType == "theme" && itemId == "default_theme" { return true }
        return profile.unlockedItems.contains(where: { $0.itemId == itemId && $0.itemType == itemType })
    }
}

// MARK: - Reward and notification views

struct AchievementUnlockedView: View {
    let achievement: AchievementType
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: achievement.icon)
                .font(.title)
                .foregroundColor(.yellow)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(achievement.title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text("+\(achievement.xpReward)")
                        .font(.caption.bold())
                    Text("XP")
                        .font(.caption2)
                }
                .foregroundColor(themeManager.primaryColor)
                
                HStack(spacing: 4) {
                    Text("+\(achievement.coinReward)")
                        .font(.caption.bold())
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption2)
                }
                .foregroundColor(.yellow)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}

struct XPGainedView: View {
    let xp: Int
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundColor(themeManager.primaryColor)
            Text("+\(xp) XP")
                .font(.headline)
                .foregroundColor(themeManager.primaryColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(themeManager.primaryColor.opacity(0.2))
        )
    }
}

struct LevelUpView: View {
    let level: Int
    
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 60))
                .foregroundColor(.yellow)
            
            Text("Level Up!")
                .font(.largeTitle.bold())
            
            Text("You reached Level \(level)")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .padding(30)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        )
    }
}

struct CoinsEarnedView: View {
    let coins: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundColor(.yellow)
            Text("+\(coins)")
                .font(.headline)
                .foregroundColor(.yellow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.yellow.opacity(0.2))
        )
    }
}
