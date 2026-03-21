// Root tab container and home screen composition for LearnHub.

import SwiftUI
import SwiftData
import ConfettiSwiftUI

// MARK: - App tab configuration
enum AppTab: Int, CaseIterable {
    case shop = 0
    case achievements = 1
    case home = 2
    case profile = 3
    case settings = 4
    
    var title: String {
        switch self {
        case .shop: return "Shop"
        case .achievements: return "Achievements"
        case .home: return "Home"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }
    
    var icon: String {
        switch self {
        case .shop: return "bag.fill"
        case .achievements: return "trophy.fill"
        case .home: return "house.fill"
        case .profile: return "person.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

private enum HomeSubtab: String, CaseIterable {
    case mySets = "My Sets"
    case explore = "Explore"
}

private struct DeepLinkAlert: Identifiable {
    let id = UUID()
    let message: String
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \StudySet.dateCreated, order: .reverse) private var studySets: [StudySet]
    @Query(sort: \StudyFolder.dateCreated, order: .reverse) private var studyFolders: [StudyFolder]
    @Query private var profiles: [UserProfile]
    @StateObject private var gamificationManager = GamificationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @EnvironmentObject private var guideManager: GuideManager
    @State private var isShowingInputSheet = false
    @State private var inputMode: InputView.InputMode = .content
    @State private var showStudySetSourceDialog = false
    @State private var isShowingCreateFolderSheet = false
    @State private var folderToEdit: StudyFolder? = nil
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var setToRename: StudySet? = nil
    @State private var isShowingRenameSheet: Bool = false
    @State private var renameTitle: String = ""
    @State private var renameIconId: String = "book"
    @State private var setMovingToFolder: StudySet? = nil
    @State private var isShowingMoveToFolderSheet: Bool = false
    @State private var hasRequestedNotifications = false
    @State private var navigationPath = NavigationPath()
    @State private var isShowingDailyMix = false
    @State private var isFoldersExpanded = true
    @State private var isStudySetsExpanded = true
    @State private var selectedTab: AppTab = .home
    @State private var selectedHomeSubtab: HomeSubtab = .mySets
    @State private var setToShare: StudySet? = nil
    @State private var deepLinkedSharedSet: SharedStudySet? = nil
    @State private var deepLinkAlert: DeepLinkAlert? = nil
    @State private var levelUpConfettiCounter = 0
    
    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }

    private var filteredStudySets: [StudySet] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return studySets.filter { $0.folder == nil }
        }
        return studySets.filter { set in
            set.title.range(of: text, options: .caseInsensitive) != nil
            || (set.summary?.range(of: text, options: .caseInsensitive) != nil)
            || (set.originalText.range(of: text, options: .caseInsensitive) != nil)
        }
    }
    
