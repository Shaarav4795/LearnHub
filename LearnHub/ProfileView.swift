import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @StateObject private var gamificationManager = GamificationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @EnvironmentObject private var guideManager: GuideManager
    
    @State private var showEditUsername = false
    @State private var newUsername = ""
    @State private var showTutorial = false
    
    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Primary identity card (avatar, username, level).
                    profileHeader

                    // Level progress and XP totals.
                    levelProgressCard

                    // Streak summary card.
                    streakCard

                    // Snapshot of core performance metrics.
                    statsGrid

                    // Creator credit anchored to the end of the scroll.
                    Text("Created with ♡ by Shaarav4795")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    HapticsManager.shared.playTap()
                    showTutorial = true
                }) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .sheet(isPresented: $showEditUsername) {
            editUsernameSheet
        }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView()
                .environmentObject(themeManager)
                .environmentObject(guideManager)
        }
        .overlayPreferenceValue(GuideTargetPreferenceKey.self) { prefs in
            GeometryReader { proxy in
                GuideOverlayLayer(
                    guideManager: guideManager,
                    accent: themeManager.primaryColor,
                    prefs: prefs,
                    geometry: proxy,
                    onSkip: { guideManager.skipGuide() },
                    onAdvance: { guideManager.finishGamification() }
                )
            }
        }
    }
    
    // MARK: - Profile header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar with themed gradient backing.
            ZStack {
                Circle()
                    .fill(themeManager.primaryGradient)
                    .frame(width: 100, height: 100)
                
                if let avatar = AvatarItem.avatar(for: profile.selectedAvatarId) {
                    Image(avatar.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 75, height: 75)
                }
            }
            .shadow(color: themeManager.primaryColor.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Username with inline edit action.
            HStack {
                Text(profile.username)
                    .font(.title2.bold())
                
                Button(action: {
                    HapticsManager.shared.playTap()
                    newUsername = profile.username
                    showEditUsername = true
                }) {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            
            // Current level badge.
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("Level \(profile.level)")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.yellow.opacity(0.2))
            )
            
            // Coin balance summary.
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(.yellow)
                    .font(.title3)
                Text("\(profile.coins)")
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                Text("coins")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20, strokeOpacity: 0.24)
        .guideTarget(.profileHeader)
    }
    
    // MARK: - Level progress card
    
    private var levelProgressCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Level Progress")
                    .font(.headline)
                Spacer()
                Text("\(profile.totalXP) XP")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Progress bar toward next level.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(themeManager.horizontalGradient)
                        .frame(width: geometry.size.width * profile.xpProgress, height: 16)
                }
            }
            .frame(height: 16)
            
            HStack {
                Text("Level \(profile.level)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(profile.xpToNextLevel) XP to Level \(profile.level + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
    }
    
    // MARK: - Stats grid
    
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                icon: "checkmark.circle.fill",
                color: .green,
                value: "\(profile.totalQuestionsCorrect)",
                label: "Questions Correct"
            )
            
            StatCard(
                icon: "rectangle.stack.fill",
                color: .blue,
                value: "\(profile.totalFlashcardsStudied)",
                label: "Flashcards Studied"
            )
            
            StatCard(
                icon: "doc.text.fill",
                color: .purple,
                value: "\(profile.totalQuizzesTaken)",
                label: "Quizzes Taken"
            )
            
            StatCard(
                icon: "star.fill",
                color: .yellow,
                value: "\(profile.perfectQuizzes)",
                label: "Perfect Scores"
            )
            
            StatCard(
                icon: "book.fill",
                color: .orange,
                value: "\(profile.totalStudySets)",
                label: "Study Sets"
            )
            
            StatCard(
                icon: "trophy.fill",
                color: .yellow,
                value: "\(profile.achievements?.count ?? 0)",
                label: "Achievements"
            )
        }
    }
    
    // MARK: - Streak card
    
    private var streakCard: some View {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundColor(profile.currentStreak > 0 ? .orange : .gray)
                
                Text("\(profile.currentStreak)")
                    .font(.title.bold())
                
                Text("Day Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 80)
            
            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.yellow)
                
                Text("\(profile.longestStreak)")
                    .font(.title.bold())
                
                Text("Best Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
    }
    
    // MARK: - Edit-username sheet
    
    private var editUsernameSheet: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Sheet header with icon.
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(themeManager.primaryGradient)
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "person.text.rectangle")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                        
                        Text("Edit Profile")
                            .font(.title2.bold())
                            .foregroundColor(.primary)
                    }
                    
                    // Username input field.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        TextField("Enter username", text: $newUsername)
                            .font(.body)
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
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
                        showEditUsername = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        HapticsManager.shared.playTap()
                        profile.username = newUsername
                        try? modelContext.save()
                        showEditUsername = false
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.headline)
                            .foregroundColor(themeManager.primaryColor)
                    }
                    .disabled(newUsername.isEmpty)
                }
            }
        }
    }
}

// MARK: - Supporting views

struct StatCard: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2.bold())
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard(cornerRadius: 12, strokeOpacity: 0.2)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(for: [StudySet.self, UserProfile.self], inMemory: true)
}
