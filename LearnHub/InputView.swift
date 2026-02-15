import SwiftUI
import UIKit
import SwiftData
import VisionKit
import Shimmer
import SwiftUIIntrospect

struct InputView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query(sort: \StudyFolder.dateCreated, order: .reverse) private var studyFolders: [StudyFolder]
    @StateObject private var gamificationManager = GamificationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @EnvironmentObject private var guideManager: GuideManager
    @AppStorage(ModelSettings.Keys.preference) private var modelPreferenceRaw: String = AIModelPreference.automatic.rawValue
    @AppStorage(ModelSettings.Keys.groqApiKey) private var storedGroqKey: String = ""
    
    // Study-set creation modes.
    enum InputMode: String, CaseIterable, Identifiable {
        case content = "From Content"
        case topic = "Learn Topic"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .content: return "doc.text"
            case .topic: return "lightbulb"
            }
        }
        
        var description: String {
            switch self {
            case .content: return "Generate content from your notes, textbook, or documents"
            case .topic: return "Learn something new - AI teaches you the topic"
            }
        }
    }
    
    @State private var selectedMode: InputMode
    @State private var inputText: String = ""
    @State private var topicDescription: String = ""
    @State private var title: String = ""
    
    init(mode: InputMode = .content) {
        _selectedMode = State(initialValue: mode)
    }
    
    @State private var selectedIconId: String = "book"
    @State private var isIconPickerExpanded: Bool = false
    @State private var selectedFolder: StudyFolder? = nil
    @State private var isFolderPickerExpanded: Bool = false
    @State private var activeSheet: ActiveSheet?
    @State private var isGenerating = false
    private let characterLimit = 10000
    
    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }
    
    enum ActiveSheet: Int, Identifiable {
        case scanner = 0
        case filePicker = 1
        
        var id: Int { rawValue }
    }
    
    // Generation settings.
    @State private var questionCount: Double = 5
    @State private var flashcardCount: Double = 10
    @State private var summaryStyle: AIService.SummaryStyle = .paragraph
    @State private var summaryWordCount: Double = 150
    @State private var summaryDifficulty: AIService.SummaryDifficulty = .intermediate
    @State private var fallbackNotice: String? = nil
    @State private var generationError: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                
                if selectedMode == .content {
                    sourceMaterialSection
                } else {
                    topicSection
                }
                
                configurationSection
                actionSection
            }
            .scrollDismissesKeyboard(.interactively)
            .introspect(.scrollView, on: .iOS(.v17, .v18)) { scrollView in
                scrollView.keyboardDismissMode = .interactive
                scrollView.delaysContentTouches = false
            }
            .navigationTitle("New Study Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(item: $activeSheet) { item in
                switch item {
                case .scanner:
                    ScannerView(scannedText: $inputText)
                case .filePicker:
                    DocumentPicker(fileContent: $inputText)
                }
            }
            .overlayPreferenceValue(GuideTargetPreferenceKey.self) { prefs in
                GeometryReader { proxy in
                    GuideOverlayLayer(
                        guideManager: guideManager,
                        accent: .accentColor,
                        prefs: prefs,
                        geometry: proxy,
                        onSkip: { guideManager.skipGuide() },
                        onAdvance: {
                            guideManager.currentStep = .generateSet
                            guideManager.collapse()
                        }
                    )
                }
            }
            .alert("Generation Failed", isPresented: Binding(
                get: { generationError != nil },
                set: { if !$0 { generationError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    HapticsManager.shared.playTap()
                    generationError = nil
                }
            } message: {
                if let generationError {
                    Text(generationError)
                }
            }
        }
    }
    
    private var canGenerate: Bool {
        if title.isEmpty { return false }
        switch selectedMode {
        case .content:
            return !inputText.isEmpty
        case .topic:
            return !topicDescription.isEmpty
        }
    }

    private var preference: AIModelPreference {
        AIModelPreference(rawValue: modelPreferenceRaw) ?? .automatic
    }
    
    private var mustUseGroq: Bool {
        switch preference {
        case .groqOnly:
            return true
        case .automatic:
            return !ModelSettings.appleIntelligenceAvailable
        }
    }
    
    private func generateContent() {
        HapticsManager.shared.playTap()

        let trimmedKey = storedGroqKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if mustUseGroq && trimmedKey.isEmpty {
            generationError = "Add your Groq API key in Model Settings."
            return
        }

        fallbackNotice = nil
        generationError = nil
        isGenerating = true

        Task {
            let service = AIService.shared
            let previewNotice = await service.previewFallbackNoticeForCurrentPreference()
            await MainActor.run { fallbackNotice = previewNotice }
            await service.clearFallbackNotice()

            do {
                switch selectedMode {
                case .content:
                    let summary = try await service.generateSummary(
                        from: inputText,
                        style: summaryStyle,
                        wordCount: Int(summaryWordCount),
                        difficulty: summaryDifficulty
                    )

                    let questionsData = try await service.generateQuestions(from: inputText, count: Int(questionCount))
                    let flashcardsData = try await service.generateFlashcards(from: inputText, count: Int(flashcardCount))

                    let newSet = StudySet(title: title, originalText: inputText, summary: summary, mode: .content, iconId: selectedIconId)
                    newSet.folder = selectedFolder
                    modelContext.insert(newSet)

                    for q in questionsData {
                        let question = Question(prompt: q.question, answer: q.answer, options: q.options, explanation: q.explanation)
                        question.studySet = newSet
                    }

                    for f in flashcardsData {
                        let card = Flashcard(front: f.front, back: f.back)
                        card.studySet = newSet
                    }

                case .topic:
                    let guide = try await service.generateTopicGuide(
                        topic: topicDescription,
                        style: summaryStyle,
                        wordCount: Int(summaryWordCount),
                        difficulty: summaryDifficulty
                    )

                    let questionsData = try await service.generateTopicQuestions(
                        topic: topicDescription,
                        count: Int(questionCount),
                        difficulty: summaryDifficulty
                    )

                    let flashcardsData = try await service.generateTopicFlashcards(
                        topic: topicDescription,
                        count: Int(flashcardCount),
                        difficulty: summaryDifficulty
                    )

                    let newSet = StudySet(title: title, originalText: topicDescription, summary: guide, mode: .topic, iconId: selectedIconId)
                    newSet.folder = selectedFolder
                    modelContext.insert(newSet)

                    for q in questionsData {
                        let question = Question(prompt: q.question, answer: q.answer, options: q.options, explanation: q.explanation)
                        question.studySet = newSet
                    }

                    for f in flashcardsData {
                        let card = Flashcard(front: f.front, back: f.back)
                        card.studySet = newSet
                    }
                }

                let runtimeNotice = await service.popFallbackNotice()

                // Track study-set creation for XP/achievements.
                gamificationManager.recordStudySetCreated(profile: profile, context: modelContext)

                await MainActor.run {
                    fallbackNotice = runtimeNotice ?? fallbackNotice
                    isGenerating = false
                    guideManager.advanceAfterGeneratedSet()
                    dismiss()
                }

            } catch {
                print("Error generating content: \(error)")
                await MainActor.run {
                    isGenerating = false
                    generationError = AIService.formatError(error)
                }
            }
        }
    }
    
    // MARK: - Form sections
    
    private var detailsSection: some View {
        Section {
            TextField(selectedMode == .content ? "Title (e.g., Biology Chapter 1)" : "Title (e.g., Learn Calculus)", text: $title)
                .font(.headline)
            
            // Icon picker for the study set.
            DisclosureGroup(isExpanded: $isIconPickerExpanded) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(StudySetIcon.allIcons) { icon in
                        Button(action: {
                            HapticsManager.shared.playTap()
                            selectedIconId = icon.id
                        }) {
                            ZStack {
                                Circle()
                                    .fill(selectedIconId == icon.id ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
                                    .frame(width: 48, height: 48)
                                
                                Image(systemName: icon.systemName)
                                    .font(.system(size: 20))
                                    .foregroundColor(selectedIconId == icon.id ? .white : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            } label: {
                HStack {
                    Text("Icon")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !isIconPickerExpanded, let selectedIcon = StudySetIcon.allIcons.first(where: { $0.id == selectedIconId }) {
                        Image(systemName: selectedIcon.systemName)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Optional folder assignment.
            if !studyFolders.isEmpty {
                DisclosureGroup(isExpanded: $isFolderPickerExpanded) {
                    VStack(spacing: 8) {
                        // Clear folder selection.
                        Button(action: {
                            HapticsManager.shared.playTap()
                            selectedFolder = nil
                        }) {
                            HStack {
                                Image(systemName: "folder.badge.minus")
                                    .foregroundColor(.secondary)
                                Text("None")
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedFolder == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Divider()
                        
                        ForEach(studyFolders) { folder in
                            Button(action: {
                                HapticsManager.shared.playTap()
                                selectedFolder = folder
                            }) {
                                HStack {
                                    Image(systemName: StudySetIcon.icon(for: folder.iconId)?.systemName ?? "folder.fill")
                                        .foregroundColor(themeManager.primaryColor)
                                    Text(folder.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedFolder == folder {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            if folder != studyFolders.last {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } label: {
                    HStack {
                        Text("Folder")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(selectedFolder?.name ?? "None")
                            .font(.subheadline)
                            .foregroundColor(selectedFolder == nil ? .secondary : .primary)
                    }
                }
            }
        } header: {
            Text("Study Set Details")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
        }
    }
    
    private var sourceMaterialSection: some View {
        Section {
            VStack(spacing: 15) {
                HStack(spacing: 14) {
                    // Card-style action to scan paper notes.
                    Button(action: {
                        HapticsManager.shared.playTap()
                        activeSheet = .scanner
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.12))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "doc.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }

                            Text("Scan")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("Use camera to import pages")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel("Scan documents")
                    .accessibilityHint("Open camera scanner to capture pages")

                    // Card-style action to import a document.
                    Button(action: {
                        HapticsManager.shared.playTap()
                        activeSheet = .filePicker
                    }) {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.12))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "arrow.up.doc")
                                    .font(.title2)
                                    .foregroundColor(.accentColor)
                            }

                            Text("Upload")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("Import a PDF or document")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentColor.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .buttonStyle(PressScaleButtonStyle())
                    .accessibilityLabel("Upload document")
                    .accessibilityHint("Choose a file to import its text")
                }
                
                let editorPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
                // Use a UITextView-backed editor for consistent placeholder alignment.
                PlaceholderTextView(
                    text: $inputText,
                    placeholder: "Type or paste your notes here...\nOr import above",
                    padding: editorPadding
                )
                .frame(minHeight: 150)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(8)
                .onChange(of: inputText) { _, newValue in
                    if newValue.count > characterLimit {
                        inputText = String(newValue.prefix(characterLimit))
                    }
                }
                
                HStack {
                    Spacer()
                    Text("\(inputText.count)/\(characterLimit)")
                    .font(.caption)
                    .foregroundColor(inputText.count >= characterLimit ? .red : .secondary)
                }
                .padding(.trailing, 4)
            }
            .padding(.vertical, 5)
        } header: {
            Text("Source Material")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
        }
    }
    
    private var topicSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.accentColor)
                    Text("AI will teach you this topic")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                let editorPadding = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
                PlaceholderTextView(
                    text: $topicDescription,
                    placeholder: "Describe what you want to learn...",
                    padding: editorPadding
                )
                .frame(minHeight: 180)
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(8)
            }
            .padding(.vertical, 5)
        } header: {
            Text("Topic to Learn")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
        }
    }
    
    private var configurationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Questions")
                    Spacer()
                    Text("\(Int(questionCount))")
                        .foregroundColor(.secondary)
                        .bold()
                }
                Slider(value: $questionCount, in: 1...20, step: 1)
                    .tint(.accentColor)
                    .onChange(of: questionCount) { _, _ in
                        HapticsManager.shared.playTap()
                    }
                    .accessibilityValue("\(Int(questionCount)) questions")
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Flashcards")
                    Spacer()
                    Text("\(Int(flashcardCount))")
                        .foregroundColor(.secondary)
                        .bold()
                }
                Slider(value: $flashcardCount, in: 1...30, step: 1)
                    .tint(.accentColor)
                    .onChange(of: flashcardCount) { _, _ in
                        HapticsManager.shared.playTap()
                    }
                    .accessibilityValue("\(Int(flashcardCount)) flashcards")
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(selectedMode == .content ? "Summary Style" : "Guide Style")
                Picker("Style", selection: $summaryStyle) {
                    ForEach(AIService.SummaryStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: summaryStyle) { _, _ in
                    HapticsManager.shared.playTap()
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(selectedMode == .content ? "Summary Word Count" : "Guide Word Count")
                    Spacer()
                    Text("\(Int(summaryWordCount))")
                        .foregroundColor(.secondary)
                        .bold()
                }
                Slider(value: $summaryWordCount, in: 50...500, step: 10)
                    .tint(.accentColor)
                    .onChange(of: summaryWordCount) { _, _ in
                        HapticsManager.shared.playTap()
                    }
                    .accessibilityValue("\(Int(summaryWordCount)) words")
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Difficulty Level")
                Picker("Difficulty", selection: $summaryDifficulty) {
                    ForEach(AIService.SummaryDifficulty.allCases) { difficulty in
                        Text(difficulty.rawValue).tag(difficulty)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: summaryDifficulty) { _, _ in
                    HapticsManager.shared.playTap()
                }
            }
        } header: {
            Text("Generation Settings")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
        }
    }
    
    private var actionSection: some View {
        Section {
            Button(action: generateContent) {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 5)
                            Text("Generating...")
                    } else {
                        Image(systemName: selectedMode == .content ? "sparkles" : "brain.head.profile")
                        Text(selectedMode == .content ? "Generate Study Set" : "Generate Learning Set")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .bold()
                .shimmering(active: isGenerating)
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(!canGenerate || isGenerating)
            .listRowBackground(
                (!canGenerate || isGenerating) ? Color.gray : Color.accentColor
            )
            .foregroundColor(.white)
            .guideTarget(.inputGenerate)

            if let fallbackNotice {
                Label {
                    Text(fallbackNotice)
                        .font(.footnote)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundColor(.secondary)
                .padding(.top, 6)
            }
        }
    }
}

// UITextView-backed editor for accurate placeholder positioning.
private struct PlaceholderTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var padding: EdgeInsets

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.isScrollEnabled = true
        tv.backgroundColor = .systemBackground
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textContainerInset = UIEdgeInsets(top: padding.top, left: padding.leading, bottom: padding.bottom, right: padding.trailing)
        tv.textContainer.lineFragmentPadding = 0

        // Placeholder label layered inside the text view.
        let label = UILabel()
        label.text = placeholder
        label.numberOfLines = 0
        label.textColor = .placeholderText
        label.font = tv.font
        label.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(label)

        // Align placeholder to the text container insets.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: padding.leading + 2),
            label.trailingAnchor.constraint(equalTo: tv.trailingAnchor, constant: -padding.trailing - 2),
            label.topAnchor.constraint(equalTo: tv.topAnchor, constant: padding.top),
        ])

        context.coordinator.placeholderLabel = label
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        weak var placeholderLabel: UILabel?

        init(text: Binding<String>) {
            self._text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
        }
    }
}
