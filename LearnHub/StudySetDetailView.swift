import SwiftUI
import SwiftData

struct StudySetDetailView: View {
    let studySet: StudySet
    @EnvironmentObject private var guideManager: GuideManager
    @Query private var profiles: [UserProfile]
    @State private var selectedTab: Int = 0
    @State private var isShowingShareSheet = false

    private var username: String {
        profiles.first?.username ?? "Student"
    }
    
    private var isTopicMode: Bool {
        studySet.studySetMode == .topic
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                SummaryView(summary: studySet.summary ?? "No summary available.", isGuide: isTopicMode)
                    .tabItem {
                        Label(isTopicMode ? "Guide" : "Summary", systemImage: isTopicMode ? "book.fill" : "text.alignleft")
                    }
                    .tag(0)
                
                QuestionsView(studySet: studySet)
                    .tabItem {
                        Label("Questions", systemImage: "list.bullet.clipboard")
                    }
                    .tag(1)
                
                FlashcardsView(studySet: studySet)
                    .tabItem {
                        Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                    }
                    .tag(2)
                
                StudyChatView(studySet: studySet)
                    .tabItem {
                        Label("Tutor", systemImage: "brain.head.profile")
                    }
                    .tag(3)
            }
            .onAppear {
                if guideManager.currentStep == .openSet {
                    guideManager.advanceAfterOpenedSet()
                }
            }
            .onChange(of: selectedTab) { _, _ in
                HapticsManager.shared.lightImpact()
            }
        }
        .navigationTitle(studySet.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share to Explore")
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ShareStudySetView(studySet: studySet, authorName: username)
        }
        .overlayPreferenceValue(GuideTargetPreferenceKey.self) { prefs in
            if guideManager.isActive {
                GeometryReader { proxy in
                    GuideOverlayLayer(
                        guideManager: guideManager,
                        accent: .accentColor,
                        prefs: prefs,
                        geometry: proxy,
                        onSkip: { guideManager.skipGuide() },
                        onAdvance: nil
                    )
                }
            }
        }
    }
}
