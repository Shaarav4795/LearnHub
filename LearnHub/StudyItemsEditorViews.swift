import SwiftUI
import SwiftData
import Shimmer

struct FlashcardsEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var gamificationManager = GamificationManager.shared

    let studySet: StudySet
    let onChanged: () -> Void

    @State private var flashcards: [Flashcard]
    @State private var showGenerateSheet = false
    @State private var isGenerating = false
    @State private var additionalCount: Double = 6
    @State private var relativeDifficulty: AIService.RelativeDifficulty = .same
    @State private var generationError: String?
    @State private var pendingDeleteFlashcard: Flashcard?
    @State private var editingFlashcardState: FlashcardEditorState?

    init(studySet: StudySet, onChanged: @escaping () -> Void = {}) {
        self.studySet = studySet
        self.onChanged = onChanged
        _flashcards = State(initialValue: studySet.flashcards)
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    EditorActionRow(
                        themeColor: themeManager.primaryColor,
                        onAdd: { startCreatingFlashcard() },
                        onGenerate: {
                            HapticsManager.shared.playTap()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                showGenerateSheet = true
                            }
                        }
                    )
                    .listRowBackground(Color.clear)
                }

                Section("Flashcards (\(flashcards.count))") {
                    if flashcards.isEmpty {
                        ContentUnavailableView {
                            Label("No Flashcards", systemImage: "rectangle.stack")
                        } description: {
                            Text("Add one manually or generate more with AI.")
                        }
                    } else {
                        ForEach(flashcards) { card in
                            Button {
                                HapticsManager.shared.playTap()
                                editingFlashcardState = .editing(card)
                            } label: {
                                FlashcardListRow(card: card, tintColor: themeManager.primaryColor)
                            }
                            .buttonStyle(.plain)
                            .buttonStyle(PressScaleButtonStyle())
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    HapticsManager.shared.playTap()
                                    pendingDeleteFlashcard = card
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .listStyle(.insetGrouped)
            .allowsHitTesting(!showGenerateSheet)

            if showGenerateSheet {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showGenerateSheet = false
                        }
                    }

                ItemGenerationPopup(
                    title: "Generate More Flashcards",
                    count: $additionalCount,
                    countRange: 3...25,
                    countLabel: "Flashcards",
                    difficulty: $relativeDifficulty,
                    isGenerating: isGenerating,
                    themeColor: themeManager.primaryColor,
                    onGenerate: { generateMoreFlashcards() },
                    onDismiss: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showGenerateSheet = false
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationTitle("Edit Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticsManager.shared.playSuccess()
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryColor)
                }
            }
        }
        .sheet(item: $editingFlashcardState) { state in
            NavigationStack {
                FlashcardDetailEditorSheet(
                    state: state,
                    tintColor: themeManager.primaryColor,
                    onSave: { updatedState in
                        saveFlashcard(from: updatedState)
                    }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete flashcard?", isPresented: Binding(
            get: { pendingDeleteFlashcard != nil },
            set: { if !$0 { pendingDeleteFlashcard = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let card = pendingDeleteFlashcard {
                    delete(card)
                }
                pendingDeleteFlashcard = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteFlashcard = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Could not generate", isPresented: Binding(
            get: { generationError != nil },
            set: { if !$0 { generationError = nil } }
        )) {
            Button("OK", role: .cancel) {
                generationError = nil
            }
        } message: {
            if let generationError {
                Text(generationError)
            }
        }
    }

    private func startCreatingFlashcard() {
        HapticsManager.shared.playTap()
        editingFlashcardState = .create()
    }

    private func saveFlashcard(from state: FlashcardEditorState) {
        if let existing = state.card {
            existing.front = state.front.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.back = state.back.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let card = Flashcard(
                front: state.front.trimmingCharacters(in: .whitespacesAndNewlines),
                back: state.back.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            card.studySet = studySet
            modelContext.insert(card)
        }

        flashcards = studySet.flashcards
        persistChanges(playSuccess: true)
    }

    private func delete(_ card: Flashcard) {
        HapticsManager.shared.playSuccess()
        modelContext.delete(card)
        flashcards.removeAll { $0.id == card.id }
        persistChanges()
    }

    private func generateMoreFlashcards() {
        HapticsManager.shared.playTap()
        generationError = nil
        isGenerating = true

        Task {
            do {
                let sourceText = limitedAISourceText(
                    originalText: studySet.originalText,
                    summary: studySet.summary,
                    title: studySet.title
                )

                let newData = try await AIService.shared.generateFlashcards(
                    from: sourceText,
                    count: Int(additionalCount),
                    relativeDifficulty: relativeDifficulty
                )

                await MainActor.run {
                    let newCards = newData.map { pair -> Flashcard in
                        let card = Flashcard(front: pair.front, back: pair.back)
                        card.studySet = studySet
                        modelContext.insert(card)
                        return card
                    }
                    flashcards.append(contentsOf: newCards)
                    isGenerating = false
                    showGenerateSheet = false
                    persistChanges(playSuccess: true)
                }
            } catch {
                await MainActor.run {
                    generationError = AIService.formatError(error)
                    isGenerating = false
                }
            }
        }
    }

    private func persistChanges(playSuccess: Bool = false) {
        if playSuccess {
            HapticsManager.shared.playSuccess()
        }
        try? modelContext.save()
        gamificationManager.syncStudySets([studySet])
        onChanged()
    }
}

struct QuestionsEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var gamificationManager = GamificationManager.shared

    let studySet: StudySet
    let onChanged: () -> Void

    @State private var questions: [Question]
    @State private var showGenerateSheet = false
    @State private var isGenerating = false
    @State private var additionalCount: Double = 5
    @State private var relativeDifficulty: AIService.RelativeDifficulty = .same
    @State private var generationError: String?
    @State private var pendingDeleteQuestion: Question?
    @State private var editingQuestionState: QuestionEditorState?

    init(studySet: StudySet, onChanged: @escaping () -> Void = {}) {
        self.studySet = studySet
        self.onChanged = onChanged
        _questions = State(initialValue: studySet.questions)
    }

    var body: some View {
        ZStack {
            List {
                Section {
                    EditorActionRow(
                        themeColor: themeManager.primaryColor,
                        onAdd: { startCreatingQuestion() },
                        onGenerate: {
                            HapticsManager.shared.playTap()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                showGenerateSheet = true
                            }
                        }
                    )
                    .listRowBackground(Color.clear)
                }

                Section("Questions (\(questions.count))") {
                    if questions.isEmpty {
                        ContentUnavailableView {
                            Label("No Questions", systemImage: "questionmark.circle")
                        } description: {
                            Text("Add one manually or generate more with AI.")
                        }
                    } else {
                        ForEach(questions) { question in
                            Button {
                                HapticsManager.shared.playTap()
                                editingQuestionState = .editing(question)
                            } label: {
                                QuestionListRow(question: question, tintColor: themeManager.primaryColor)
                            }
                            .buttonStyle(.plain)
                            .buttonStyle(PressScaleButtonStyle())
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    HapticsManager.shared.playTap()
                                    pendingDeleteQuestion = question
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .listStyle(.insetGrouped)
            .allowsHitTesting(!showGenerateSheet)

            if showGenerateSheet {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showGenerateSheet = false
                        }
                    }

                ItemGenerationPopup(
                    title: "Generate More Questions",
                    count: $additionalCount,
                    countRange: 3...20,
                    countLabel: "Questions",
                    difficulty: $relativeDifficulty,
                    isGenerating: isGenerating,
                    themeColor: themeManager.primaryColor,
                    onGenerate: { generateMoreQuestions() },
                    onDismiss: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showGenerateSheet = false
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationTitle("Edit Questions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticsManager.shared.playSuccess()
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryColor)
                }
            }
        }
        .sheet(item: $editingQuestionState) { state in
            NavigationStack {
                QuestionDetailEditorSheet(
                    state: state,
                    tintColor: themeManager.primaryColor,
                    onSave: { updatedState in
                        saveQuestion(from: updatedState)
                    }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete question?", isPresented: Binding(
            get: { pendingDeleteQuestion != nil },
            set: { if !$0 { pendingDeleteQuestion = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let question = pendingDeleteQuestion {
                    delete(question)
                }
                pendingDeleteQuestion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteQuestion = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Could not generate", isPresented: Binding(
            get: { generationError != nil },
            set: { if !$0 { generationError = nil } }
        )) {
            Button("OK", role: .cancel) {
                generationError = nil
            }
        } message: {
            if let generationError {
                Text(generationError)
            }
        }
    }

    private func startCreatingQuestion() {
        HapticsManager.shared.playTap()
        editingQuestionState = .create()
    }

    private func saveQuestion(from state: QuestionEditorState) {
        if let existing = state.question {
            existing.prompt = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.answer = state.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.explanation = state.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : state.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedOptions = state.optionsText
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            existing.options = parsedOptions.isEmpty ? nil : parsedOptions
        } else {
            let parsedOptions = state.optionsText
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let question = Question(
                prompt: state.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                answer: state.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                options: parsedOptions.isEmpty ? nil : parsedOptions,
                explanation: state.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : state.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            question.studySet = studySet
            modelContext.insert(question)
        }

        questions = studySet.questions
        persistChanges(playSuccess: true)
    }

    private func delete(_ question: Question) {
        HapticsManager.shared.playSuccess()
        modelContext.delete(question)
        questions.removeAll { $0.id == question.id }
        persistChanges()
    }

    private func generateMoreQuestions() {
        HapticsManager.shared.playTap()
        generationError = nil
        isGenerating = true

        Task {
            do {
                let sourceText = limitedAISourceText(
                    originalText: studySet.originalText,
                    summary: studySet.summary,
                    title: studySet.title
                )

                let newData = try await AIService.shared.generateQuestions(
                    from: sourceText,
                    count: Int(additionalCount),
                    relativeDifficulty: relativeDifficulty
                )

                await MainActor.run {
                    let newQuestions = newData.map { data -> Question in
                        let question = Question(
                            prompt: data.question,
                            answer: data.answer,
                            options: data.options,
                            explanation: data.explanation
                        )
                        question.studySet = studySet
                        modelContext.insert(question)
                        return question
                    }
                    questions.append(contentsOf: newQuestions)
                    isGenerating = false
                    showGenerateSheet = false
                    persistChanges(playSuccess: true)
                }
            } catch {
                await MainActor.run {
                    generationError = AIService.formatError(error)
                    isGenerating = false
                }
            }
        }
    }

    private func persistChanges(playSuccess: Bool = false) {
        if playSuccess {
            HapticsManager.shared.playSuccess()
        }
        try? modelContext.save()
        gamificationManager.syncStudySets([studySet])
        onChanged()
    }
}

private struct EditorActionRow: View {
    let themeColor: Color
    let onAdd: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onAdd) {
                Label("Add Manual", systemImage: "plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(themeColor)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(themeColor.opacity(0.12))
                    )
            }
            .buttonStyle(PressScaleButtonStyle())

            Button(action: onGenerate) {
                Label("Generate AI", systemImage: "sparkles")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(themeColor)
                    )
            }
            .buttonStyle(PressScaleButtonStyle())
        }
    }
}

private struct FlashcardListRow: View {
    let card: Flashcard
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(tintColor)
                Text(card.front)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Text(card.back)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
    }
}

private struct QuestionListRow: View {
    let question: Question
    let tintColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(tintColor)
                Text(question.prompt)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Text(question.answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
    }
}

private struct FlashcardEditorState: Identifiable {
    let id: UUID
    let card: Flashcard?
    var front: String
    var back: String

    static func create() -> FlashcardEditorState {
        FlashcardEditorState(id: UUID(), card: nil, front: "", back: "")
    }

    static func editing(_ card: Flashcard) -> FlashcardEditorState {
        FlashcardEditorState(id: card.id, card: card, front: card.front, back: card.back)
    }
}

private struct QuestionEditorState: Identifiable {
    let id: UUID
    let question: Question?
    var prompt: String
    var answer: String
    var explanation: String
    var optionsText: String

    static func create() -> QuestionEditorState {
        QuestionEditorState(id: UUID(), question: nil, prompt: "", answer: "", explanation: "", optionsText: "")
    }

    static func editing(_ question: Question) -> QuestionEditorState {
        QuestionEditorState(
            id: question.id,
            question: question,
            prompt: question.prompt,
            answer: question.answer,
            explanation: question.explanation ?? "",
            optionsText: (question.options ?? []).joined(separator: "\n")
        )
    }
}

private struct FlashcardDetailEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State var state: FlashcardEditorState
    let tintColor: Color
    let onSave: (FlashcardEditorState) -> Void

    private enum Field {
        case front
        case back
    }

    private var canSave: Bool {
        !state.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !state.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [tintColor, tintColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 72, height: 72)

                            Image(systemName: state.card == nil ? "plus.rectangle.on.rectangle" : "square.and.pencil")
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                        }

                        Text(state.card == nil ? "New Flashcard" : "Edit Flashcard")
                            .font(.title2.bold())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Front")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        TextField("Question side", text: $state.front, axis: .vertical)
                            .lineLimit(2...6)
                            .focused($focusedField, equals: .front)
                            .padding()
                            .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Back")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        TextField("Answer side", text: $state.back, axis: .vertical)
                            .lineLimit(2...6)
                            .focused($focusedField, equals: .back)
                            .padding()
                            .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal)
            }
        }
        .navigationTitle(state.card == nil ? "New Flashcard" : "Edit Flashcard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onSave(state)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(tintColor)
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            focusedField = .front
        }
    }
}

