import SwiftUI
import SwiftData

struct FlashcardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @StateObject private var gamificationManager = GamificationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @EnvironmentObject private var guideManager: GuideManager
    
    let studySet: StudySet
    @State private var flashcards: [Flashcard]
    @State private var currentIndex = 0
    @State private var cardsStudied = 0
    @State private var cardsMastered = 0
    @State private var hasRecordedSession = false
    @State private var showSessionComplete = false
    @State private var studiedCardIds: Set<UUID> = []
    @State private var masteredCardIds: Set<UUID> = []
    @State private var showEditFlashcards = false
    
    init(studySet: StudySet) {
        self.studySet = studySet
        _flashcards = State(initialValue: studySet.flashcards)
        _masteredCardIds = State(initialValue: Set(studySet.flashcards.filter(\.isMastered).map(\.id)))
    }
    
    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }
    
    var body: some View {
        VStack {
            if flashcards.isEmpty {
                Text("No flashcards available.")
                    .foregroundColor(.secondary)
            } else if showSessionComplete {
                sessionCompleteView
            } else {
                // Session progress summary (studied vs mastered).
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("\(cardsStudied) Studied")
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
                        Text("\(cardsMastered) Mastered")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 12)

                // Action to generate additional flashcards for this set.
                HStack {
                    Button {
                        HapticsManager.shared.playTap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showEditFlashcards = true
                        }
                    } label: {
                        Label("Edit Flashcards", systemImage: "square.and.pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeManager.primaryColor)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                
                TabView(selection: $currentIndex) {
                    ForEach(flashcards.indices, id: \.self) { index in
                        FlashcardView(
                            card: flashcards[index],
                            isStudied: studiedCardIds.contains(flashcards[index].id),
                            isMastered: masteredCardIds.contains(flashcards[index].id),
                            onStudied: { markStudied(flashcards[index].id) },
                            onMastered: { markMastered(flashcards[index].id) }
                        )
                        .tag(index)
                        .padding()
                        .guideTarget(.flashcardsDeck)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                
                // Bottom bar with position and session CTA.
                HStack {
                    // Current card index and total count.
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption)
                        Text("\(currentIndex + 1) of \(flashcards.count)")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if cardsStudied > 0 {
                        Button(action: {
                            HapticsManager.shared.playTap()
                            finishSession()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Finish Session")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accentColor)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Flashcards")
        .fullScreenCover(isPresented: $showEditFlashcards) {
            NavigationStack {
                FlashcardsEditorView(studySet: studySet) {
                    refreshFlashcardsFromSource()
                }
            }
        }
        .onDisappear {
            if cardsStudied > 0 && !hasRecordedSession {
                finishSession()
            }
            if guideManager.currentStep == .exploreFlashcards {
                guideManager.advanceAfterVisitedFlashcards()
            }
        }
    }
    
    private var sessionCompleteView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text("Session Complete!")
                .font(.title.bold())
            
            VStack(spacing: 16) {
                HStack(spacing: 30) {
                    VStack(spacing: 4) {
                        Text("\(cardsStudied)")
                            .font(.title2.bold())
                        Text("Studied")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(spacing: 4) {
                        Text("\(cardsMastered)")
                            .font(.title2.bold())
                            .foregroundColor(.green)
                        Text("Mastered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // XP summary for the completed session.
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.blue)
                    Text("+\(calculateXPEarned()) XP")
                        .font(.headline.bold())
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
        .padding()
    }
    
    private func markStudied(_ cardId: UUID) {
        guard !studiedCardIds.contains(cardId) else { return }
        studiedCardIds.insert(cardId)
        cardsStudied += 1
    }
    
    private func markMastered(_ cardId: UUID) {
        guard !masteredCardIds.contains(cardId) else { return }
        masteredCardIds.insert(cardId)
        cardsMastered += 1
        if let idx = flashcards.firstIndex(where: { $0.id == cardId }) {
            flashcards[idx].isMastered = true
        }
        // Ensure mastered cards count as studied.
        if !studiedCardIds.contains(cardId) {
            studiedCardIds.insert(cardId)
            cardsStudied += 1
        }
        try? modelContext.save()
        gamificationManager.syncStudySets([studySet])
    }
    
    private func finishSession() {
        guard !hasRecordedSession && cardsStudied > 0 else { return }
        hasRecordedSession = true
        
        gamificationManager.recordFlashcardStudied(
            count: cardsStudied,
            mastered: cardsMastered,
            profile: profile,
            context: modelContext
        )
        
        showSessionComplete = true
    }

    private func refreshFlashcardsFromSource() {
        flashcards = studySet.flashcards
        if flashcards.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(currentIndex, flashcards.count - 1)
        }
        cardsMastered = flashcards.filter(\.isMastered).count
        masteredCardIds = Set(flashcards.filter(\.isMastered).map(\.id))
    }

    private func calculateXPEarned() -> Int {
        var xp = cardsStudied * XPRewards.flashcardStudied
        xp += cardsMastered * XPRewards.flashcardMastered
        let multiplier = XPRewards.streakMultiplier(for: profile.currentStreak)
        return Int(Double(xp) * multiplier)
    }
}

struct FlashcardView: View {
    let card: Flashcard
    var isStudied: Bool = false
    var isMastered: Bool = false
    var onStudied: (() -> Void)?
    var onMastered: (() -> Void)?
    
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
                    if isFlipped && !isStudied {
                        onStudied?()
                    }
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
                    if isFlipped && !isStudied {
                        onStudied?()
                    }
                }
            }
            
            // Mastery action appears only after the card is flipped.
            if isFlipped && !isMastered {
                Button(action: {
                    HapticsManager.shared.playTap()
                    onMastered?()
                }) {
                    Label("I Know This!", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(20)
                }
            } else if isFlipped && isMastered {
                Label("Mastered!", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.green.opacity(0.6))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
    }
}
