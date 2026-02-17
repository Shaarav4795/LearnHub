import SwiftUI
import SwiftData
import Shimmer
import ConfettiSwiftUI
import SwiftUIIntrospect

struct ShopView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @StateObject private var gamificationManager = GamificationManager.shared
    
    @State private var selectedTab: ShopTab = .avatars
    @State private var showPurchaseAlert = false
    @State private var purchaseMessage = ""
    @State private var pendingPurchase: (() -> Void)?
    @State private var selectedItemName = ""
    @State private var selectedItemCost = 0
    @State private var purchaseConfettiCounter = 0
    @State private var isProcessingPurchase = false
    @State private var isCatalogBooting = true
    
    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }
    
    enum ShopTab: String, CaseIterable {
        case avatars = "Avatars"
        case themes = "Themes"
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Coin Balance Header
                coinBalanceHeader
                
                // Tab Picker
                tabPicker
                
                // Content
                ScrollView {
                    if isCatalogBooting {
                        ShopSkeletonView(tab: selectedTab)
                            .padding()
                    } else {
                        switch selectedTab {
                        case .avatars:
                            avatarsGrid
                        case .themes:
                            themesGrid
                        }
                    }
                }
                .introspect(.scrollView, on: .iOS(.v17)) { scrollView in
                    scrollView.keyboardDismissMode = .interactive
                    scrollView.delaysContentTouches = false
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
            .confettiCannon(counter: $purchaseConfettiCounter, num: 28, rainHeight: 720)
            .onAppear {
                guard isCatalogBooting else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isCatalogBooting = false
                    }
                }
            }
            
            if showPurchaseAlert {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        HapticsManager.shared.playTap()
                        withAnimation {
                            showPurchaseAlert = false
                        }
                    }
                    .zIndex(1)
                
                PurchaseConfirmationView(
                    itemName: selectedItemName,
                    itemCost: selectedItemCost,
                    isProcessing: isProcessingPurchase,
                    onConfirm: {
                        guard isProcessingPurchase == false else { return }
                        isProcessingPurchase = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            pendingPurchase?()
                            purchaseConfettiCounter += 1
                            isProcessingPurchase = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showPurchaseAlert = false
                            }
                        }
                    },
                    onCancel: {
                        isProcessingPurchase = false
                        withAnimation {
                            showPurchaseAlert = false
                        }
                    }
                )
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
            }
        }
    }
    
    // MARK: - Coin Balance Header
    
    private var coinBalanceHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Balance")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    
                    Text("\(profile.coins)")
                        .font(.title.bold())
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Level \(profile.level)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("\(profile.totalXP) XP")
                        .font(.subheadline.bold())
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.14), Color.accentColor.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .trailing) {
            CelebrationLottieView(animationName: "celebration", play: true)
                .frame(width: 42, height: 42)
                .opacity(0.22)
                .padding(.trailing, 8)
        }
    }
    
    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        Picker("Shop Category", selection: $selectedTab) {
            ForEach(ShopTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding()
        .onChange(of: selectedTab) { _, _ in
            HapticsManager.shared.playTap()
        }
    }
    
    // MARK: - Avatars Grid
    
    private var avatarsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)
        ], spacing: 14) {
            ForEach(AvatarItem.allAvatars) { avatar in
                AvatarShopCard(
                    avatar: avatar,
                    isOwned: gamificationManager.isItemOwned(avatar.id, itemType: "avatar", profile: profile),
                    isSelected: profile.selectedAvatarId == avatar.id,
                    isLocked: profile.level < avatar.requiredLevel,
                    canAfford: profile.coins >= avatar.cost,
                    onSelect: {
                        _ = gamificationManager.selectAvatar(avatar.id, for: profile, context: modelContext)
                    },
                    onPurchase: {
                        selectedItemName = avatar.name
                        selectedItemCost = avatar.cost
                        pendingPurchase = {
                            if gamificationManager.purchaseAvatar(avatar, for: profile, context: modelContext) {
                                _ = gamificationManager.selectAvatar(avatar.id, for: profile, context: modelContext)
                            }
                        }
                        withAnimation {
                            showPurchaseAlert = true
                        }
                    }
                )
            }
        }
        .padding()
    }
    
    // MARK: - Themes Grid
    
    private var themesGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible())
        ], spacing: 14) {
            ForEach(ThemeItem.allThemes) { theme in
                ThemeShopCard(
                    theme: theme,
                    isOwned: gamificationManager.isItemOwned(theme.id, itemType: "theme", profile: profile),
                    isSelected: profile.selectedThemeId == theme.id,
                    isLocked: profile.level < theme.requiredLevel,
                    canAfford: profile.coins >= theme.cost,
                    onSelect: {
                        _ = gamificationManager.selectTheme(theme.id, for: profile, context: modelContext)
                    },
                    onPurchase: {
                        selectedItemName = theme.name
                        selectedItemCost = theme.cost
                        pendingPurchase = {
                            if gamificationManager.purchaseTheme(theme, for: profile, context: modelContext) {
                                _ = gamificationManager.selectTheme(theme.id, for: profile, context: modelContext)
                            }
                        }
                        withAnimation {
                            showPurchaseAlert = true
                        }
                    }
                )
            }
        }
        .padding()
    }
}

