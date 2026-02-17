import Foundation

enum SpacedReviewRating: Int {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}

struct SpacedReviewInput {
    var now: Date
    var difficulty: Double
    var stability: Double
    var intervalDays: Double
    var repetitions: Int
    var lapses: Int
    var lastReviewedAt: Date?
    var rating: SpacedReviewRating
}

struct SpacedReviewResult {
    var dueDate: Date
    var intervalDays: Double
    var stability: Double
    var difficulty: Double
    var repetitions: Int
    var lapses: Int
    var lastReviewedAt: Date
}

enum SpacedRepetitionScheduler {
    private static let retention: Double = 0.9
    private static let decay: Double = -0.5
    private static let gradeWeight: Double = 0.35
    private static let meanReversion: Double = 0.08
    private static let stabilityGrowthAlpha: Double = 0.32

    static func schedule(_ input: SpacedReviewInput) -> SpacedReviewResult {
        let elapsedDays = elapsedDays(now: input.now, lastReviewedAt: input.lastReviewedAt)
        let previousStability = max(0, input.stability)
        let retrievability = computeRetrievability(elapsedDays: elapsedDays, stability: previousStability)
        let updatedDifficulty = updateDifficulty(current: input.difficulty, rating: input.rating)

        let updatedStability: Double
        if previousStability <= 0 {
            updatedStability = initialStability(for: input.rating)
        } else {
            updatedStability = updateStability(
                current: previousStability,
                difficulty: updatedDifficulty,
                retrievability: retrievability,
                rating: input.rating
            )
        }

        let nextInterval = computeNextIntervalDays(
            rating: input.rating,
            stability: updatedStability,
            previousInterval: max(0, input.intervalDays)
        )

        let repetitions = input.rating == .again ? 0 : max(0, input.repetitions) + 1
        let lapses = input.rating == .again ? max(0, input.lapses) + 1 : max(0, input.lapses)
        let dueDate = input.now.addingTimeInterval(nextInterval * 86_400)

        return SpacedReviewResult(
            dueDate: dueDate,
            intervalDays: nextInterval,
            stability: updatedStability,
            difficulty: updatedDifficulty,
            repetitions: repetitions,
            lapses: lapses,
            lastReviewedAt: input.now
        )
    }

    static func predictRetrievability(stability: Double, now: Date, lastReviewedAt: Date?) -> Double {
        let elapsed = elapsedDays(now: now, lastReviewedAt: lastReviewedAt)
        return computeRetrievability(elapsedDays: elapsed, stability: stability)
    }

    private static func elapsedDays(now: Date, lastReviewedAt: Date?) -> Double {
        guard let lastReviewedAt else { return 0 }
        let elapsed = now.timeIntervalSince(lastReviewedAt) / 86_400
        return max(0, elapsed)
    }

    private static func computeRetrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        let factor = pow(retention, 1 / decay) - 1
        let value = pow(1 + factor * (elapsedDays / stability), decay)
        return min(1, max(0, value))
    }

    private static func updateDifficulty(current: Double, rating: SpacedReviewRating) -> Double {
        let baseDifficulty = current > 0 ? current : 5
        let gradeDelta = gradeWeight * Double(3 - rating.rawValue)
        let reversion = meanReversion * (5 - baseDifficulty)
        return min(10, max(1, baseDifficulty + gradeDelta + reversion))
    }

    private static func updateStability(
        current: Double,
        difficulty: Double,
        retrievability: Double,
        rating: SpacedReviewRating
    ) -> Double {
        switch rating {
        case .again:
            return max(0.2, current * (0.25 + 0.35 * (1 - retrievability)))
        case .hard, .good, .easy:
            let gradeMultiplier: Double
            switch rating {
            case .hard:
                gradeMultiplier = 0.85
            case .good:
                gradeMultiplier = 1.0
            case .easy:
                gradeMultiplier = 1.3
            case .again:
                gradeMultiplier = 1.0
            }

            let difficultyModifier = exp(-0.25 * (difficulty - 5))
            let retrievabilityModifier = exp(1 - retrievability) - 1
            let growth = 1 + stabilityGrowthAlpha * difficultyModifier * retrievabilityModifier * gradeMultiplier
            return max(0.3, current * growth)
        }
    }

    private static func initialStability(for rating: SpacedReviewRating) -> Double {
        switch rating {
        case .again:
            return 0.2
        case .hard:
            return 1.0
        case .good:
            return 2.5
        case .easy:
            return 4.0
        }
    }

    private static func computeNextIntervalDays(
        rating: SpacedReviewRating,
        stability: Double,
        previousInterval: Double
    ) -> Double {
        switch rating {
        case .again:
            return 0.02
        case .hard:
            let hardInterval = max(1, min(stability, max(1, previousInterval * 1.2)))
            return hardInterval
        case .good:
            let hardBaseline = max(1, min(stability, max(1, previousInterval * 1.2)))
            return max(hardBaseline + 1, stability)
        case .easy:
            let hardBaseline = max(1, min(stability, max(1, previousInterval * 1.2)))
            let goodBaseline = max(hardBaseline + 1, stability)
            return max(goodBaseline + 1, stability * 1.3)
        }
    }
}