private struct QuestionDetailEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State var state: QuestionEditorState
    let tintColor: Color
    let onSave: (QuestionEditorState) -> Void

    private enum Field {
        case prompt
        case answer
        case explanation
    }

    private var canSave: Bool {
        !state.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !state.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [tintColor, tintColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 72, height: 72)

                            Image(systemName: state.question == nil ? "plus.circle" : "square.and.pencil")
                                .font(.system(size: 30))
                                .foregroundStyle(.white)
                        }

                        Text(state.question == nil ? "New Question" : "Edit Question")
                            .font(.title2.bold())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        TextField("Question prompt", text: $state.prompt, axis: .vertical)
                            .lineLimit(2...6)
                            .focused($focusedField, equals: .prompt)
                            .padding()
                            .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Answer")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        TextField("Correct answer", text: $state.answer, axis: .vertical)
                            .lineLimit(2...6)
                            .focused($focusedField, equals: .answer)
                            .padding()
                            .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Explanation (Optional)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        TextField("Extra context", text: $state.explanation, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focusedField, equals: .explanation)
                            .padding()
                            .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Options (Optional, one per line)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $state.optionsText)
                            .frame(minHeight: 110)
                            .padding(8)
                            .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
                    }
                }
                .padding(.top, 28)
                .padding(.horizontal)
            }
        }
        .navigationTitle(state.question == nil ? "New Question" : "Edit Question")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    onSave(state)
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(tintColor)
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            focusedField = .prompt
        }
    }
}

