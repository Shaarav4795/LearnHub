import Foundation
import SwiftData

// MARK: - Achievement definitions

enum AchievementType: String, Codable, CaseIterable {
    // Question-correct milestones.
    case questions5 = "questions_5"
    case questions10 = "questions_10"
    case questions50 = "questions_50"
    case questions100 = "questions_100"
    case questions500 = "questions_500"
    case questions1000 = "questions_1000"
    
    // Streak milestones.
    case streak1 = "streak_1"
    case streak7 = "streak_7"
    case streak14 = "streak_14"
    case streak31 = "streak_31"
    case streak100 = "streak_100"
    case streak365 = "streak_365"
    
    // Study-set milestones.
    case studySets1 = "study_sets_1"
    case studySets5 = "study_sets_5"
    case studySets10 = "study_sets_10"
    case studySets25 = "study_sets_25"
    case studySets50 = "study_sets_50"
    
    // Flashcard milestones.
    case flashcards25 = "flashcards_25"
    case flashcards100 = "flashcards_100"
    case flashcards500 = "flashcards_500"
    case flashcards1000 = "flashcards_1000"
    
    // Perfect-quiz milestones.
    case perfectQuiz1 = "perfect_quiz_1"
    case perfectQuiz5 = "perfect_quiz_5"
    case perfectQuiz10 = "perfect_quiz_10"
    case perfectQuiz25 = "perfect_quiz_25"
    
    // Level milestones.
    case level5 = "level_5"
    case level10 = "level_10"
    case level25 = "level_25"
    case level50 = "level_50"
    case level75 = "level_75"
    
    var title: String {
        switch self {
        case .questions5: return "First Steps"
        case .questions10: return "Getting Started"
        case .questions50: return "Quiz Enthusiast"
        case .questions100: return "Quiz Master"
        case .questions500: return "Quiz Legend"
        case .questions1000: return "Quiz Immortal"
        case .streak1: return "Day One"
        case .streak7: return "Week Warrior"
        case .streak14: return "Two Week Triumph"
        case .streak31: return "Monthly Master"
        case .streak100: return "Century Streak"
        case .streak365: return "Year of Learning"
        case .studySets1: return "Study Starter"
        case .studySets5: return "Knowledge Seeker"
        case .studySets10: return "Study Scholar"
        case .studySets25: return "Study Champion"
        case .studySets50: return "Library Builder"
        case .flashcards25: return "Card Collector"
        case .flashcards100: return "Flash Master"
        case .flashcards500: return "Memory King"
        case .flashcards1000: return "Memory Titan"
        case .perfectQuiz1: return "Perfect Score"
        case .perfectQuiz5: return "Precision Player"
        case .perfectQuiz10: return "Flawless Scholar"
        case .perfectQuiz25: return "Perfectionist"
        case .level5: return "Rising Star"
        case .level10: return "Dedicated Learner"
        case .level25: return "Knowledge Expert"
        case .level50: return "Ultimate Scholar"
        case .level75: return "Ascended Scholar"
        }
    }
    
    var description: String {
        switch self {
        case .questions5: return "Answer 5 questions correctly"
        case .questions10: return "Answer 10 questions correctly"
        case .questions50: return "Answer 50 questions correctly"
        case .questions100: return "Answer 100 questions correctly"
        case .questions500: return "Answer 500 questions correctly"
        case .questions1000: return "Answer 1000 questions correctly"
        case .streak1: return "Study for 1 day"
        case .streak7: return "Maintain a 7-day study streak"
        case .streak14: return "Maintain a 14-day study streak"
        case .streak31: return "Maintain a 31-day study streak"
        case .streak100: return "Maintain a 100-day study streak"
        case .streak365: return "Maintain a 365-day study streak"
        case .studySets1: return "Create your first study set"
        case .studySets5: return "Create 5 study sets"
        case .studySets10: return "Create 10 study sets"
        case .studySets25: return "Create 25 study sets"
        case .studySets50: return "Create 50 study sets"
        case .flashcards25: return "Study 25 flashcards"
        case .flashcards100: return "Study 100 flashcards"
        case .flashcards500: return "Study 500 flashcards"
        case .flashcards1000: return "Study 1000 flashcards"
        case .perfectQuiz1: return "Get a perfect score on a quiz"
        case .perfectQuiz5: return "Get 5 perfect quiz scores"
        case .perfectQuiz10: return "Get 10 perfect quiz scores"
        case .perfectQuiz25: return "Get 25 perfect quiz scores"
        case .level5: return "Reach level 5"
        case .level10: return "Reach level 10"
        case .level25: return "Reach level 25"
        case .level50: return "Reach level 50"
        case .level75: return "Reach level 75"
        }
    }
    
