import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let hasAskedKey = "learnhub.notifications.hasAsked"
    private init() {}
    
    private enum Identifier {
        static let predictiveOne = "study_reminder_predictive_1"
        static let predictiveTwo = "study_reminder_predictive_2"
        static let predictiveThree = "study_reminder_predictive_3"
        static let snooze = "study_reminder_snooze"
        static let legacyMorning = "study_reminder_morning"
        static let legacyEvening = "study_reminder_evening"
        static let legacyCatchUp = "study_reminder_catchup"

        static let managed = [
            predictiveOne,
            predictiveTwo,
            predictiveThree,
            snooze,
            legacyMorning,
            legacyEvening,
            legacyCatchUp
        ]
    }

    private enum CategoryIdentifier {
        static let predictiveReminder = "learnhub.predictive.reminder"
    }

    private enum ActionIdentifier {
        static let snoozeOneHour = "learnhub.reminder.snooze.1h"
        static let snoozeThreeHours = "learnhub.reminder.snooze.3h"
        static let snoozeTomorrow = "learnhub.reminder.snooze.tomorrow"
    }

    private enum DefaultsKeys {
        static let studyHourHistory = "notifications.smart.studyHourHistory"
        static let quizAccuracyHistory = "notifications.smart.quizAccuracyHistory"
        static let snoozeDateStamp = "notifications.smart.snoozeDateStamp"
        static let snoozeCount = "notifications.smart.snoozeCount"
    }
    
    enum ReminderAnchor {
        case morning
        case evening
        case catchUp
    }

    struct PredictiveReminderContext {
        let lastStudyDate: Date?
        let streak: Int
        let totalQuestionsCorrect: Int
        let totalQuizzesTaken: Int
    }
    
    func bootstrapNotifications(for profile: UserProfile) async {
        configureNotificationCategories()

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            // Ask once; if declined, avoid repeated prompts.
            if defaults.bool(forKey: hasAskedKey) == false {
                defaults.set(true, forKey: hasAskedKey)
                let granted = await requestAuthorization()
                if granted {
                    await refreshPredictiveReminders(
                        context: PredictiveReminderContext(
                            lastStudyDate: profile.lastStudyDate,
                            streak: profile.currentStreak,
                            totalQuestionsCorrect: profile.totalQuestionsCorrect,
                            totalQuizzesTaken: profile.totalQuizzesTaken
                        )
                    )
                }
            }
        case .authorized, .provisional, .ephemeral:
            await refreshPredictiveReminders(
                context: PredictiveReminderContext(
                    lastStudyDate: profile.lastStudyDate,
                    streak: profile.currentStreak,
                    totalQuestionsCorrect: profile.totalQuestionsCorrect,
                    totalQuizzesTaken: profile.totalQuizzesTaken
                )
            )
        default:
            break
        }
    }

    func refreshPredictiveReminders(context: PredictiveReminderContext) async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }

        guard smartRemindersEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: Identifier.managed)
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: Identifier.managed)

        let now = Date()
        let risk = forgetfulnessRisk(for: context, now: now)
        let dates = predictedReminderDates(for: context, risk: risk, now: now)

        for (index, date) in dates.prefix(3).enumerated() {
            let id: String
            switch index {
            case 0: id = Identifier.predictiveOne
            case 1: id = Identifier.predictiveTwo
            default: id = Identifier.predictiveThree
            }

            let content = makePredictiveContent(index: index, risk: risk, streak: context.streak)
            scheduleNotification(id: id, fireDate: date, content: content)
        }
    }
    
    func refreshStudyReminders(lastStudyDate: Date?, streak: Int) async {
        await refreshPredictiveReminders(
            context: PredictiveReminderContext(
                lastStudyDate: lastStudyDate,
                streak: streak,
                totalQuestionsCorrect: 0,
                totalQuizzesTaken: 0
            )
        )
    }

    func recordStudyActivity(at date: Date) {
        let hour = Calendar.current.component(.hour, from: date)
        var history = defaults.array(forKey: DefaultsKeys.studyHourHistory) as? [Int] ?? []
        history.append(hour)
        if history.count > 40 {
            history.removeFirst(history.count - 40)
        }
        defaults.set(history, forKey: DefaultsKeys.studyHourHistory)
    }

    func recordQuizPerformance(score: Int, totalQuestions: Int) {
        guard totalQuestions > 0 else { return }
        let accuracy = max(0.0, min(1.0, Double(score) / Double(totalQuestions)))
        var history = defaults.array(forKey: DefaultsKeys.quizAccuracyHistory) as? [Double] ?? []
        history.append(accuracy)
        if history.count > 20 {
            history.removeFirst(history.count - 20)
        }
        defaults.set(history, forKey: DefaultsKeys.quizAccuracyHistory)
    }

    func handleNotificationResponse(_ response: UNNotificationResponse) {
        let action = response.actionIdentifier
        guard shouldAllowSnoozeAction() else { return }

        if action == ActionIdentifier.snoozeOneHour {
            scheduleSnooze(hours: 1)
        } else if action == ActionIdentifier.snoozeThreeHours {
            scheduleSnooze(hours: 3)
        } else if action == ActionIdentifier.snoozeTomorrow {
            scheduleSnoozeTomorrowMorning()
        }
    }
    
    // MARK: - Helpers
    
    private func requestAuthorization() async -> Bool {
        do {
            // Skip badge permission to avoid automatic app icon badges.
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    private func configureNotificationCategories() {
        let oneHour = UNNotificationAction(
            identifier: ActionIdentifier.snoozeOneHour,
            title: "Snooze 1h",
            options: []
        )
        let threeHours = UNNotificationAction(
            identifier: ActionIdentifier.snoozeThreeHours,
            title: "Snooze 3h",
            options: []
        )
        let tomorrow = UNNotificationAction(
            identifier: ActionIdentifier.snoozeTomorrow,
            title: "Tomorrow 8AM",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: CategoryIdentifier.predictiveReminder,
            actions: [oneHour, threeHours, tomorrow],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([category])
    }

    private var smartRemindersEnabled: Bool {
        if defaults.object(forKey: ModelSettings.Keys.smartRemindersEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: ModelSettings.Keys.smartRemindersEnabled)
    }

    private var reminderSensitivity: ReminderSensitivity {
        let raw = defaults.string(forKey: ModelSettings.Keys.smartReminderSensitivity)
        return ReminderSensitivity(rawValue: raw ?? "") ?? .medium
    }

    private func forgetfulnessRisk(for context: PredictiveReminderContext, now: Date) -> Double {
        let recencyRisk: Double = {
            guard let lastStudy = context.lastStudyDate else { return 0.8 }
            let hours = max(0, now.timeIntervalSince(lastStudy) / 3600)
            return min(1.0, hours / 36.0)
        }()

        let streakRisk: Double = {
            switch context.streak {
            case ..<1: return 0.75
            case 1...2: return 0.55
            case 3...6: return 0.35
            default: return 0.18
            }
        }()

        let performanceRisk: Double = {
            let history = defaults.array(forKey: DefaultsKeys.quizAccuracyHistory) as? [Double] ?? []
            if history.isEmpty {
                guard context.totalQuizzesTaken > 0 else { return 0.35 }
                let estimatedDenominator = Double(max(1, context.totalQuizzesTaken * 5))
                let estimatedAccuracy = min(1.0, max(0.0, Double(context.totalQuestionsCorrect) / estimatedDenominator))
                return 1.0 - estimatedAccuracy
            }
            let avg = history.reduce(0, +) / Double(history.count)
            return 1.0 - avg
        }()

        return min(1.0, max(0.0, (0.5 * recencyRisk) + (0.3 * performanceRisk) + (0.2 * streakRisk)))
    }

    private func predictedReminderDates(for context: PredictiveReminderContext, risk: Double, now: Date) -> [Date] {
        let firstGapHours: Double
        let spacingHours: Double
        let immediateLeadMinutes: Int

        switch reminderSensitivity {
        case .low:
            firstGapHours = 8.0 + ((1.0 - risk) * 12.0)
            spacingHours = 8.0 - (risk * 1.2)
            immediateLeadMinutes = 60
        case .medium:
            firstGapHours = 6.0 + ((1.0 - risk) * 10.0)
            spacingHours = 6.0 - (risk * 1.4)
            immediateLeadMinutes = 45
        case .high:
            firstGapHours = 4.0 + ((1.0 - risk) * 8.0)
            spacingHours = 4.0 - (risk * 1.6)
            immediateLeadMinutes = 30
        }

        let preferredHour = preferredStudyHour()
        var dates: [Date] = []

        var first = context.lastStudyDate?
            .addingTimeInterval(firstGapHours * 3600)
            ?? nextPreferredDate(after: now, preferredHour: preferredHour)

        if first <= now.addingTimeInterval(TimeInterval(immediateLeadMinutes * 60)) {
            first = now.addingTimeInterval(TimeInterval(immediateLeadMinutes * 60))
        }
        first = adjustedForQuietHours(first)
        dates.append(first)

        var second = nextPreferredDate(after: first.addingTimeInterval(3600), preferredHour: preferredHour)
        let minSpacing = TimeInterval(max(3.0, spacingHours) * 3600)
        if second.timeIntervalSince(first) < minSpacing {
            second = adjustedForQuietHours(first.addingTimeInterval(minSpacing))
        }
        dates.append(second)

        let thirdBase = second.addingTimeInterval(minSpacing)
        let third = adjustedForQuietHours(thirdBase)
        dates.append(third)

        return dates
            .filter { $0 > now }
            .prefix(3)
            .map { $0 }
    }

    private func preferredStudyHour() -> Int {
        let history = defaults.array(forKey: DefaultsKeys.studyHourHistory) as? [Int] ?? []
        guard history.isEmpty == false else { return 19 }

        var buckets: [Int: Int] = [:]
        for hour in history {
            buckets[hour, default: 0] += 1
        }
        let bestHour = buckets.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }?.key ?? 19
        return min(22, max(7, bestHour))
    }

    private func nextPreferredDate(after date: Date, preferredHour: Int) -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = preferredHour
        components.minute = Int.random(in: 0...20)
        components.second = 0

        var candidate = calendar.date(from: components) ?? date
        if candidate <= date {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return adjustedForQuietHours(candidate)
    }

    private func adjustedForQuietHours(_ date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        if hour >= 23 {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            return calendar.date(bySettingHour: 7, minute: Int.random(in: 0...15), second: 0, of: nextDay) ?? nextDay
        }
        if hour < 7 {
            return calendar.date(bySettingHour: 7, minute: Int.random(in: 0...15), second: 0, of: date) ?? date
        }
        return date
    }

    private func makePredictiveContent(index: Int, risk: Double, streak: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = CategoryIdentifier.predictiveReminder
        content.sound = .default

        let streakNote: String
        if streak >= 7 {
            streakNote = "Streak \(streak) days strong."
        } else if streak >= 3 {
            streakNote = "You’re on a \(streak)-day streak."
        } else {
            streakNote = "One short session builds momentum."
        }

        if risk >= 0.7 {
            content.title = index == 0 ? "Memory drop predicted soon" : "Quick review keeps knowledge fresh"
            content.body = "A short session now should prevent forgetting. \(streakNote)"
        } else if risk >= 0.4 {
            content.title = index == 0 ? "Good time for a quick review" : "Keep your progress steady"
            content.body = "A focused study block now helps retention. \(streakNote)"
        } else {
            content.title = index == 0 ? "Stay ahead with 10 minutes" : "Light review suggestion"
            content.body = "You’re doing well—small reviews keep it that way. \(streakNote)"
        }

        return content
    }
    
    private func makeContent(anchor: ReminderAnchor, streak: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let streakNote: String
        if streak >= 7 {
            streakNote = "Streak \(streak) days strong. Keep it going!"
        } else if streak >= 3 {
            streakNote = "You are on a \(streak)-day streak."
        } else {
            streakNote = "Today is a good day to build momentum."
        }
        
        switch anchor {
        case .morning:
            content.title = "Plan a 10 minute study block"
            content.body = "Set up one quick session before the day gets busy. \(streakNote)"
        case .evening:
            content.title = "Wrap up with a quick review"
            content.body = "A short set now locks in today’s streak. \(streakNote)"
        case .catchUp:
            content.title = "Still time to study today"
            content.body = "One focused session will keep you on track. \(streakNote)"
        }
        content.sound = .default
        return content
    }
    
    private func nextFireDate(hour: Int, minute: Int, jitterMinutes: Int, from now: Date) -> Date {
        let calendar = Calendar.current
        let jitter = Int.random(in: 0...max(jitterMinutes, 0))
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute + jitter
        components.second = 0
        var candidate = calendar.date(from: components) ?? now
        if candidate <= now {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
    
    private func nextDate(from base: Date, jitterMinutes: Int, now: Date) -> Date {
        let calendar = Calendar.current
        let jitter = Int.random(in: 0...max(jitterMinutes, 0))
        var date = calendar.date(byAdding: .minute, value: jitter, to: base) ?? base
        if date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }
    
    private func scheduleNotification(id: String, fireDate: Date, content: UNMutableNotificationContent) {
        let calendar = Calendar.current
        let triggerDate = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request)
    }

    private func scheduleSnooze(hours: Int) {
        let date = adjustedForQuietHours(Date().addingTimeInterval(TimeInterval(hours * 3600)))
        let content = UNMutableNotificationContent()
        content.title = "Snoozed reminder"
        content.body = "Your next study nudge is ready."
        content.sound = .default
        content.categoryIdentifier = CategoryIdentifier.predictiveReminder
        scheduleNotification(id: Identifier.snooze, fireDate: date, content: content)
    }

    private func scheduleSnoozeTomorrowMorning() {
        let calendar = Calendar.current
        let tomorrowBase = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let date = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrowBase) ?? tomorrowBase

        let content = UNMutableNotificationContent()
        content.title = "Tomorrow’s study reminder"
        content.body = "Start with a quick session and keep your momentum."
        content.sound = .default
        content.categoryIdentifier = CategoryIdentifier.predictiveReminder
        scheduleNotification(id: Identifier.snooze, fireDate: adjustedForQuietHours(date), content: content)
    }

    private func shouldAllowSnoozeAction() -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let storedDate = defaults.object(forKey: DefaultsKeys.snoozeDateStamp) as? Date
        if let storedDate, calendar.isDate(storedDate, inSameDayAs: today) == false {
            defaults.set(today, forKey: DefaultsKeys.snoozeDateStamp)
            defaults.set(0, forKey: DefaultsKeys.snoozeCount)
        } else if storedDate == nil {
            defaults.set(today, forKey: DefaultsKeys.snoozeDateStamp)
            defaults.set(0, forKey: DefaultsKeys.snoozeCount)
        }

        let count = defaults.integer(forKey: DefaultsKeys.snoozeCount)
        guard count < 3 else { return false }
        defaults.set(count + 1, forKey: DefaultsKeys.snoozeCount)
        return true
    }
    
    private func shouldSchedule(target: Date, lastStudy: Date?, buffer: TimeInterval) -> Bool {
        guard let last = lastStudy else { return true }
        return abs(target.timeIntervalSince(last)) > buffer
    }
}
