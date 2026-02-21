import SwiftUI
import SwiftData

struct ExploreView: View {
    @State private var sets: [SharedStudySet] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var filteredSets: [SharedStudySet] {
        if searchText.isEmpty {
            return sets
        }
        return sets.filter { set in
            set.title.localizedCaseInsensitiveContains(searchText) ||
            (set.authorName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (set.summary?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        Group {
            if isLoading && sets.isEmpty {
                ProgressView("Loading Explore")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, sets.isEmpty {
                ContentUnavailableView {
                    Label("Explore unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await load(force: true) }
                    }
                }
            } else if sets.isEmpty {
                ContentUnavailableView {
                    Label("No shared sets yet", systemImage: "globe")
                } description: {
                    Text("Be the first to share a study set.")
                }
            } else if filteredSets.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }

                        ForEach(filteredSets) { sharedSet in
                            NavigationLink {
                                ExploreStudySetPreviewView(sharedSet: sharedSet)
                            } label: {
                                ExploreStudySetRow(sharedSet: sharedSet)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .refreshable {
                    await load(force: true)
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search shared sets")
        .task {
            await load(force: false)
        }
    }

    private func load(force: Bool) async {
        if isLoading { return }
        if !force && !sets.isEmpty { return }

        isLoading = true
        errorMessage = nil

        do {
            sets = try await ExploreService.shared.fetchSharedStudySets(limit: 40)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct ExploreStudySetRow: View {
    let sharedSet: SharedStudySet

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: StudySetIcon.icon(for: sharedSet.iconId)?.systemName ?? "book.closed.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                MathTextView(sharedSet.title, fontSize: 18, forceBold: true)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    if let author = sharedSet.authorName, !author.isEmpty {
                        Label(author, systemImage: "person.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Label("\(sharedSet.questionsCount ?? sharedSet.questions?.count ?? 0)", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Label("\(sharedSet.flashcardsCount ?? sharedSet.flashcards?.count ?? 0)", systemImage: "rectangle.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct ExploreStudySetPreviewView: View {
    @State var sharedSet: SharedStudySet

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StudySet.dateCreated, order: .reverse) private var studySets: [StudySet]
    @Environment(\.dismiss) private var dismiss

    @State private var saveState: SaveState = .idle
    @State private var showReportSheet = false
    @State private var showReportSuccess = false
    @State private var selectedPreviewTab = 0
    @State private var showAlreadySavedAlert = false
    @State private var reportFeedbackMessage: String?
    @State private var isFetchingDetails = false

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await saveToMySets() }
                } label: {
                    HStack(spacing: 10) {
                        if isFetchingDetails || saveState == .saving {
                            ProgressView()
                        } else {
                            switch saveState {
                            case .idle: Image(systemName: "tray.and.arrow.down.fill")
                            case .saved: Image(systemName: "checkmark.circle.fill")
                            case .failed: Image(systemName: "exclamationmark.circle.fill")
                            default: EmptyView()
                            }
                        }
                        Text(saveButtonTitle)
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(saveState != .idle || isFetchingDetails)

                VStack(alignment: .leading, spacing: 12) {
                    MathTextView(sharedSet.title, fontSize: 26, forceBold: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let shortDescription = sharedSet.shortDescription, !shortDescription.isEmpty {
                        MathTextView(shortDescription, fontSize: 16)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let summary = sharedSet.summary, !summary.isEmpty {
                        MathTextView(summary, fontSize: 16)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 14) {
                        if let author = sharedSet.authorName, !author.isEmpty {
                            Label(author, systemImage: "person.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                        }
                        Spacer()
                        
                        iconLabel(count: sharedSet.questionsCount ?? sharedSet.questions?.count ?? 0, icon: "questionmark.circle")
                        iconLabel(count: sharedSet.flashcardsCount ?? sharedSet.flashcards?.count ?? 0, icon: "rectangle.on.rectangle")
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 8)

                Picker("Content", selection: $selectedPreviewTab) {
                    Text("Summary").tag(0)
                    Text("Questions").tag(1)
                    Text("Flashcards").tag(2)
                }
                .pickerStyle(.segmented)
            }

            if isFetchingDetails {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading content...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 20)
                }
            } else {
                contentSections
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if sharedSet.questions == nil || sharedSet.flashcards == nil {
                await fetchDetails()
            }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        showReportSheet = true
                    }
                } label: {
                    Label("Report Content", systemImage: "flag")
                }
            }
        }
        .alert("Already Saved", isPresented: $showAlreadySavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This study set is already in My Sets.")
        }
        .overlay(alignment: .bottom) {
            if case .failed(let message) = saveState {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(Color.red.cornerRadius(10))
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if showReportSheet {
                reportPickerOverlay
            }
            if showReportSuccess {
                reportSuccessOverlay
            }
        }
    }

    private func iconLabel(count: Int, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var contentSections: some View {
        if selectedPreviewTab == 0 {
            Section("Summary") {
                if let summary = sharedSet.summary, !summary.isEmpty {
                    MathTextView(summary, fontSize: 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let shortDescription = sharedSet.shortDescription, !shortDescription.isEmpty {
                    MathTextView(shortDescription, fontSize: 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No summary available for this set.")
                        .foregroundStyle(.secondary)
                }
            }
        }

        if selectedPreviewTab == 1 {
            Section("Questions") {
                let questions = sharedSet.questions ?? []
                if questions.isEmpty {
                    Text("No questions in this set.")
                        .foregroundStyle(.secondary)
                }
                ForEach(questions) { question in
                    VStack(alignment: .leading, spacing: 8) {
                        MathTextView(question.prompt, fontSize: 16, forceBold: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        MathTextView(question.answer, fontSize: 15)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
            }
        }

        if selectedPreviewTab == 2 {
            Section("Flashcards") {
                let flashcards = sharedSet.flashcards ?? []
                if flashcards.isEmpty {
                    Text("No flashcards in this set.")
                        .foregroundStyle(.secondary)
                }
                ForEach(flashcards) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        MathTextView(card.front, fontSize: 16, forceBold: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        MathTextView(card.back, fontSize: 15)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var reportPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { showReportSheet = false }
                }
            
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Report Content")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { showReportSheet = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text("Why are you reporting this study set? We take community safety seriously.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    Button {
                        withAnimation { showReportSheet = false }
                        Task { await submitReport(reason: "Spam or Advertising") }
                    } label: {
                        reportOption(title: "Spam or Advertising", icon: "megaphone")
                    }
                    
                    Button {
                        withAnimation { showReportSheet = false }
                        Task { await submitReport(reason: "Inappropriate Content") }
                    } label: {
                        reportOption(title: "Inappropriate Content", icon: "hand.raised")
                    }
                    
                    Button {
                        withAnimation { showReportSheet = false }
                        Task { await submitReport(reason: "Copyright Violation") }
                    } label: {
                        reportOption(title: "Copyright Violation", icon: "c.circle")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
            .padding(.horizontal, 24)
            .transition(.scale.combined(with: .opacity))
        }
        .zIndex(100)
    }

    private var reportSuccessOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { showReportSuccess = false }
                }
            
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                
                Text("Report Submitted")
                    .font(.headline)
                
                Text(reportFeedbackMessage ?? "Thanks. This content has been submitted for review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { showReportSuccess = false }
                } label: {
                    Text("Done")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.15), radius: 14, y: 6)
            .transition(.scale.combined(with: .opacity))
        }
        .zIndex(110)
    }

    private func reportOption(title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var saveButtonTitle: String {
        if isFetchingDetails { return "Loading Content..." }
        switch saveState {
        case .idle:
            return "Save to My Sets"
        case .saving:
            return "Saving..."
        case .saved:
            return "Saved to My Sets"
        case .failed:
            return "Try Saving Again"
        }
    }

    @MainActor
    private func fetchDetails() async {
        isFetchingDetails = true
        do {
            sharedSet = try await ExploreService.shared.fetchFullStudySet(id: sharedSet.id)
        } catch {
            reportFeedbackMessage = "Could not load full content: \(error.localizedDescription)"
            showReportSuccess = true
        }
        isFetchingDetails = false
    }

    @MainActor
    private func saveToMySets() async {
        guard saveState != .saving else { return }

        // Ensure we have details before cloning
        if sharedSet.questions == nil || sharedSet.flashcards == nil {
            await fetchDetails()
        }
        
        guard sharedSet.questions != nil else {
            saveState = .failed("Could not load content to save.")
            return
        }

        if studySets.contains(where: { $0.importedFromSharedId == sharedSet.id }) {
            showAlreadySavedAlert = true
            HapticsManager.shared.error()
            return
        }

        saveState = .saving

        let localSet = ExploreCloneBuilder.cloneToLocalStudySet(from: sharedSet)

        modelContext.insert(localSet)

        do {
            try modelContext.save()
            let updatedSets = [localSet] + studySets
            GamificationManager.shared.syncStudySets(updatedSets)
            saveState = .saved
            HapticsManager.shared.success()
            Task {
                await ExploreService.shared.incrementDownloadCount(setId: sharedSet.id)
            }

            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        } catch {
            saveState = .failed(error.localizedDescription)
            HapticsManager.shared.error()
        }
    }

    @MainActor
    private func submitReport(reason: String) async {
        do {
            try await ExploreService.shared.submitReview(snapshotID: sharedSet.id, reason: reason)
            reportFeedbackMessage = "Thanks. This content has been submitted for review."
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showReportSuccess = true
            }
            HapticsManager.shared.success()
        } catch {
            reportFeedbackMessage = error.localizedDescription
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showReportSuccess = true
            }
            HapticsManager.shared.error()
        }
    }
}