    var icon: String {
        switch self {
        case .questions5, .questions10, .questions50, .questions100, .questions500, .questions1000:
            return "checkmark.circle.fill"
        case .streak1, .streak7, .streak14, .streak31, .streak100, .streak365:
            return "flame.fill"
        case .studySets1, .studySets5, .studySets10, .studySets25, .studySets50:
            return "book.fill"
        case .flashcards25, .flashcards100, .flashcards500, .flashcards1000:
            return "rectangle.stack.fill"
        case .perfectQuiz1, .perfectQuiz5, .perfectQuiz10, .perfectQuiz25:
            return "star.fill"
        case .level5, .level10, .level25, .level50, .level75:
            return "trophy.fill"
        }
    }
    
    var color: String {
        switch self {
        case .questions5, .questions10: return "green"
        case .questions50, .questions100, .questions500, .questions1000: return "blue"
        case .streak1, .streak7: return "orange"
        case .streak14, .streak31, .streak100, .streak365: return "red"
        case .studySets1, .studySets5, .studySets10, .studySets25, .studySets50: return "purple"
        case .flashcards25, .flashcards100, .flashcards500, .flashcards1000: return "cyan"
        case .perfectQuiz1, .perfectQuiz5, .perfectQuiz10, .perfectQuiz25: return "yellow"
        case .level5, .level10, .level25, .level50, .level75: return "gold"
        }
    }
    
    var requirement: Int {
        switch self {
        case .questions5: return 5
        case .questions10: return 10
        case .questions50: return 50
        case .questions100: return 100
        case .questions500: return 500
        case .questions1000: return 1000
        case .streak1: return 1
        case .streak7: return 7
        case .streak14: return 14
        case .streak31: return 31
        case .streak100: return 100
        case .streak365: return 365
        case .studySets1: return 1
        case .studySets5: return 5
        case .studySets10: return 10
        case .studySets25: return 25
        case .studySets50: return 50
        case .flashcards25: return 25
        case .flashcards100: return 100
        case .flashcards500: return 500
        case .flashcards1000: return 1000
        case .perfectQuiz1: return 1
        case .perfectQuiz5: return 5
        case .perfectQuiz10: return 10
        case .perfectQuiz25: return 25
        case .level5: return 5
        case .level10: return 10
        case .level25: return 25
        case .level50: return 50
        case .level75: return 75
        }
    }
    
    var xpReward: Int {
        switch self {
        case .questions5: return 50
        case .questions10: return 100
        case .questions50: return 250
        case .questions100: return 500
        case .questions500: return 1000
        case .questions1000: return 1800
        case .streak1: return 25
        case .streak7: return 200
        case .streak14: return 400
        case .streak31: return 800
        case .streak100: return 1800
        case .streak365: return 5000
        case .studySets1: return 50
        case .studySets5: return 150
        case .studySets10: return 300
        case .studySets25: return 750
        case .studySets50: return 1400
        case .flashcards25: return 75
        case .flashcards100: return 200
        case .flashcards500: return 500
        case .flashcards1000: return 1000
        case .perfectQuiz1: return 100
        case .perfectQuiz5: return 300
        case .perfectQuiz10: return 600
        case .perfectQuiz25: return 1500
        case .level5: return 250
        case .level10: return 500
        case .level25: return 1000
        case .level50: return 2500
        case .level75: return 4000
        }
    }
    