    private var filteredFolders: [StudyFolder] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return studyFolders
        }
        return studyFolders.filter { folder in
            folder.name.range(of: text, options: .caseInsensitive) != nil
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab: Shop storefront
            NavigationStack {
                ShopView()
            }
            .tabItem {
                Label(AppTab.shop.title, systemImage: AppTab.shop.icon)
            }
            .tag(AppTab.shop)
            
            // Tab: Achievements overview
            NavigationStack {
                AchievementsView()
            }
            .tabItem {
                Label(AppTab.achievements.title, systemImage: AppTab.achievements.icon)
            }
            .tag(AppTab.achievements)
            
            // Tab: Home (default)
            homeView
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.icon)
                }
                .tag(AppTab.home)
            
            // Tab: Profile and stats
            NavigationStack {
                ProfileView()
                    .environmentObject(guideManager)
            }
            .tabItem {
                Label(AppTab.profile.title, systemImage: AppTab.profile.icon)
            }
            .tag(AppTab.profile)
            
            // Tab: Model settings and preferences
            NavigationStack {
                ModelSettingsView()
                    .environmentObject(guideManager)
            }
            .tabItem {
                Label(AppTab.settings.title, systemImage: AppTab.settings.icon)
            }
            .tag(AppTab.settings)
        }
        .tint(themeManager.primaryColor)
        .onAppear {
            themeManager.updateTheme(for: profile.selectedThemeId)
        }
        .onChange(of: profile.selectedThemeId) { _, newValue in
            themeManager.updateTheme(for: newValue)
        }
        .onChange(of: studySets) { _, newSets in
            gamificationManager.syncStudySets(newSets)
        }
        .onAppear {
            gamificationManager.syncStudySets(studySets)
        }
        .overlay(alignment: .top) {
            // Transient banner when an achievement unlocks.
            if gamificationManager.showAchievementUnlocked && !isSearching, let achievement = gamificationManager.unlockedAchievement {
                AchievementUnlockedView(achievement: achievement)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                    .padding(.top, 50)
            }
        }
        .overlay(alignment: .top) {
            // Transient banner when the user levels up.
            if gamificationManager.showLevelUp && !isSearching {
                LevelUpView(level: gamificationManager.newLevel)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(101)
                    .padding(.top, 100)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: (gamificationManager.showAchievementUnlocked && !isSearching))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: (gamificationManager.showLevelUp && !isSearching))
        .confettiCannon(counter: $levelUpConfettiCounter)
        .onChange(of: gamificationManager.showLevelUp) { _, isShowing in
            if isShowing {
                levelUpConfettiCounter += 1
            }
        }
        .task {
            guard hasRequestedNotifications == false else { return }
            hasRequestedNotifications = true
            await NotificationManager.shared.bootstrapNotifications(for: profile)
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        if url.scheme == "learnhub" {
            if url.host == "flashcards", let components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                if let setIDString = components.queryItems?.first(where: { $0.name == "setID" })?.value,
                   let setID = UUID(uuidString: setIDString),
                   let set = studySets.first(where: { $0.id == setID }) {
                    selectedTab = .home
                    navigationPath.append(set)
                }
                return
            }

            if url.host == "stats" {
                // Deep-link from widgets or notifications to the Profile tab.
                selectedTab = .profile
                return
            }
        }

        guard let shortCode = extractSharedSetShortCode(from: url) else {
            return
        }

        Task {
            await openSharedSetFromDeepLink(shortCode: shortCode)
        }
    }

    private func extractSharedSetShortCode(from url: URL) -> String? {
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if url.scheme == "learnhub" {
            if url.host == "share" {
                if let first = pathComponents.first, !first.isEmpty {
                    return first
                }

                if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                   !code.isEmpty {
                    return code
                }
            }
            return nil
        }

        let isWebDeepLink = (url.scheme == "https" || url.scheme == "http")
            && (url.host == "learnhub.shaarav.xyz" || url.host == "www.learnhub.shaarav.xyz")
        guard isWebDeepLink else {
            return nil
        }

        if pathComponents.count >= 2,
           pathComponents[0].lowercased() == "share",
           !pathComponents[1].isEmpty {
            return pathComponents[1]
        }

        if pathComponents.count == 1,
           pathComponents[0].lowercased() == "share",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code
        }

        return nil
    }

    @MainActor
    private func openSharedSetFromDeepLink(shortCode: String) async {
        selectedTab = .home
        selectedHomeSubtab = .explore
        deepLinkAlert = nil

        do {
            let sharedSet = try await ExploreService.shared.fetchFullStudySet(shortCode: shortCode)
            deepLinkedSharedSet = sharedSet
        } catch {
            deepLinkAlert = DeepLinkAlert(message: error.localizedDescription)
        }
    }
    
    // MARK: - Home tab content
    private var homeView: some View {
        NavigationStack(path: $navigationPath) {
            let isCreationDialogVisible = showStudySetSourceDialog
            ZStack {
                OLEDBackground()
                
                if selectedHomeSubtab == .explore {
                    ExploreView()
                } else {
                    Group {
                        if studySets.isEmpty && studyFolders.isEmpty && searchText.isEmpty {
                    VStack(spacing: 16) {
                        // Daily Mix launcher
                        dailyMixCard
                        
                        // Gamification summary card
                        gamificationHeader

                        Spacer()

                        ContentUnavailableView {
                            Label("No Study Sets", systemImage: "books.vertical")
                        } description: {
                            Text("Tap the + button to create your first study set.")
                        }

                        Spacer()
                    }
                } else if filteredStudySets.isEmpty && filteredFolders.isEmpty {
                    VStack(spacing: 16) {
                        // Daily Mix launcher
                        dailyMixCard
                        
                        // Show gamification summary even in empty search states.
                        gamificationHeader

                        Spacer()

                        ContentUnavailableView {
                            Label("No Results", systemImage: "magnifyingglass")
                        } description: {
                            Text("No study sets match \"\(searchText)\".")
                        }

                        Spacer()
                    }
                } else {
                    List {
                        // Pin Daily Mix at top of the list.
                        Section {
                            dailyMixCard
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                        .listRowSeparator(.hidden)
                        
                        // Pin the gamification summary below Daily Mix.
                        Section {
                            gamificationHeader
                                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                                .listRowBackground(Color.clear)
                        }
                        .listRowSeparator(.hidden)
                        
                        // Folder section with optional expand/collapse.
                        if !filteredFolders.isEmpty {
                            Section {
                                // Folder header doubles as expand/collapse control.
                                Button(action: {
                                    withAnimation {
                                        isFoldersExpanded.toggle()
                                    }
                                }) {
                                    HStack {
                                        Text("Folders")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .rotationEffect(.degrees(isFoldersExpanded ? 90 : 0))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)

                                if isFoldersExpanded {
                                    // Adaptive grid sized to available width.
                                    let columns = [
                                        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
                                    ]

                                    LazyVGrid(columns: columns, alignment: .center, spacing: 24) {
                                        ForEach(filteredFolders) { folder in
                                            Button {
                                                navigationPath.append(folder)
                                            } label: {
                                                FolderCard(folder: folder)
                                            }
                                            .buttonStyle(.plain)
                                            .contentShape(RoundedRectangle(cornerRadius: 18))
                                            .overlay(alignment: .topTrailing) {
                                                Menu {
                                                    Button {
                                                        folderToEdit = folder
                                                        isShowingCreateFolderSheet = true
                                                    } label: {
                                                        Label("Rename", systemImage: "pencil")
                                                    }

                                                    Button(role: .destructive) {
                                                        withAnimation {
                                                            modelContext.delete(folder)
                                                        }
                                                    } label: {
                                                        Label("Delete", systemImage: "trash")
                                                    }
                                                } label: {
                                                    Image(systemName: "ellipsis.circle")
                                                        .font(.title3)
                                                        .foregroundColor(.secondary)
                                                        .padding(8)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 20)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        }

                        if !filteredStudySets.isEmpty {
                            Section {
                                // Show study-set header only when folders exist.
                                if !filteredFolders.isEmpty {
                                    Button(action: {
                                        withAnimation {
                                            isStudySetsExpanded.toggle()
                                        }
                                    }) {
                                        HStack {
                                            Text("Study Sets")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .rotationEffect(.degrees(isStudySetsExpanded ? 90 : 0))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets())
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                }
                                
                                if isStudySetsExpanded {
                                    ForEach(filteredStudySets) { set in
                                    ZStack {
                                        NavigationLink(value: set) {
                                            EmptyView()
                                        }
                                        .opacity(0)
                                        
                                        VStack(alignment: .leading, spacing: 12) {
                                            HStack {
                                                Image(systemName: set.icon.systemName)
                                                    .foregroundColor(.white)
                                                    .padding(8)
                                                    .background(Circle().fill(themeManager.primaryColor))
                                                
                                                Text(set.title)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                
                                                Spacer()
                                                
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            HStack(alignment: .center, spacing: 8) {
                                                // Compact date layout to reduce icon-to-text spacing.
                                                HStack(spacing: 4) {
                                                    Image(systemName: "calendar")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text("\(set.dateCreated, style: .date)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }

                                                Spacer()

                                                // Compact badge for study-set mode in list rows.
                                                HStack(spacing: 4) {
                                                    Image(systemName: set.studySetMode == .topic ? "lightbulb.fill" : "doc.text.fill")
                                                        .font(.caption2)
                                                    Text(set.studySetMode == .topic ? "Learning Topic" : "From Content")
                                                        .font(.caption2)
                                                }
                                                .foregroundColor(set.studySetMode == .topic ? .orange : .blue)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background((set.studySetMode == .topic ? Color.orange : Color.blue).opacity(0.14))
                                                .cornerRadius(8)
                                            }
                                        }
                                        .padding()
                                        .glassCard(cornerRadius: 16, strokeOpacity: 0.15)
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .contextMenu {
                                        Button {
                                            setToShare = set
                                        } label: {
                                            Label("Share to Explore", systemImage: "square.and.arrow.up")
                                        }

                                        if !studyFolders.isEmpty {
                                            Menu("Move to Folder", systemImage: "folder") {
                                                ForEach(studyFolders) { folder in
                                                    Button {
                                                        withAnimation {
                                                            set.folder = folder
                                                        }
                                                    } label: {
                                                        Label(folder.name, systemImage: "folder")
                                                    }
                                                }
                                            }
                                        }
                                        
                                        Button {
                                            setToRename = set
                                            renameTitle = set.title
                                            renameIconId = set.iconId
                                            isShowingRenameSheet = true
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        
                                        Button(role: .destructive) {
                                            withAnimation {
                                                modelContext.delete(set)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            HapticsManager.shared.playTap()
                                            // Capture current values before opening rename sheet.
                                            setToRename = set
                                            renameTitle = set.title
                                            renameIconId = set.iconId
                                            isShowingRenameSheet = true
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                        
                                        if !studyFolders.isEmpty {
                                            Button {
                                                HapticsManager.shared.playTap()
                                                setMovingToFolder = set
                                                isShowingMoveToFolderSheet = true
                                            } label: {
                                                Label("Folder", systemImage: "folder")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticsManager.shared.playTap()
                                            withAnimation {
                                                modelContext.delete(set)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    // Improve tap target and VoiceOver summary for custom rows.
                                    .accessibilityElement(children: .combine)
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityLabel("Study set: \(set.title). Created on \(set.dateCreated, style: .date). Mode: \(set.studySetMode == .topic ? "Learning Topic" : "From Content")")
                                    .accessibilityHint("Opens study set details")
                                }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                    .listSectionSpacing(0)
                    .transaction { t in t.animation = nil }
                    .animation(nil, value: searchText)
                } // end list
                    } // end group
                    .searchable(text: $searchText, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search study sets")
                    .animation(.linear(duration: 0.04), value: isSearching)
                } // end else
            }
            .safeAreaInset(edge: .top) {
                homeSubtabPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(.ultraThinMaterial)
            }
            .blur(radius: isCreationDialogVisible ? 1 : 0)
            .allowsHitTesting(!isCreationDialogVisible)
            .overlay {
                if isCreationDialogVisible {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    showStudySetSourceDialog = false
                                }
                            }
                        
                        StudySetSourcePopup(
                            onSelectContent: {
                                HapticsManager.shared.playTap()
                                inputMode = .content
                                isShowingInputSheet = true
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    showStudySetSourceDialog = false
                                }
                            },
                            onSelectTopic: {
                                HapticsManager.shared.playTap()
                                inputMode = .topic
                                isShowingInputSheet = true
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    showStudySetSourceDialog = false
                                }
                            },
                            onDismiss: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    showStudySetSourceDialog = false
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.horizontal, 24)
                        .transition(.scale.combined(with: .opacity))
                    }
                    .ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: StudySet.self) { set in
                StudySetDetailView(studySet: set)
                    .toolbar(.hidden, for: .tabBar)
            }
            .navigationDestination(for: StudyFolder.self) { folder in
                FolderDetailView(folder: folder)
            }
            .sheet(isPresented: $isShowingCreateFolderSheet) {
                CreateFolderView(folderToEdit: folderToEdit)
            }
            .sheet(isPresented: $isShowingMoveToFolderSheet) {
                if let set = setMovingToFolder {
                    MoveToFolderView(studySet: set, studyFolders: studyFolders)
                }
            }
            .sheet(isPresented: Binding(get: { setToShare != nil }, set: { if !$0 { setToShare = nil } })) {
                if let set = setToShare {
                    ShareStudySetView(studySet: set, authorName: profile.username)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LearnHub")
                        .font(.title2.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            HapticsManager.shared.playTap()
                            guideManager.advanceAfterTappedCreate()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                showStudySetSourceDialog = true
                            }
                        } label: {
                            Label("New Study Set", systemImage: "doc.badge.plus")
                        }
                        
                        Button {
                            HapticsManager.shared.playTap()
                            folderToEdit = nil
                            isShowingCreateFolderSheet = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                            
                            Text("New")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(colorScheme == .light ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(themeManager.primaryColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .buttonStyle(PressScaleButtonStyle())
                    .guideTarget(.homeCreate)
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "icloud")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(0.6)
                    .padding(.top, 10)
                    .padding(.leading, 16)
                    .accessibilityLabel("Syncing with iCloud")
                    .allowsHitTesting(false)
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .sheet(item: $deepLinkedSharedSet) { sharedSet in
                NavigationStack {
                    ExploreStudySetPreviewView(sharedSet: sharedSet)
                }
            }
            .alert(item: $deepLinkAlert) { alert in
                Alert(
                    title: Text("Couldn’t Open Share Link"),
                    message: Text(alert.message),
                    dismissButton: .cancel(Text("OK"))
                )
            }
            .fullScreenCover(isPresented: $isShowingDailyMix) {
                DailyMixView()
            }
            .sheet(isPresented: $isShowingInputSheet) {
                InputView(mode: inputMode)
                    .environmentObject(guideManager)
            }
            .sheet(isPresented: Binding(get: { setToRename != nil }, set: { if !$0 { setToRename = nil } })) {
                if let set = setToRename {
                    NavigationStack {
                        ZStack {
                            Color(uiColor: .systemGroupedBackground)
                                .ignoresSafeArea()
                            
                            VStack(spacing: 24) {
                                // Rename sheet header with iconography.
                                VStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(themeManager.primaryGradient)
                                            .frame(width: 80, height: 80)
                                        
                                        Image(systemName: "pencil")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Text("Edit Study Set")
                                        .font(.title2.bold())
                                        .foregroundColor(.primary)
                                }
                                
                                // Rename field for the study set title.
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Title")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    TextField("Enter new title", text: $renameTitle)
                                        .font(.body)
                                        .padding()
                                        .glassCard(cornerRadius: 12)
                                }
                                .padding(.horizontal)
                                
                                // Icon selector for the study set.
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Icon")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                                        ForEach(StudySetIcon.allIcons) { icon in
                                            Button(action: {
                                                HapticsManager.shared.playTap()
                                                renameIconId = icon.id
                                            }) {
                                                ZStack {
                                                    Circle()
                                                        .fill(renameIconId == icon.id ? themeManager.primaryColor : Color(uiColor: .tertiarySystemGroupedBackground))
                                                        .frame(width: 48, height: 48)
                                                    
                                                    Image(systemName: icon.systemName)
                                                        .font(.system(size: 20))
                                                        .foregroundColor(renameIconId == icon.id ? .white : .primary)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                
                                Spacer()
                            }
                            .padding(.top, 40)
                            .padding(.horizontal)
                        }
                        .navigationTitle("")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    HapticsManager.shared.playTap()
                                    setToRename = nil
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    HapticsManager.shared.playTap()
                                    withAnimation {
                                        set.title = renameTitle
                                        set.iconId = renameIconId
                                    }
                                    setToRename = nil
                                } label: {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundColor(themeManager.primaryColor)
                                }
                            }
                        }
                    }
                } else {
                    EmptyView()
                }
            }
            .overlayPreferenceValue(GuideTargetPreferenceKey.self) { prefs in
                GeometryReader { proxy in
                    GuideOverlayLayer(
                        guideManager: guideManager,
                        accent: themeManager.primaryColor,
                        prefs: prefs,
                        geometry: proxy,
                        selectedTab: selectedTab,
                        onSkip: { guideManager.skipGuide() },
                        onAdvance: nil
                    )
                    .zIndex(200)  // Keep guide overlay above lists and sheets.
                }
                .allowsHitTesting(!guideManager.isCollapsed)  // Disable hits when the guide is collapsed.
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                if guideManager.currentStep == .configureModel && newValue == .settings {
                    guideManager.advanceAfterConfiguredModel()
                }
                if guideManager.currentStep == .exploreGamification {
                    guideManager.finishGamification()
                }
            }
        }
    }
    
    // MARK: - Daily Mix launcher
    
    private var hasDailyMixContent: Bool {
        let allQuestions = studySets.flatMap { $0.questions ?? [] }
        let allFlashcards = studySets.flatMap { $0.flashcards ?? [] }

        let dueOrNewQuestionCount = allQuestions.filter { $0.isDueForReview || $0.isNewForReview }.count
        let dueOrNewFlashcardCount = allFlashcards.filter { $0.isDueForReview || $0.isNewForReview }.count

        let canBackfillQuestions = allQuestions.count >= 5
        let canBackfillFlashcards = allFlashcards.count >= 5
        
        // Hide if the user already completed Daily Mix today.
        if gamificationManager.hasDailyMixCompletedToday(profile: profile) {
            return false
        }
        
        return (dueOrNewQuestionCount > 0 || canBackfillQuestions) && (dueOrNewFlashcardCount > 0 || canBackfillFlashcards)
    }
    
    private var dailyMixCard: some View {
        Group {
            if hasDailyMixContent {
                Button {
                    HapticsManager.shared.playTap()
                    isShowingDailyMix = true
                } label: {
                    HStack(spacing: 14) {
                        // Solid icon chip to emphasize the CTA.
                        ZStack {
                            Circle()
                                .fill(themeManager.primaryColor)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "bolt.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Daily Mix")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Keep your streak alive!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .glassCard(cornerRadius: 16, strokeOpacity: 0.15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(themeManager.primaryColor.opacity(0.3), lineWidth: 1.5)
                    )
                    .shadow(color: themeManager.primaryColor.opacity(0.12), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: hasDailyMixContent)
    }
    
    // MARK: - Gamification summary header
    
    private var gamificationHeader: some View {
        HStack(spacing: 16) {
            // Level and XP progress summary.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text("Level \(profile.level)")
                        .font(.subheadline.bold())
                }
                
                // Visual indicator of progress toward next level.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(themeManager.horizontalGradient)
                            .frame(width: geometry.size.width * profile.xpProgress, height: 6)
                    }
                }
                .frame(height: 6)
                
                Text("\(profile.xpToNextLevel) XP to next")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 40)
            
            // Current streak summary.
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundColor(profile.currentStreak > 0 ? .orange : .gray)
                    Text("\(profile.currentStreak)")
                        .font(.title3.bold())
                }
                Text("Streak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            // Current coin balance summary.
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.title3)
                        .foregroundColor(.yellow)
                    Text("\(profile.coins)")
                        .font(.title3.bold())
                }
                Text("Coins")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard(cornerRadius: 16, strokeOpacity: 0.15)
        .padding(.horizontal)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var homeSubtabPicker: some View {
        Picker("Library", selection: $selectedHomeSubtab) {
            ForEach(HomeSubtab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(studySets[index])
            }
        }
    }

}

// MARK: - Folder card

private struct FolderCard: View {
    let folder: StudyFolder
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let iconSize = width * 0.32
            let spacing = width * 0.06

            VStack(spacing: spacing) {
                // Folder icon with themed background.
                Circle()
                    .fill(themeManager.secondaryColor.opacity(0.9))
                    .overlay(
                        Circle()
                            .stroke(themeManager.primaryColor.opacity(0.25), lineWidth: 2)
                    )
                    .frame(width: iconSize, height: iconSize)
                    .overlay(
                        Image(systemName: StudySetIcon.icon(for: folder.iconId)?.systemName ?? "folder.fill")
                            .font(.system(size: iconSize * 0.45, weight: .semibold))
                            .foregroundColor(.white)
                    )

                // Folder name and study-set count.
                VStack(spacing: spacing * 0.7) {
                    Text(folder.name)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.caption2)
                        Text("\((folder.studySets ?? []).count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(themeManager.primaryColor)
                    )
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(10)
            .glassCard(cornerRadius: 18)
        }
        .aspectRatio(1.3, contentMode: .fit)
    }
}

// MARK: - Study-set source popup

private struct StudySetSourcePopup: View {
    let onSelectContent: () -> Void
    let onSelectTopic: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Create a study set")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("Choose how you want to start. Paste existing material or let AI teach you something new.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            VStack(spacing: 12) {
                Button(action: onSelectContent) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.headline)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From Content")
                                .font(.headline)
                            Text("Paste notes, scan with the camera, or import a PDF to generate questions and flashcards.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .buttonStyle(PressScaleButtonStyle())
                
                Button(action: onSelectTopic) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb")
                            .font(.headline)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Learn a Topic")
                                .font(.headline)
                            Text("Tell AI what you want to learn. Get a guided summary, practice questions, and flashcards.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .glassCard(cornerRadius: 12)
                }
                .buttonStyle(.plain)
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: 420)
        .glassCard(cornerRadius: 22)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [StudySet.self, UserProfile.self], inMemory: true)
}

