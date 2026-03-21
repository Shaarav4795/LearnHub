// Daily Mix flow: a short, deterministic daily session of questions + flashcards.

import SwiftUI
import SwiftData
import ConfettiSwiftUI

// MARK: - Seeded random number generator

/// A deterministic RNG that yields the same sequence for the same seed.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        // Xorshift keeps the generator fast and deterministic.
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

struct DailyMixView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StudySet.dateCreated, order: .reverse) private var studySets: [StudySet]
    @Query private var profiles: [UserProfile]
    @StateObject private var gamificationManager = GamificationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    // Session phase and content for the Daily Mix run.
    @State private var phase: DailyMixPhase = .intro
    @State private var mixQuestions: [Question] = []
    @State private var mixFlashcards: [Flashcard] = []
    
    // Quiz state mirrors `QuizView` to keep scoring and UI consistent.
    @State private var currentQuestionIndex = 0
    @State private var questionsCorrect = 0
    @State private var isAnswerVisible = false
    @State private var selectedAnswer: String?
    @State private var currentQuestionIsCorrect = false
    @State private var hasRatedCurrentQuestion = false
    
    // Flashcard state mirrors `FlashcardsView` for consistency.
    @State private var currentFlashcardIndex = 0
    @State private var flashcardsStudied = 0
    @State private var flashcardsMastered = 0
    @State private var ratedCardIds: Set<UUID> = []
    @State private var masteredCardIds: Set<UUID> = []
    @State private var mixPlan = DailyMixPlan()
    
    @State private var hasRecordedCompletion = false
    @State private var isPreparingMix = true
    @State private var completionConfettiCounter = 0
    
    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }
    
    private var isAlreadyCompleted: Bool {
        gamificationManager.hasDailyMixCompletedToday(profile: profile)
    }

    private var totalCompletedItems: Int {
        questionsRatedCount + flashcardsStudied
    }

    private var totalPlannedItems: Int {
        mixQuestions.count + mixFlashcards.count
    }

    private var questionsRatedCount: Int {
        currentQuestionIndex + (hasRatedCurrentQuestion ? 1 : 0)
    }
    
    enum DailyMixPhase {
        case intro
        case questions
        case flashcards
        case complete
    }

    private struct DailyMixPlan {
        var questionCap: Int = 0
        var flashcardCap: Int = 0
        var dueQuestions: Int = 0
        var overdueQuestions: Int = 0
        var dueFlashcards: Int = 0
        var overdueFlashcards: Int = 0
        var carryoverQuestions: Int = 0
        var carryoverFlashcards: Int = 0
    }

    enum ReviewRating: String, CaseIterable {
        case again = "Again"
        case hard = "Hard"
        case good = "Good"
        case easy = "Easy"

        var fsrs: SpacedReviewRating {
            switch self {
            case .again: return .again
            case .hard: return .hard
            case .good: return .good
            case .easy: return .easy
            }
        }

        var color: Color {
            switch self {
            case .again: return .red
            case .hard: return .orange
            case .good: return .blue
            case .easy: return .green
            }
        }

        var icon: String {
            switch self {
            case .again: return "arrow.counterclockwise"
            case .hard: return "tortoise.fill"
            case .good: return "hand.thumbsup.fill"
            case .easy: return "bolt.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                switch phase {
                case .intro:
                    introView
                        .transition(.opacity)
                case .questions:
                    questionsPhaseView
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .flashcards:
                    flashcardsPhaseView
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                case .complete:
                    completionView
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: phase)
            .navigationTitle("Daily Mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            isPreparingMix = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                generateDailyMix()
                isPreparingMix = false
            }
        }
        .overlay {
            if isPreparingMix {
                AppLoadingOverlay(
                    title: "Preparing Daily Mix",
                    subtitle: "Selecting today’s questions and flashcards...",
                    animationName: "loading"
                )
            }
        }
        .confettiCannon(counter: $completionConfettiCounter)
    }
    
    // MARK: - Intro view
    
    private var introView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Primary message and hero icon.
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(themeManager.primaryGradient)
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                
                Text(isAlreadyCompleted ? "You've Crushed Today!" : "Ready for Today's Challenge?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Label("Spaced Repetition Session", systemImage: "brain.head.profile")
                    .font(.caption.bold())
                    .foregroundColor(themeManager.primaryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(themeManager.primaryColor.opacity(0.12))
                    .cornerRadius(999)
                
                Text(isAlreadyCompleted
                     ? "Amazing work! Come back tomorrow for a fresh mix."
                     : "Review due items first, then practice a few new ones to keep your streak alive!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)
            }
            
            // Preview of today's adaptive plan.
            if !isAlreadyCompleted {
                VStack(spacing: 12) {
                    HStack(spacing: 24) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                            Text("\(mixQuestions.count) Questions")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                        }

                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 60, height: 60)
                                Image(systemName: "rectangle.stack.fill")
                                    .font(.title)
                                    .foregroundColor(.orange)
                            }
                            Text("\(mixFlashcards.count) Flashcards")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                        }
                    }

                    HStack(spacing: 12) {
                        mixMiniStat(label: "Overdue", value: mixPlan.overdueQuestions + mixPlan.overdueFlashcards, color: .red)
                        mixMiniStat(label: "Due", value: mixPlan.dueQuestions + mixPlan.dueFlashcards, color: .blue)
                        mixMiniStat(label: "Carryover", value: mixPlan.carryoverQuestions + mixPlan.carryoverFlashcards, color: .orange)
                    }
                }
                .padding()
                .glassCard(cornerRadius: 16, strokeOpacity: 0.24)
            }
            
            // Preview of possible XP/coin rewards.
            if !isAlreadyCompleted {
                HStack(spacing: 16) {
                    Label("Up to \(calculateMaxXP()) XP", systemImage: "star.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                    Label("Up to \(calculateMaxCoins()) Coins", systemImage: "dollarsign.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .glassCard(cornerRadius: 12, strokeOpacity: 0.22)
            }
            
            // Reminder to keep a streak active.
            if profile.currentStreak > 0 && !isAlreadyCompleted {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("\(profile.currentStreak) day streak — don't break it!")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(20)
            }
            
            Spacer()
            
            // Primary CTA based on availability/completion.
            VStack(spacing: 12) {
                if !isAlreadyCompleted && !mixQuestions.isEmpty && !mixFlashcards.isEmpty {
                    Button(action: {
                        HapticsManager.shared.playTap()
                        withAnimation {
                            phase = .questions
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Daily Mix")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.primaryColor)
                        .cornerRadius(16)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                } else if isAlreadyCompleted {
                    Button(action: {
                        HapticsManager.shared.playTap()
                        // Allow replay without awarding rewards.
                        withAnimation {
                            phase = .questions
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Practice Again (No Rewards)")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(themeManager.primaryColor)
                        .cornerRadius(16)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                } else {
                    // Inform the user when they lack enough content to run Daily Mix.
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text("Create more study sets to unlock Daily Mix!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .padding()
    }
    
    // MARK: - Questions phase
    
    private var questionsPhaseView: some View {
        VStack(spacing: 0) {
            if currentQuestionIndex < mixQuestions.count {
                let question = mixQuestions[currentQuestionIndex]
                
                VStack(spacing: 20) {
                    // Progress header for current question and score.
                    HStack {
                        Text("Question \(currentQuestionIndex + 1) of \(mixQuestions.count)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(questionsCorrect) correct")
                                .font(.subheadline.bold())
                        }
                        Text("\(totalCompletedItems)/\(totalPlannedItems)")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    Label("Spaced Repetition", systemImage: "brain")
                        .font(.caption.bold())
                        .foregroundColor(themeManager.primaryColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(themeManager.primaryColor.opacity(0.12))
                        .cornerRadius(999)
                    
                    ProgressView(value: Double(questionsRatedCount), total: Double(max(1, mixQuestions.count)))
                        .tint(themeManager.primaryColor)
                        .padding(.horizontal)
                    
                    GeometryReader { proxy in
                        ScrollView {
                            VStack(spacing: 20) {
                            // Main question card.
                            VStack {
                                MathTextView(question.prompt, fontSize: 20)
                                    .fontWeight(.semibold)
                                    .multilineTextAlignment(.center)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                            )
                            .glassCard(cornerRadius: 20, strokeOpacity: 0.2)
                            .padding(.horizontal)
                            
                            // Answer options with selectable states.
                            if let allOptions = question.options, !allOptions.isEmpty {
                                let options = sanitizedOptions(from: allOptions)
                                
                                VStack(spacing: 16) {
                                    ForEach(Array(options.enumerated()), id: \.element) { index, option in
                                        Button(action: {
                                            guard !isAnswerVisible else { return }
                                            HapticsManager.shared.playTap()
                                            checkAnswer(option, correctAnswer: question.answer)
                                        }) {
                                            HStack(spacing: 15) {
                                                ZStack {
                                                    Circle()
                                                        .fill(optionCircleColor(for: option, correctAnswer: question.answer))
                                                        .frame(width: 36, height: 36)
                                                    
                                                    Text(["A", "B", "C", "D"][index % 4])
                                                        .font(.headline)
                                                        .foregroundColor(optionLetterColor(for: option, correctAnswer: question.answer))
                                                }
                                                
                                                MathTextView(option, fontSize: 17)
                                                    .fontWeight(.medium)
                                                    .multilineTextAlignment(.leading)
                                                    .foregroundColor(.primary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                
                                                Spacer()
                                                
                                                if isAnswerVisible {
                                                    if option == question.answer {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .foregroundColor(.green)
                                                            .font(.title2)
                                                    } else if option == selectedAnswer {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .foregroundColor(.red)
                                                            .font(.title2)
                                                    }
                                                }
                                            }
                                            .padding()
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(optionBackgroundColor(for: option, correctAnswer: question.answer))
                                                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(optionBorderColor(for: option, correctAnswer: question.answer), lineWidth: isAnswerVisible && (option == question.answer || option == selectedAnswer) ? 2 : 0)
                                            )
                                        }
                                        .disabled(isAnswerVisible)
                                        .opacity(isAnswerVisible ? 0.9 : 1)
                                        .scaleEffect(selectedAnswer == option ? 0.98 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedAnswer)
                                    }
                                }
                                .padding(.horizontal)
                            } else if isAnswerVisible {
                                VStack(spacing: 16) {
                                    MathTextView(question.answer, fontSize: 17)
                                        .foregroundColor(.primary)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .glassCard(cornerRadius: 12, strokeOpacity: 0.22)
                                }
                                .padding(.horizontal)
                            }

                            if isAnswerVisible, let explanation = question.explanation, !explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Explanation")
                                        .font(.headline)
                                        .foregroundColor(.secondary)

                                    MathTextView(explanation, fontSize: 16)
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .glassCard(cornerRadius: 12, strokeOpacity: 0.22)
                                .padding(.horizontal)
                                .transition(.opacity)
                            }
                        }
                        .padding(.bottom, 100)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: isAnswerVisible ? .top : .center)
                    }
                    }
                }
                
                // Fixed footer for rating + next actions.
                if isAnswerVisible {
                    VStack(spacing: 12) {
                        Text(currentQuestionIsCorrect ? "How easy was this recall?" : "Rate your recall")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(ReviewRating.allCases, id: \.self) { rating in
                                Button(action: {
                                    HapticsManager.shared.playTap()
                                    rateCurrentQuestion(rating)
                                    // Auto-advance
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        nextQuestion()
                                    }
                                }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: rating.icon)
                                            .font(.title3)
                                        Text(rating.rawValue)
                                            .font(.caption.bold())
                                    }
                                    .foregroundColor(hasRatedCurrentQuestion ? .secondary : rating.color)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(hasRatedCurrentQuestion ? Color.secondary.opacity(0.1) : rating.color.opacity(0.15))
                                    .cornerRadius(12)
                                }
                                .disabled(hasRatedCurrentQuestion)
                                .buttonStyle(PressScaleButtonStyle())
                            }
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
        }
    }
    
    // MARK: - Flashcards phase
    
    private var flashcardsPhaseView: some View {
        VStack(spacing: 0) {
            if currentFlashcardIndex < mixFlashcards.count {
                // Progress stats for studied/mastered cards.
                HStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("\(flashcardsStudied) Studied")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("\(flashcardsMastered) Mastered")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)

                    Text("\(totalCompletedItems)/\(totalPlannedItems)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                if mixPlan.carryoverQuestions + mixPlan.carryoverFlashcards > 0 {
                    Text("Carryover after today: \(mixPlan.carryoverQuestions + mixPlan.carryoverFlashcards)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                // Swipeable flashcard deck.
                TabView(selection: $currentFlashcardIndex) {
                    ForEach(mixFlashcards.indices, id: \.self) { index in
                        DailyMixFlashcardView(
                            card: mixFlashcards[index],
                            isStudied: ratedCardIds.contains(mixFlashcards[index].id),
                            isMastered: masteredCardIds.contains(mixFlashcards[index].id),
                            onRate: { rating in
                                rateFlashcard(mixFlashcards[index].id, rating: rating)
                            },
                            themeColor: themeManager.primaryColor
                        )
                        .tag(index)
                        .padding()
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                
                // Bottom bar with position and finish CTA.
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption)
                        Text("\(currentFlashcardIndex + 1) of \(mixFlashcards.count)")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if flashcardsStudied == mixFlashcards.count && !mixFlashcards.isEmpty {
                        Button(action: {
                            HapticsManager.shared.playTap()
                            finishDailyMix()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Finish Daily Mix")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(themeManager.primaryColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PressScaleButtonStyle())
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Completion view
    
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Celebration icon and title.
            ZStack {
                Circle()
                    .fill(themeManager.primaryGradient)
                    .frame(width: 120, height: 120)
                
                Image(systemName: "trophy.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)

                CelebrationLottieView(animationName: "celebration", play: phase == .complete)
                    .frame(width: 82, height: 82)
            }
            
            Text("Daily Mix Complete!")
                .font(.largeTitle.bold())
            
            Text(motivationalMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Summary of question and flashcard performance.
            VStack(spacing: 16) {
                HStack(spacing: 40) {
                    VStack(spacing: 4) {
                        Text("\(questionsCorrect)/\(mixQuestions.count)")
                            .font(.title2.bold())
                            .foregroundColor(.blue)
                        Text("Questions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(flashcardsStudied)/\(mixFlashcards.count)")
                            .font(.title2.bold())
                            .foregroundColor(.orange)
                        Text("Flashcards")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(flashcardsMastered)")
                            .font(.title2.bold())
                            .foregroundColor(.green)
                        Text("Mastered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .glassCard(cornerRadius: 16, strokeOpacity: 0.24)
            
            // Reward breakdown, only on first completion today.
            if !isAlreadyCompleted {
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.blue)
                            Text("+\(calculateEarnedXP())")
                                .font(.headline.bold())
                                .foregroundColor(.blue)
                        }
                        Text("XP Earned")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                    .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                    
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.yellow)
                            Text("+\(calculateEarnedCoins())")
                                .font(.headline.bold())
                                .foregroundColor(.yellow)
                        }
                        Text("Coins")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(12)
                    .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                }
                
                // Streak reinforcement message.
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.orange)
                    Text("Streak maintained!")
                        .font(.subheadline.bold())
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(20)
            } else {
                Text("Practice complete!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Backlog remaining: \(mixPlan.carryoverQuestions) questions, \(mixPlan.carryoverFlashcards) flashcards")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: {
                HapticsManager.shared.playTap()
                dismiss()
            }) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.primaryColor)
                    .cornerRadius(16)
            }
                    .buttonStyle(PressScaleButtonStyle())
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .padding()
    }
    
    // MARK: - Helper functions
    
    private func generateDailyMix() {
        var allQuestions: [Question] = []
        var allFlashcards: [Flashcard] = []

        for set in studySets {
            allQuestions.append(contentsOf: set.questions ?? [])
            allFlashcards.append(contentsOf: set.flashcards ?? [])
        }

        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        let seed = UInt64(dayStart.timeIntervalSince1970)
        var generator = SeededRandomNumberGenerator(seed: seed)
        let wrongQuestionIDs = gamificationManager.fetchIncorrectQuestionIDs()

        let dueQuestions = allQuestions.filter { $0.isDueForReview || wrongQuestionIDs.contains($0.id) }
        let dueFlashcards = allFlashcards.filter { $0.isDueForReview }
        let overdueQuestions = dueQuestions.filter { isOverdue($0.reviewDueDate, now: now) }
        let overdueFlashcards = dueFlashcards.filter { isOverdue($0.reviewDueDate, now: now) }

        let adaptiveTotalCap = computeAdaptiveTotalCap(
            totalItems: allQuestions.count + allFlashcards.count,
            overdueCount: overdueQuestions.count + overdueFlashcards.count
        )
        let (questionCap, flashcardCap) = splitCaps(
            totalCap: adaptiveTotalCap,
            questionAvailable: allQuestions.count,
            flashcardAvailable: allFlashcards.count,
            dueQuestions: dueQuestions.count,
            dueFlashcards: dueFlashcards.count
        )

        let totalNewCap: Int
        if (overdueQuestions.count + overdueFlashcards.count) > Int(Double(max(1, adaptiveTotalCap)) * 0.8) {
            totalNewCap = 0
        } else {
            totalNewCap = min(4, Int(Double(adaptiveTotalCap) * 0.2))
        }
        let (questionNewCap, flashcardNewCap) = splitCaps(
            totalCap: totalNewCap,
            questionAvailable: allQuestions.filter(\.isNewForReview).count,
            flashcardAvailable: allFlashcards.filter(\.isNewForReview).count,
            dueQuestions: dueQuestions.count,
            dueFlashcards: dueFlashcards.count,
            enforceMinimums: false
        )

        let questionSelection = selectQuestions(
            allQuestions: allQuestions,
            wrongQuestionIDs: wrongQuestionIDs,
            target: questionCap,
            maxNewItems: questionNewCap,
            now: now,
            generator: &generator
        )
        mixQuestions = questionSelection.items

        let flashcardSelection = selectFlashcards(
            allFlashcards: allFlashcards,
            target: flashcardCap,
            maxNewItems: flashcardNewCap,
            now: now,
            generator: &generator
        )
        mixFlashcards = flashcardSelection.items

        mixPlan = DailyMixPlan(
            questionCap: questionCap,
            flashcardCap: flashcardCap,
            dueQuestions: dueQuestions.count,
            overdueQuestions: overdueQuestions.count,
            dueFlashcards: dueFlashcards.count,
            overdueFlashcards: overdueFlashcards.count,
            carryoverQuestions: questionSelection.carryover,
            carryoverFlashcards: flashcardSelection.carryover
        )

        let selectedQuestionIDs = Set(mixQuestions.map(\.id))
        for question in allQuestions where !selectedQuestionIDs.contains(question.id) && !question.isDueForReview {
            gamificationManager.recordQuestionResult(questionID: question.id, wasCorrect: true)
        }

        resetSessionProgress()
    }
    
    private func checkAnswer(_ option: String, correctAnswer: String) {
        selectedAnswer = option
        isAnswerVisible = true
        hasRatedCurrentQuestion = false
        let isCorrect = option == correctAnswer
        currentQuestionIsCorrect = isCorrect
        let question = mixQuestions[currentQuestionIndex]
        gamificationManager.recordQuestionResult(
            questionID: question.id,
            wasCorrect: isCorrect
        )
        if isCorrect {
            questionsCorrect += 1
        }
    }

    private func rateCurrentQuestion(_ rating: ReviewRating) {
        guard !hasRatedCurrentQuestion else { return }
        guard currentQuestionIndex < mixQuestions.count else { return }
        let question = mixQuestions[currentQuestionIndex]
        applyReview(to: question, rating: rating)
        hasRatedCurrentQuestion = true
        try? modelContext.save()
    }
    
    private func nextQuestion() {
        guard hasRatedCurrentQuestion else { return }
        if currentQuestionIndex < mixQuestions.count - 1 {
            currentQuestionIndex += 1
            isAnswerVisible = false
            selectedAnswer = nil
            hasRatedCurrentQuestion = false
            currentQuestionIsCorrect = false
        } else {
            // Transition to the flashcards phase after the last question.
            withAnimation {
                phase = .flashcards
            }
        }
    }
    
    private func rateFlashcard(_ cardId: UUID, rating: ReviewRating) {
        guard !ratedCardIds.contains(cardId) else { return }
        guard let idx = mixFlashcards.firstIndex(where: { $0.id == cardId }) else { return }

        ratedCardIds.insert(cardId)
        flashcardsStudied = ratedCardIds.count

        if rating == .easy {
            masteredCardIds.insert(cardId)
            mixFlashcards[idx].isMastered = true
        }
        flashcardsMastered = masteredCardIds.count

        applyReview(to: mixFlashcards[idx], rating: rating)
        try? modelContext.save()
        gamificationManager.syncStudySets(studySets)

        if currentFlashcardIndex < mixFlashcards.count - 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation {
                    currentFlashcardIndex += 1
                }
            }
        }
    }

    private func selectQuestions(
        allQuestions: [Question],
        wrongQuestionIDs: Set<UUID>,
        target: Int,
        maxNewItems: Int,
        now: Date,
        generator: inout SeededRandomNumberGenerator
    ) -> (items: [Question], carryover: Int) {
        guard target > 0 else { return ([], 0) }

        let dueOrPriority = allQuestions
            .filter { $0.isDueForReview || wrongQuestionIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsScore = questionUrgency(lhs, wrongQuestionIDs: wrongQuestionIDs, now: now)
                let rhsScore = questionUrgency(rhs, wrongQuestionIDs: wrongQuestionIDs, now: now)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var selected = Array(dueOrPriority.prefix(target))
        let selectedIDs = Set(selected.map(\.id))

        var newItems = allQuestions
            .filter { $0.isNewForReview && !selectedIDs.contains($0.id) && !wrongQuestionIDs.contains($0.id) }
        newItems.shuffle(using: &generator)

        let newCount = min(maxNewItems, max(0, target - selected.count))
        selected.append(contentsOf: newItems.prefix(newCount))

        if selected.count < target {
            let selectedNow = Set(selected.map(\.id))
            let fallback = allQuestions
                .filter { !selectedNow.contains($0.id) }
                .sorted { lhs, rhs in
                    let lhsDue = lhs.reviewDueDate ?? .distantFuture
                    let rhsDue = rhs.reviewDueDate ?? .distantFuture
                    if lhsDue != rhsDue { return lhsDue < rhsDue }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            selected.append(contentsOf: fallback.prefix(target - selected.count))
        }

        let carryover = max(0, dueOrPriority.count - min(target, dueOrPriority.count))
        return (selected, carryover)
    }

    private func selectFlashcards(
        allFlashcards: [Flashcard],
        target: Int,
        maxNewItems: Int,
        now: Date,
        generator: inout SeededRandomNumberGenerator
    ) -> (items: [Flashcard], carryover: Int) {
        guard target > 0 else { return ([], 0) }

        let dueItems = allFlashcards
            .filter { $0.isDueForReview }
            .sorted { lhs, rhs in
                let lhsScore = flashcardUrgency(lhs, now: now)
                let rhsScore = flashcardUrgency(rhs, now: now)
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var selected = Array(dueItems.prefix(target))
        let selectedIDs = Set(selected.map(\.id))

        var newItems = allFlashcards
            .filter { $0.isNewForReview && !selectedIDs.contains($0.id) }
        newItems.shuffle(using: &generator)

        let newCount = min(maxNewItems, max(0, target - selected.count))
        selected.append(contentsOf: newItems.prefix(newCount))

        if selected.count < target {
            let selectedNow = Set(selected.map(\.id))
            let fallback = allFlashcards
                .filter { !selectedNow.contains($0.id) }
                .sorted { lhs, rhs in
                    let lhsDue = lhs.reviewDueDate ?? .distantFuture
                    let rhsDue = rhs.reviewDueDate ?? .distantFuture
                    if lhsDue != rhsDue { return lhsDue < rhsDue }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            selected.append(contentsOf: fallback.prefix(target - selected.count))
        }

        let carryover = max(0, dueItems.count - min(target, dueItems.count))
        return (selected, carryover)
    }

    private func applyReview(to question: Question, rating: ReviewRating) {
        let result = SpacedRepetitionScheduler.schedule(
            SpacedReviewInput(
                now: Date(),
                difficulty: question.reviewDifficulty,
                stability: question.reviewStability,
                intervalDays: question.reviewIntervalDays,
                repetitions: question.reviewRepetitions,
                lapses: question.reviewLapses,
                lastReviewedAt: question.reviewLastReviewedAt,
                rating: rating.fsrs
            )
        )

        question.reviewDifficulty = result.difficulty
        question.reviewStability = result.stability
        question.reviewIntervalDays = result.intervalDays
        question.reviewRepetitions = result.repetitions
        question.reviewDueDate = result.dueDate
        question.reviewLapses = result.lapses
        question.reviewLastReviewedAt = result.lastReviewedAt
    }

    private func applyReview(to flashcard: Flashcard, rating: ReviewRating) {
        let result = SpacedRepetitionScheduler.schedule(
            SpacedReviewInput(
                now: Date(),
                difficulty: flashcard.reviewDifficulty,
                stability: flashcard.reviewStability,
                intervalDays: flashcard.reviewIntervalDays,
                repetitions: flashcard.reviewRepetitions,
                lapses: flashcard.reviewLapses,
                lastReviewedAt: flashcard.reviewLastReviewedAt,
                rating: rating.fsrs
            )
        )

        flashcard.reviewDifficulty = result.difficulty
        flashcard.reviewStability = result.stability
        flashcard.reviewIntervalDays = result.intervalDays
        flashcard.reviewRepetitions = result.repetitions
        flashcard.reviewDueDate = result.dueDate
        flashcard.reviewLapses = result.lapses
        flashcard.reviewLastReviewedAt = result.lastReviewedAt
    }

    private func computeAdaptiveTotalCap(totalItems: Int, overdueCount: Int) -> Int {
        guard totalItems > 0 else { return 0 }
        let base = 12
        let backlogPressure = min(24, Int(3 * sqrt(Double(overdueCount))))
        let streakBonus: Int
        if profile.currentStreak >= 30 {
            streakBonus = 4
        } else if profile.currentStreak >= 7 {
            streakBonus = 2
        } else {
            streakBonus = 0
        }
        let computed = min(40, max(10, base + backlogPressure + streakBonus))
        return min(totalItems, computed)
    }

    private func splitCaps(
        totalCap: Int,
        questionAvailable: Int,
        flashcardAvailable: Int,
        dueQuestions: Int,
        dueFlashcards: Int,
        enforceMinimums: Bool = true
    ) -> (Int, Int) {
        guard totalCap > 0 else { return (0, 0) }
        guard questionAvailable > 0 else { return (0, min(totalCap, flashcardAvailable)) }
        guard flashcardAvailable > 0 else { return (min(totalCap, questionAvailable), 0) }

        let dueTotal = dueQuestions + dueFlashcards
        let questionShare: Double
        if dueTotal > 0 {
            questionShare = Double(dueQuestions) / Double(dueTotal)
        } else {
            questionShare = Double(questionAvailable) / Double(questionAvailable + flashcardAvailable)
        }

        var questionCap = min(questionAvailable, Int((Double(totalCap) * questionShare).rounded()))
        var flashcardCap = min(flashcardAvailable, totalCap - questionCap)

        if enforceMinimums && totalCap >= 6 {
            questionCap = max(min(3, questionAvailable), questionCap)
            flashcardCap = max(min(3, flashcardAvailable), flashcardCap)
        }

        if questionCap + flashcardCap > totalCap {
            if questionCap > flashcardCap {
                questionCap -= (questionCap + flashcardCap) - totalCap
            } else {
                flashcardCap -= (questionCap + flashcardCap) - totalCap
            }
        }

        if questionCap + flashcardCap < totalCap {
            let remaining = totalCap - (questionCap + flashcardCap)
            let questionRoom = max(0, questionAvailable - questionCap)
            let questionAdd = min(remaining, questionRoom)
            questionCap += questionAdd
            flashcardCap += min(totalCap - (questionCap + flashcardCap), max(0, flashcardAvailable - flashcardCap))
        }

        return (questionCap, flashcardCap)
    }

    private func questionUrgency(_ question: Question, wrongQuestionIDs: Set<UUID>, now: Date) -> Double {
        let overdueDays = overdueDays(until: question.reviewDueDate, now: now)
        let retrievability = SpacedRepetitionScheduler.predictRetrievability(
            stability: question.reviewStability,
            now: now,
            lastReviewedAt: question.reviewLastReviewedAt
        )
        let wrongBoost = wrongQuestionIDs.contains(question.id) ? 100.0 : 0.0
        return wrongBoost + (8 * overdueDays) + (20 * (1 - retrievability))
    }

    private func flashcardUrgency(_ flashcard: Flashcard, now: Date) -> Double {
        let overdueDays = overdueDays(until: flashcard.reviewDueDate, now: now)
        let retrievability = SpacedRepetitionScheduler.predictRetrievability(
            stability: flashcard.reviewStability,
            now: now,
            lastReviewedAt: flashcard.reviewLastReviewedAt
        )
        return (8 * overdueDays) + (20 * (1 - retrievability))
    }

    private func overdueDays(until dueDate: Date?, now: Date) -> Double {
        guard let dueDate else { return 0 }
        return max(0, now.timeIntervalSince(dueDate) / 86_400)
    }

    private func isOverdue(_ dueDate: Date?, now: Date) -> Bool {
        guard let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: now)
    }

    private func resetSessionProgress() {
        phase = .intro
        currentQuestionIndex = 0
        questionsCorrect = 0
        isAnswerVisible = false
        selectedAnswer = nil
        currentQuestionIsCorrect = false
        hasRatedCurrentQuestion = false
        currentFlashcardIndex = 0
        flashcardsStudied = 0
        flashcardsMastered = 0
        ratedCardIds = []
        masteredCardIds = []
        hasRecordedCompletion = false
    }

    private func sanitizedOptions(from options: [String]) -> [String] {
        options.filter { option in
            !((option.hasPrefix("Option ") || option.hasPrefix("option ")) && option.count < 10 && option.last?.isNumber == true)
        }
    }
    
    private func finishDailyMix() {
        guard !hasRecordedCompletion else {
            withAnimation { phase = .complete }
            return
        }
        hasRecordedCompletion = true
        
        // Award rewards only once per day.
        if !isAlreadyCompleted {
            gamificationManager.recordDailyMixCompletion(
                questionsCorrect: questionsCorrect,
                flashcardsStudied: flashcardsStudied,
                profile: profile,
                context: modelContext
            )
        }
        
        withAnimation {
            phase = .complete
        }
        completionConfettiCounter += 1
    }
    
    // MARK: - Reward calculations
    
    private func calculateMaxXP() -> Int {
        let base = XPRewards.dailyMixBase
        let questions = mixQuestions.count * XPRewards.dailyMixQuestionCorrect
        let flashcards = mixFlashcards.count * XPRewards.dailyMixFlashcard
        let multiplier = gamificationManager.totalXPMultiplierPreview(for: profile)
        return Int(Double(base + questions + flashcards) * multiplier)
    }
    
    private func calculateMaxCoins() -> Int {
        return CoinRewards.dailyMixBase + (mixQuestions.count * CoinRewards.dailyMixQuestionCorrect) + (mixFlashcards.count * CoinRewards.dailyMixFlashcard)
    }
    
    private func calculateEarnedXP() -> Int {
        let base = XPRewards.dailyMixBase
        let questions = questionsCorrect * XPRewards.dailyMixQuestionCorrect
        let flashcards = flashcardsStudied * XPRewards.dailyMixFlashcard
        let multiplier = gamificationManager.totalXPMultiplierPreview(for: profile)
        return Int(Double(base + questions + flashcards) * multiplier)
    }
    
    private func calculateEarnedCoins() -> Int {
        return CoinRewards.dailyMixBase + (questionsCorrect * CoinRewards.dailyMixQuestionCorrect) + (flashcardsStudied * CoinRewards.dailyMixFlashcard)
    }
    
    private var motivationalMessage: String {
        let percentage = Double(questionsCorrect) / Double(max(1, mixQuestions.count))
        if percentage >= 1.0 {
            return "Perfect score! You're unstoppable! 🔥"
        } else if percentage >= 0.8 {
            return "Excellent work! Keep that momentum going!"
        } else if percentage >= 0.6 {
            return "Great effort! Practice makes perfect!"
        } else {
            return "Keep learning — every step counts!"
        }
    }

    private func mixMiniStat(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.subheadline.bold())
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
    
    // MARK: - Option styling (mirrors QuizView)
    
    private func optionCircleColor(for option: String, correctAnswer: String) -> Color {
        guard isAnswerVisible else { return Color.accentColor.opacity(0.1) }
        if option == correctAnswer { return .green }
        if option == selectedAnswer { return .red }
        return Color.gray.opacity(0.2)
    }
    
    private func optionLetterColor(for option: String, correctAnswer: String) -> Color {
        guard isAnswerVisible else { return .accentColor }
        if option == correctAnswer || option == selectedAnswer { return .white }
        return .secondary
    }
    
    private func optionBackgroundColor(for option: String, correctAnswer: String) -> Color {
        guard isAnswerVisible else { return Color(uiColor: .secondarySystemGroupedBackground) }
        if option == correctAnswer { return .green.opacity(0.1) }
        if option == selectedAnswer { return .red.opacity(0.1) }
        return Color(uiColor: .secondarySystemGroupedBackground)
    }
    
    private func optionBorderColor(for option: String, correctAnswer: String) -> Color {
        guard isAnswerVisible else { return .gray.opacity(0.3) }
        if option == correctAnswer { return .green }
        if option == selectedAnswer { return .red }
        return .gray.opacity(0.3)
    }
}

// MARK: - Daily Mix flashcard view (mirrors FlashcardView)

private struct DailyMixFlashcardView: View {
    let card: Flashcard
    var isStudied: Bool = false
    var isMastered: Bool = false
    var onRate: ((DailyMixView.ReviewRating) -> Void)?
    var themeColor: Color = ThemeManager.shared.primaryColor
    
    @State private var isFlipped = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 5)
                
                VStack {
                    if isFlipped {
                        MathTextView(card.back, fontSize: 20)
                            .multilineTextAlignment(.center)
                            .padding()
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    } else {
                        MathTextView(card.front, fontSize: 24, forceBold: true)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
            }
            .frame(height: 260)
            .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            .onTapGesture {
                HapticsManager.shared.playTap()
                withAnimation(.spring()) {
                    isFlipped.toggle()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isFlipped ? "Flashcard answer" : "Flashcard question")
            .accessibilityValue(isFlipped ? card.back : card.front)
            .accessibilityHint(isFlipped ? "Swipe or double-tap to go back to the question" : "Double-tap to flip and hear the answer")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                HapticsManager.shared.playTap()
                withAnimation(.spring()) {
                    isFlipped.toggle()
                }
            }
            
            if isFlipped && !isStudied {
                VStack(spacing: 12) {
                    Text("Rate your recall")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        ForEach(DailyMixView.ReviewRating.allCases, id: \.self) { rating in
                            Button(action: {
                                HapticsManager.shared.playTap()
                                onRate?(rating)
                            }) {
                                VStack(spacing: 6) {
                                    Image(systemName: rating.icon)
                                        .font(.title3)
                                    Text(rating.rawValue)
                                        .font(.caption.bold())
                                }
                                .foregroundColor(rating.color)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(rating.color.opacity(0.15))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PressScaleButtonStyle())
                        }
                    }
                    .transition(.opacity)
                }
            } else if isFlipped && isMastered {
                Label("Mastered!", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.green.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else if isFlipped && isStudied {
                Label("Rated", systemImage: "checkmark.circle")
                    .font(.subheadline.bold())
                    .foregroundColor(themeColor.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
    }
}

#Preview {
    DailyMixView()
        .modelContainer(for: [StudySet.self, UserProfile.self], inMemory: true)
}
