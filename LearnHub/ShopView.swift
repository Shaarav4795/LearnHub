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
    @State private var pendingPurchase: (() -> Bool)?
    @State private var selectedItemName = ""
    @State private var selectedItemCoins = 0
    @State private var selectedItemXP = 0
    @State private var purchaseConfettiCounter = 0
    @State private var isProcessingPurchase = false
    @State private var isCatalogBooting = true

    @State private var xpShare: Double = 0.25
    @State private var boosterPercent: Int = 50
    @State private var boosterDurationValue: Int = 4
    @State private var boosterDurationUnit: GamificationManager.BoosterDurationUnit = .hours

    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }
        return gamificationManager.getOrCreateProfile(context: modelContext)
    }

    private var activeBoosters: [ActiveXPBooster] {
        gamificationManager.activeBoosters(for: profile, context: modelContext)
    }

    private var shopTier: ShopXPTier {
        gamificationManager.currentShopTier(for: profile)
    }

    private var boosterDurationHours: Int {
        boosterDurationUnit == .hours ? max(1, boosterDurationValue) : max(1, boosterDurationValue) * 24
    }

    private var boosterTierRequirement: ShopXPTier {
        gamificationManager.xpBoosterTierRequirement(percent: boosterPercent, durationHours: boosterDurationHours)
    }

    private var canConfigureBoosterAtCurrentTier: Bool {
        shopTier.maxBoosterPercent >= boosterPercent && shopTier.rawValue >= boosterTierRequirement.rawValue
    }

    private var boosterBaseCoinPrice: Int {
        gamificationManager.xpBoosterCoinCost(
            percent: boosterPercent,
            durationValue: boosterDurationValue,
            unit: boosterDurationUnit,
            activeCount: activeBoosters.count
        )
    }

    private var boosterHybridPrice: GamificationManager.HybridPrice {
        gamificationManager.hybridPrice(forCoinPrice: boosterBaseCoinPrice, xpShare: xpShare)
    }

    enum ShopTab: String, CaseIterable {
        case avatars = "Avatars"
        case themes = "Themes"
        case consumables = "Consumables"
    }

    private var avatarColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var themeColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                shopHeader
                tabPicker

                ScrollView {
                    if isCatalogBooting {
                        ShopSkeletonView(tab: selectedTab)
                            .padding()
                    } else {
                        tabContent
                            .padding(.horizontal)
                            .padding(.bottom, 18)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
            .confettiCannon(counter: $purchaseConfettiCounter, num: 34, rainHeight: 720)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedTab)
            .onAppear {
                guard isCatalogBooting else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isCatalogBooting = false
                    }
                }
            }

            if showPurchaseAlert {
                Color.black.opacity(0.42)
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
                    itemCoins: selectedItemCoins,
                    itemXP: selectedItemXP,
                    isProcessing: isProcessingPurchase,
                    onConfirm: {
                        guard isProcessingPurchase == false else { return }
                        isProcessingPurchase = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            let success = pendingPurchase?() ?? false
                            if success {
                                purchaseConfettiCounter += selectedItemXP > 0 ? 2 : 1
                            }
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

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .avatars:
                avatarsGrid
            case .themes:
                themesGrid
            case .consumables:
                consumablesSection
            }
        }
    }

    // MARK: - Header

    private var shopHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Balance")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.yellow)
                            Text("\(profile.coins)")
                                .font(.headline.bold())
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.orange)
                            Text("\(profile.totalXP)")
                                .font(.headline.bold())
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Tier")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(shopTier.title)
                        .font(.subheadline.bold())

                    Text("Lvl \(profile.level)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                statPill(icon: "snowflake", text: "Freeze x\(profile.streakFreezeTokens)", tint: .cyan)
                statPill(icon: "bolt.fill", text: "Boost x\(activeBoosters.count)", tint: .purple)
                statPill(icon: "sparkles", text: String(format: "x%.2f XP", gamificationManager.totalXPMultiplierPreview(for: profile)), tint: .green)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .trailing) {
            CelebrationLottieView(animationName: "celebration", play: true)
                .frame(width: 40, height: 40)
                .opacity(0.24)
                .padding(.trailing, 8)
        }
    }

    private func statPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.bold())
        .foregroundColor(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
    }

    // MARK: - Tabs

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

    // MARK: - Shared Spend Controls

    private var xpSpendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hybrid Spend")
                    .font(.subheadline.bold())
                Spacer()
                Text("XP Share: \(Int(xpShare * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Slider(value: $xpShare, in: 0...ShopEconomy.maxXPShare, step: 0.05)
                .tint(.orange)

            Text("Use XP to reduce coin cost. Higher XP share spends more XP per purchase.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Avatars

    private var avatarsGrid: some View {
        VStack(spacing: 12) {
            xpSpendCard

            LazyVGrid(columns: avatarColumns, spacing: 12) {
                ForEach(AvatarItem.allAvatars) { avatar in
                    let price = gamificationManager.hybridPrice(forCoinPrice: avatar.cost, xpShare: xpShare)
                    AvatarShopCard(
                        avatar: avatar,
                        price: price,
                        isOwned: gamificationManager.isItemOwned(avatar.id, itemType: "avatar", profile: profile),
                        isSelected: profile.selectedAvatarId == avatar.id,
                        isLocked: profile.level < avatar.requiredLevel,
                        canAfford: gamificationManager.canAffordHybridPrice(price, profile: profile),
                        onSelect: {
                            _ = gamificationManager.selectAvatar(avatar.id, for: profile, context: modelContext)
                        },
                        onPurchase: {
                            selectedItemName = avatar.name
                            selectedItemCoins = price.coins
                            selectedItemXP = price.xp
                            pendingPurchase = {
                                if gamificationManager.purchaseAvatar(avatar, xpShare: xpShare, for: profile, context: modelContext) {
                                    _ = gamificationManager.selectAvatar(avatar.id, for: profile, context: modelContext)
                                    return true
                                }
                                return false
                            }
                            withAnimation {
                                showPurchaseAlert = true
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Themes

    private var themesGrid: some View {
        VStack(spacing: 12) {
            xpSpendCard

            LazyVGrid(columns: themeColumns, spacing: 12) {
                ForEach(ThemeItem.allThemes) { theme in
                    let price = gamificationManager.hybridPrice(forCoinPrice: theme.cost, xpShare: xpShare)
                    ThemeShopCard(
                        theme: theme,
                        price: price,
                        isOwned: gamificationManager.isItemOwned(theme.id, itemType: "theme", profile: profile),
                        isSelected: profile.selectedThemeId == theme.id,
                        isLocked: profile.level < theme.requiredLevel,
                        canAfford: gamificationManager.canAffordHybridPrice(price, profile: profile),
                        onSelect: {
                            _ = gamificationManager.selectTheme(theme.id, for: profile, context: modelContext)
                        },
                        onPurchase: {
                            selectedItemName = theme.name
                            selectedItemCoins = price.coins
                            selectedItemXP = price.xp
                            pendingPurchase = {
                                if gamificationManager.purchaseTheme(theme, xpShare: xpShare, for: profile, context: modelContext) {
                                    _ = gamificationManager.selectTheme(theme.id, for: profile, context: modelContext)
                                    return true
                                }
                                return false
                            }
                            withAnimation {
                                showPurchaseAlert = true
                            }
                        }
                    )
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Consumables

    private var consumablesSection: some View {
        VStack(spacing: 12) {
            xpSpendCard
            
            // Tier requirement warning banner
            if shopTier.rawValue < ShopXPTier.learner.rawValue {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "lock.circle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Locked")
                                .font(.caption.bold())
                            Text("Unlock at Tier Learner (\(ShopXPTier.learner.minXP - profile.totalXP) XP to go)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2), lineWidth: 1))
            }

            streakFreezeCard
            xpBoosterCard
            activeEffectsCard
        }
        .padding(.top, 2)
    }

    private var streakFreezeCard: some View {
        let baseCoins = gamificationManager.streakFreezeCoinCost(currentTokens: profile.streakFreezeTokens)
        let price = gamificationManager.hybridPrice(forCoinPrice: baseCoins, xpShare: xpShare)
        let canBuy = profile.streakFreezeTokens < ShopEconomy.maxStreakFreezeTokens &&
            gamificationManager.canAffordHybridPrice(price, profile: profile) &&
            shopTier.rawValue >= ShopXPTier.learner.rawValue

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Streak Freeze", systemImage: "snowflake")
                        .font(.headline)
                    Text("Skip one day without losing your streak")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Owned")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(profile.streakFreezeTokens)/\(ShopEconomy.maxStreakFreezeTokens)")
                        .font(.subheadline.bold())
                        .foregroundColor(.cyan)
                }
            }

            HStack {
                PriceTagView(price: price)
                Spacer()
                Button("Buy Token") {
                    HapticsManager.shared.playTap()
                    selectedItemName = "Streak Freeze"
                    selectedItemCoins = price.coins
                    selectedItemXP = price.xp
                    pendingPurchase = {
                        gamificationManager.purchaseStreakFreeze(for: profile, xpShare: xpShare, context: modelContext)
                    }
                    withAnimation {
                        showPurchaseAlert = true
                    }
                }
                .font(.subheadline.bold())
                .foregroundColor(.cyan)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.cyan.opacity(0.15))
                .clipShape(Capsule())
                .disabled(!canBuy)
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
        )
    }

    private var xpBoosterCard: some View {
        let canAfford = gamificationManager.canAffordHybridPrice(boosterHybridPrice, profile: profile)
        let canBuy = canAfford && canConfigureBoosterAtCurrentTier

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("XP Booster", systemImage: "bolt.fill")
                    .font(.headline)
                Text("Earn \(boosterPercent)% more XP for \(boosterDurationValue) \(boosterDurationUnit == .hours ? "hours" : "days")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(spacing: 12) {
                HStack {
                    Text("XP Bonus")
                        .font(.subheadline)
                    Spacer()
                    Stepper(value: $boosterPercent, in: 25...min(300, shopTier.maxBoosterPercent), step: 25) {
                        Text("+\(boosterPercent)%")
                            .font(.subheadline.bold())
                            .foregroundColor(.purple)
                    }
                }

                HStack {
                    Text("Duration")
                        .font(.subheadline)
                    Spacer()
                    Stepper(value: $boosterDurationValue, in: 1...72) {
                        HStack(spacing: 4) {
                            Text("\(boosterDurationValue)")
                                .font(.subheadline.bold())
                                .foregroundColor(.purple)
                            Text(boosterDurationUnit == .hours ? "hours" : "days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Picker("Duration Unit", selection: $boosterDurationUnit) {
                    Text("Hours").tag(GamificationManager.BoosterDurationUnit.hours)
                    Text("Days").tag(GamificationManager.BoosterDurationUnit.days)
                }
                .pickerStyle(.segmented)
                .font(.caption)
            }

            HStack {
                PriceTagView(price: boosterHybridPrice)
                Spacer()
                Button("Activate") {
                    HapticsManager.shared.playTap()
                    selectedItemName = "XP Booster (+\(boosterPercent)%)"
                    selectedItemCoins = boosterHybridPrice.coins
                    selectedItemXP = boosterHybridPrice.xp
                    pendingPurchase = {
                        gamificationManager.purchaseXPBooster(
                            percent: boosterPercent,
                            durationValue: boosterDurationValue,
                            durationUnit: boosterDurationUnit,
                            xpShare: xpShare,
                            for: profile,
                            context: modelContext
                        )
                    }
                    withAnimation {
                        showPurchaseAlert = true
                    }
                }
                .font(.subheadline.bold())
                .foregroundColor(.purple)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.15))
                .clipShape(Capsule())
                .disabled(!canBuy)
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
    }

    private var activeEffectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Active Effects")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "x%.2f total", gamificationManager.totalXPMultiplierPreview(for: profile)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if activeBoosters.isEmpty {
                Text("No active boosters")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(activeBoosters, id: \.id) { booster in
                    HStack {
                        Text("+\(booster.percentBonus)% XP")
                            .font(.caption.bold())
                        Spacer()
                        Text(booster.endsAt, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct PriceTagView: View {
    let price: GamificationManager.HybridPrice

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text("\(price.coins)")
                    .font(.caption.bold())
                    .foregroundColor(.yellow)
            }
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("\(price.xp)")
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(Capsule())
    }
}

struct AvatarShopCard: View {
    let avatar: AvatarItem
    let price: GamificationManager.HybridPrice
    let isOwned: Bool
    let isSelected: Bool
    let isLocked: Bool
    let canAfford: Bool
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        isSelected ?
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)

                if isLocked && !isOwned {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                } else {
                    Image(avatar.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                }

                if isSelected {
                    Circle()
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 78, height: 78)
                }
            }

            Text(avatar.name)
                .font(.caption.bold())
                .lineLimit(1)

            if isOwned {
                if isSelected {
                    Text("Equipped")
                        .font(.caption2.bold())
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
            } else {
                Button(action: {
                    HapticsManager.shared.playTap()
                    onPurchase()
                }) {
                    PriceTagView(price: price)
                }
                .disabled(!canAfford)
                .buttonStyle(PressScaleButtonStyle())
                .opacity(canAfford ? 1 : 0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .scaleEffect(isSelected ? 1.02 : 1)
    }
}

struct ThemeShopCard: View {
    let theme: ThemeItem
    let price: GamificationManager.HybridPrice
    let isOwned: Bool
    let isSelected: Bool
    let isLocked: Bool
    let canAfford: Bool
    let onSelect: () -> Void
    let onPurchase: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            themePreview
            Text(theme.name)
                .font(.subheadline.bold())

            Text(theme.description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if isOwned {
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
            } else if isLocked {
                Text("Requires Level \(theme.requiredLevel)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Button(action: {
                    HapticsManager.shared.playTap()
                    onPurchase()
                }) {
                    PriceTagView(price: price)
                }
                .disabled(!canAfford)
                .buttonStyle(PressScaleButtonStyle())
                .opacity(canAfford ? 1 : 0.6)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    @ViewBuilder
    private var themePreview: some View {
        Group {
            if theme.id == "rainbow" {
                HStack(spacing: 4) {
                    ForEach([Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple], id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(colorFromString(theme.primaryColor))
                        .frame(width: 34, height: 34)
                    Circle()
                        .fill(colorFromString(theme.secondaryColor))
                        .frame(width: 34, height: 34)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
        )
        .opacity(isLocked && !isOwned ? 0.5 : 1)
        .overlay {
            if isLocked && !isOwned {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
        }
    }

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

struct PurchaseConfirmationView: View {
    let itemName: String
    let itemCoins: Int
    let itemXP: Int
    let isProcessing: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 20) {
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

                Text(itemName)
                    .font(.headline)

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.yellow)
                        Text("\(itemCoins)")
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.orange)
                        Text("\(itemXP)")
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
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
                        Text(isProcessing ? "Processing..." : "Buy")
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
        .padding(.horizontal, 34)
    }
}

private struct ShopSkeletonView: View {
    let tab: ShopView.ShopTab

    var columns: [GridItem] {
        switch tab {
        case .avatars:
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        case .themes:
            return [GridItem(.flexible()), GridItem(.flexible())]
        case .consumables:
            return [GridItem(.flexible())]
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: tab == .consumables ? 136 : 184)
            }
        }
        .shimmering()
    }
}

#Preview {
    NavigationStack {
        ShopView()
    }
    .modelContainer(for: [StudySet.self, UserProfile.self, ActiveXPBooster.self], inMemory: true)
}