// MARK: - Avatar Shop Card

struct AvatarShopCard: View {
    let avatar: AvatarItem
    let isOwned: Bool
    let isSelected: Bool
    let isLocked: Bool
    let canAfford: Bool
    let onSelect: () -> Void
    let onPurchase: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Avatar Image
            ZStack {
                Circle()
                    .fill(
                        isSelected ?
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 78, height: 78)
                
                if isLocked && !isOwned {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                } else {
                    Image(avatar.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .opacity(isOwned || !isLocked ? 1 : 0.5)
                }
                
                if isSelected {
                    Circle()
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 84, height: 84)
                }
            }
            
            // Name
            Text(avatar.name)
                .font(.caption.bold())
                .foregroundColor(isLocked && !isOwned ? .secondary : .primary)
                .lineLimit(1)
            
            // Status / Price
            if isOwned {
                if isSelected {
                    Text("Equipped")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                } else {
                    Button("Select") {
                        HapticsManager.shared.playTap()
                        onSelect()
                    }
                    .font(.caption2.bold())
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
                    .buttonStyle(PressScaleButtonStyle())
                }
            } else if isLocked {
                Text("Lvl \(avatar.requiredLevel)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            } else {
                Button(action: {
                    HapticsManager.shared.playTap()
                    onPurchase()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.caption2)
                        Text("\(avatar.cost)")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(canAfford ? .yellow : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(canAfford ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.2))
                    .cornerRadius(8)
                }
                .disabled(!canAfford)
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .scaleEffect(isSelected ? 1.02 : 1)
    }
}

// MARK: - Theme Shop Card

struct ThemeShopCard: View {
    let theme: ThemeItem
    let isOwned: Bool
    let isSelected: Bool
    let isLocked: Bool
    let canAfford: Bool
    let onSelect: () -> Void
    let onPurchase: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            themePreview
            themeNameLabel
            themeDescriptionLabel
            statusOrPriceView
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var themePreview: some View {
        Group {
            if theme.id == "rainbow" {
                rainbowPreview
            } else {
                standardPreview
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
        .opacity(isLocked && !isOwned ? 0.5 : 1)
        .overlay {
            if isLocked && !isOwned {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var rainbowPreview: some View {
        HStack(spacing: 4) {
            ForEach([Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple], id: \.self) { color in
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
            }
        }
    }
    
    private var standardPreview: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorFromString(theme.primaryColor))
                .frame(width: 40, height: 40)
            
            Circle()
                .fill(colorFromString(theme.secondaryColor))
                .frame(width: 40, height: 40)
        }
    }
    
    private var themeNameLabel: some View {
        Text(theme.name)
            .font(.subheadline.bold())
            .foregroundColor(isLocked && !isOwned ? .secondary : .primary)
    }
    
    private var themeDescriptionLabel: some View {
        Text(theme.description)
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }
    
    @ViewBuilder
    private var statusOrPriceView: some View {
        if isOwned {
            ownedStatusView
        } else if isLocked {
            lockedStatusView
        } else {
            purchaseButton
        }
    }
    
    @ViewBuilder
    private var ownedStatusView: some View {
        if isSelected {
            Text("Active")
                .font(.caption.bold())
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
        } else {
            Button("Apply") {
                HapticsManager.shared.playTap()
                onSelect()
            }
            .font(.caption.bold())
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.2))
            .cornerRadius(8)
            .buttonStyle(PressScaleButtonStyle())
        }
    }
    