private struct ItemGenerationPopup: View {
    let title: String
    @Binding var count: Double
    let countRange: ClosedRange<Double>
    let countLabel: String
    @Binding var difficulty: AIService.RelativeDifficulty
    let isGenerating: Bool
    let themeColor: Color
    let onGenerate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .foregroundStyle(themeColor)
                    Text(title)
                        .font(.headline)
                }
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(countLabel)
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(count))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $count, in: countRange, step: 1)
                    .tint(themeColor)
                    .onChange(of: count) { _, _ in
                        HapticsManager.shared.playTap()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty")
                    .font(.subheadline)
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(AIService.RelativeDifficulty.allCases) { diff in
                        Text(diff.rawValue).tag(diff)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: difficulty) { _, _ in
                    HapticsManager.shared.playTap()
                }
            }

            Button(action: onGenerate) {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(isGenerating ? "Generating..." : "Generate")
                        .bold()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(themeColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shimmering(active: isGenerating)
            }
            .buttonStyle(.plain)
            .buttonStyle(PressScaleButtonStyle())
            .disabled(isGenerating)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(themeColor.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 18, y: 6)
    }
}

private func limitedAISourceText(originalText: String, summary: String?, title: String) -> String {
    let summaryPart = (summary ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let sourcePart = originalText
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let limitedSummary = String(summaryPart.prefix(700))
    let limitedSource = String(sourcePart.prefix(1300))

    return """
    Study Set Title: \(title)

    Key Summary:
    \(limitedSummary)

    Source Excerpt:
    \(limitedSource)
    """
}