    var coinReward: Int {
        switch self {
        case .questions5: return 10
        case .questions10: return 25
        case .questions50: return 50
        case .questions100: return 100
        case .questions500: return 250
        case .questions1000: return 450
        case .streak1: return 5
        case .streak7: return 50
        case .streak14: return 100
        case .streak31: return 200
        case .streak100: return 400
        case .streak365: return 1000
        case .studySets1: return 10
        case .studySets5: return 30
        case .studySets10: return 60
        case .studySets25: return 150
        case .studySets50: return 300
        case .flashcards25: return 15
        case .flashcards100: return 40
        case .flashcards500: return 100
        case .flashcards1000: return 220
        case .perfectQuiz1: return 25
        case .perfectQuiz5: return 75
        case .perfectQuiz10: return 150
        case .perfectQuiz25: return 350
        case .level5: return 50
        case .level10: return 100
        case .level25: return 250
        case .level50: return 500
        case .level75: return 800
        }
    }
}

// MARK: - SwiftData models

@Model
final class UserProfile {
    var id: UUID
    var username: String
    var totalXP: Int
    var coins: Int
    var currentStreak: Int
    var longestStreak: Int
    var lastStudyDate: Date?
    var lastDailyMixDate: Date?
    var totalQuestionsCorrect: Int
    var totalQuizzesTaken: Int
    var perfectQuizzes: Int
    var totalFlashcardsStudied: Int
    var totalStudySets: Int
    var selectedAvatarId: String
    var selectedThemeId: String
    var streakFreezeTokens: Int
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade) var achievements: [Achievement] = []
    @Relationship(deleteRule: .cascade) var unlockedItems: [UnlockedItem] = []
    @Relationship(deleteRule: .cascade) var activeXPBoosters: [ActiveXPBooster] = []
    
    init(username: String = "Student") {
        self.id = UUID()
        self.username = username
        self.totalXP = 0
        self.coins = 100 // Starting coin balance.
        self.currentStreak = 0
        self.longestStreak = 0
        self.lastStudyDate = nil
        self.lastDailyMixDate = nil
        self.totalQuestionsCorrect = 0
        self.totalQuizzesTaken = 0
        self.perfectQuizzes = 0
        self.totalFlashcardsStudied = 0
        self.totalStudySets = 0
        self.selectedAvatarId = "default_avatar"
        self.selectedThemeId = "default_theme"
        self.streakFreezeTokens = 0
        self.createdAt = Date()
    }
    
    // MARK: - Level calculations
    
    // Base XP for level 1→2, scales by 1.1x per level.
    private static let baseXP: Double = 100
    private static let scaleFactor: Double = 1.1
    
    // Cumulative XP required to reach a given level.
    private static func cumulativeXP(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        // Geometric series sum for the XP curve.
        let sum = baseXP * (pow(scaleFactor, Double(level - 1)) - 1) / (scaleFactor - 1)
        return Int(sum)
    }
    
    var level: Int {
        // Compute level from total XP using a binary search.
        var low = 1
        var high = 100
        while low < high {
            let mid = (low + high + 1) / 2
            if UserProfile.cumulativeXP(forLevel: mid) <= totalXP {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
    
    var xpForCurrentLevel: Int {
        // XP threshold for the current level.
        return UserProfile.cumulativeXP(forLevel: level)
    }
    
    var xpForNextLevel: Int {
        // XP threshold for the next level.
        return UserProfile.cumulativeXP(forLevel: level + 1)
    }
    
    var xpProgress: Double {
        let current = totalXP - xpForCurrentLevel
        let needed = xpForNextLevel - xpForCurrentLevel
        guard needed > 0 else { return 0 }
        return min(1.0, max(0.0, Double(current) / Double(needed)))
    }
    
    var xpToNextLevel: Int {
        return max(0, xpForNextLevel - totalXP)
    }
}

@Model
final class ActiveXPBooster {
    var id: UUID
    var percentBonus: Int
    var startsAt: Date
    var endsAt: Date

    var userProfile: UserProfile?

    init(percentBonus: Int, startsAt: Date, endsAt: Date) {
        self.id = UUID()
        self.percentBonus = percentBonus
        self.startsAt = startsAt
        self.endsAt = endsAt
    }
}

@Model
final class Achievement {
    var id: UUID
    var type: String // `AchievementType.rawValue`
    var unlockedAt: Date
    var claimed: Bool
    
    var userProfile: UserProfile?
    
    init(type: AchievementType) {
        self.id = UUID()
        self.type = type.rawValue
        self.unlockedAt = Date()
        self.claimed = false
    }
    
    var achievementType: AchievementType? {
        AchievementType(rawValue: type)
    }
}

@Model
final class UnlockedItem {
    var id: UUID
    var itemId: String
    var itemType: String // "avatar" or "theme"
    var unlockedAt: Date
    
    var userProfile: UserProfile?
    
    init(itemId: String, itemType: String) {
        self.id = UUID()
        self.itemId = itemId
        self.itemType = itemType
        self.unlockedAt = Date()
    }
}

// MARK: - Avatar and theme definitions

struct AvatarItem: Identifiable, Hashable {
    let id: String
    let name: String
    let imageName: String
    let cost: Int
    let requiredLevel: Int
    let description: String
    
    static let allAvatars: [AvatarItem] = [
        AvatarItem(id: "default_avatar", name: "Student", imageName: "default_avatar", cost: 0, requiredLevel: 1, description: "The classic student avatar"),
        AvatarItem(id: "scholar", name: "Scholar", imageName: "scholar", cost: 50, requiredLevel: 2, description: "A dedicated learner"),
        AvatarItem(id: "scientist", name: "Scientist", imageName: "scientist", cost: 100, requiredLevel: 3, description: "Curious about everything"),
        AvatarItem(id: "astronaut", name: "Astronaut", imageName: "astronaut", cost: 150, requiredLevel: 5, description: "Reaching for the stars"),
        AvatarItem(id: "wizard", name: "Wizard", imageName: "wizard", cost: 200, requiredLevel: 7, description: "Master of knowledge"),
        AvatarItem(id: "robot", name: "Robot", imageName: "robot", cost: 300, requiredLevel: 10, description: "Learning machine"),
        AvatarItem(id: "ninja", name: "Ninja", imageName: "ninja", cost: 350, requiredLevel: 12, description: "Silent but smart"),
        AvatarItem(id: "superhero", name: "Superhero", imageName: "superhero", cost: 400, requiredLevel: 15, description: "Study superpower!"),
        AvatarItem(id: "alien", name: "Alien", imageName: "alien", cost: 500, requiredLevel: 20, description: "Out of this world"),
        AvatarItem(id: "dragon", name: "Dragon", imageName: "dragon", cost: 750, requiredLevel: 25, description: "Legendary learner"),
        AvatarItem(id: "phoenix", name: "Phoenix", imageName: "phoenix", cost: 1000, requiredLevel: 30, description: "Rise from challenges"),
        AvatarItem(id: "crown", name: "Royalty", imageName: "crown", cost: 1500, requiredLevel: 40, description: "Ruler of knowledge"),
    ]
    
    static func avatar(for id: String) -> AvatarItem? {
        allAvatars.first { $0.id == id }
    }
}

struct ThemeItem: Identifiable, Hashable {
    let id: String
    let name: String
    let primaryColor: String
    let secondaryColor: String
    let cost: Int
    let requiredLevel: Int
    let description: String
    
    static let allThemes: [ThemeItem] = [
        ThemeItem(id: "default_theme", name: "Default", primaryColor: "blue", secondaryColor: "cyan", cost: 0, requiredLevel: 1, description: "Classic LearnHub"),
        ThemeItem(id: "ocean", name: "Ocean", primaryColor: "navy", secondaryColor: "teal", cost: 75, requiredLevel: 3, description: "Deep sea depths"),
        ThemeItem(id: "sunset", name: "Sunset", primaryColor: "orange", secondaryColor: "pink", cost: 100, requiredLevel: 5, description: "Warm evening glow"),
        ThemeItem(id: "forest", name: "Forest", primaryColor: "green", secondaryColor: "mint", cost: 125, requiredLevel: 7, description: "Nature's calm"),
        ThemeItem(id: "galaxy", name: "Galaxy", primaryColor: "purple", secondaryColor: "indigo", cost: 200, requiredLevel: 10, description: "Cosmic wonder"),
        ThemeItem(id: "rose", name: "Rose Gold", primaryColor: "pink", secondaryColor: "red", cost: 250, requiredLevel: 15, description: "Elegant pink"),
        ThemeItem(id: "midnight", name: "Midnight", primaryColor: "charcoal", secondaryColor: "slate", cost: 300, requiredLevel: 20, description: "Sleek dark mode"),
        ThemeItem(id: "golden", name: "Golden Hour", primaryColor: "yellow", secondaryColor: "orange", cost: 400, requiredLevel: 25, description: "Shining bright"),
        ThemeItem(id: "aurora", name: "Aurora", primaryColor: "magenta", secondaryColor: "violet", cost: 500, requiredLevel: 30, description: "Northern lights magic"),
        ThemeItem(id: "rainbow", name: "Rainbow", primaryColor: "rainbow", secondaryColor: "rainbow", cost: 750, requiredLevel: 50, description: "All the colors!"),
    ]
    
    static func theme(for id: String) -> ThemeItem? {
        allThemes.first { $0.id == id }
    }
}

// MARK: - XP rewards configuration

struct XPRewards {
    // Tuned to match the higher per-level XP curve.
    static let questionCorrect = 15
    static let quizCompleted = 40
    static let perfectQuiz = 75 // Bonus for a perfect quiz.
    static let flashcardStudied = 8
    static let flashcardMastered = 20
    static let studySetCreated = 1000 // was 45
    static let summaryRead = 15
    static let dailyLoginBonus = 30
    static let streakBonus: Int = 8 // Per day of streak.
    
    // Daily Mix rewards are intentionally modest.
    static let dailyMixBase = 25
    static let dailyMixQuestionCorrect = 8
    static let dailyMixFlashcard = 5
    
    static func streakMultiplier(for streak: Int) -> Double {
        // Streak multiplier boosts XP as streaks grow.
        switch streak {
        case 0...6: return 1.0
        case 7...13: return 1.1
        case 14...30: return 1.25
        case 31...99: return 1.5
        default: return 2.0
        }
    }
}

// MARK: - Coin rewards configuration

struct CoinRewards {
    // Coin rewards track the XP economy changes.
    static let quizCompleted = 8
    static let perfectQuiz = 25
    static let studySetCreated = 1000 //was 15
    static let dailyLogin = 8
    static let streakBonus = 10 // Per day of streak (on milestones).
    
    // Daily Mix coin rewards.
    static let dailyMixBase = 10
    static let dailyMixQuestionCorrect = 3
    static let dailyMixFlashcard = 2
}

enum ShopXPTier: Int, CaseIterable {
    case novice = 0
    case learner = 1
    case scholar = 2
    case expert = 3
    case master = 4

    var title: String {
        switch self {
        case .novice: return "Novice"
        case .learner: return "Learner"
        case .scholar: return "Scholar"
        case .expert: return "Expert"
        case .master: return "Master"
        }
    }

    var minXP: Int {
        switch self {
        case .novice: return 0
        case .learner: return 600
        case .scholar: return 1800
        case .expert: return 5000
        case .master: return 12000
        }
    }

    var maxBoosterPercent: Int {
        switch self {
        case .novice: return 50
        case .learner: return 100
        case .scholar: return 150
        case .expert: return 250
        case .master: return 300
        }
    }

    static func forTotalXP(_ xp: Int) -> ShopXPTier {
        if xp >= ShopXPTier.master.minXP { return .master }
        if xp >= ShopXPTier.expert.minXP { return .expert }
        if xp >= ShopXPTier.scholar.minXP { return .scholar }
        if xp >= ShopXPTier.learner.minXP { return .learner }
        return .novice
    }
}

enum ShopEconomy {
    static let xpPerCoinRate: Double = 12
    static let maxXPShare: Double = 0.5
    static let maxStreakFreezeTokens: Int = 10
    static let maxEffectiveBoosterMultiplier: Double = 6
}