    private var lockedStatusView: some View {
        Text("Requires Level \(theme.requiredLevel)")
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
    }
    
    private var purchaseButton: some View {
        Button(action: {
            HapticsManager.shared.playTap()
            onPurchase()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.caption)
                Text("\(theme.cost)")
                    .font(.caption.bold())
            }
            .foregroundColor(canAfford ? .yellow : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(canAfford ? Color.yellow.opacity(0.2) : Color.gray.opacity(0.2))
            .cornerRadius(8)
        }
        .disabled(!canAfford)
        .buttonStyle(PressScaleButtonStyle())
    }
    
    // MARK: - Helpers
    
    private func colorFromString(_ colorName: String) -> Color {
        switch colorName {
        case "blue": return .blue
        case "cyan": return .cyan
        case "teal": return .teal
        case "orange": return .orange
        case "pink": return .pink
        case "green": return .green
        case "mint": return .mint
        case "purple": return .purple
        case "indigo": return .indigo
        case "red": return .red
        case "yellow": return .yellow
        case "rainbow": return .purple
        case "navy": return Color(red: 0.0, green: 0.0, blue: 0.5)
        case "charcoal": return Color(red: 0.2, green: 0.2, blue: 0.25)
        case "slate": return Color(red: 0.4, green: 0.45, blue: 0.5)
        case "magenta": return Color(red: 1.0, green: 0.0, blue: 0.5)
        case "violet": return Color(red: 0.5, green: 0.0, blue: 1.0)
        default: return .blue
        }
    }
}

#Preview {
    NavigationStack {
        ShopView()
    }
    .modelContainer(for: [StudySet.self, UserProfile.self], inMemory: true)
}

// MARK: - Purchase Confirmation View

struct PurchaseConfirmationView: View {
    let itemName: String
    let itemCost: Int
    let isProcessing: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon/Image
            ZStack {
                Circle()
                    .fill(themeManager.primaryGradient)
                    .frame(width: 60, height: 60)
                    .shadow(color: themeManager.primaryColor.opacity(0.3), radius: 10, x: 0, y: 5)

                CelebrationLottieView(animationName: "celebration", play: true)
                    .frame(width: 52, height: 52)

                Image(systemName: "cart.fill")
                    .font(.title)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("Confirm Purchase")
                    .font(.title3.bold())
                
                Text("Are you sure you want to buy")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                
                Text(itemName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text("for")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundColor(.yellow)
                    
                    Text("\(itemCost)")
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                }
                .padding(.top, 4)
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    HapticsManager.shared.playTap()
                    onCancel()
                }) {
                    Text("Cancel")
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isProcessing)
                
                Button(action: {
                    HapticsManager.shared.playTap()
                    onConfirm()
                }) {
                    HStack(spacing: 8) {
                        if isProcessing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                        Text(isProcessing ? "Processing..." : "Buy Now")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(themeManager.primaryGradient)
                    .cornerRadius(12)
                    .shadow(color: themeManager.primaryColor.opacity(0.3), radius: 5, x: 0, y: 3)
                    .shimmering(active: isProcessing)
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(isProcessing)
            }
            .padding(.top, 10)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(themeManager.primaryColor.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 18, y: 6)
        .padding(.horizontal, 40)
    }
}

private struct ShopSkeletonView: View {
    let tab: ShopView.ShopTab

    var body: some View {
        LazyVGrid(columns: tab == .avatars ? [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14)] : [GridItem(.flexible())], spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: tab == .avatars ? 190 : 208)
            }
        }
        .shimmering()
    }
}
