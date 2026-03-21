// App entry point and shared SwiftData container setup.

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct LearnHubApp: App {
    static var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            StudyFolder.self,
            StudySet.self,
            Flashcard.self,
            Question.self,
            ChatMessage.self,
            UserProfile.self,
            ActiveXPBooster.self,
            Achievement.self,
            UnlockedItem.self,
        ])
        
        // Try to create with current schema
        let persistentConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [persistentConfiguration])
        } catch let error as NSError {
            // Schema mismatch: old store exists but schema changed
            // Delete incompatible store and create fresh
            print("⚠️ ModelContainer initialization failed (likely schema mismatch): \(error)")
            print("📦 Attempting to migrate by rebuilding persistent store...")
            
            do {
                // Delete the incompatible store file
                if let url = try? FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                ) {
                    let storeURL = url.appending(component: "default.store")
                    if FileManager.default.fileExists(atPath: storeURL.path) {
                        try FileManager.default.removeItem(at: storeURL)
                        print("✅ Deleted incompatible store file at: \(storeURL.path)")
                    }
                }
                
                // Create fresh container with new schema
                let freshConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .automatic
                )
                let container = try ModelContainer(for: schema, configurations: [freshConfig])
                print("✅ Successfully created new ModelContainer with updated schema")
                return container
            } catch {
                print("❌ Failed to recover after schema migration: \(error)")
                print("⚠️ Falling back to in-memory storage (data will not persist)")
                
                do {
                    let inMemoryConfig = ModelConfiguration(
                        schema: schema,
                        isStoredInMemoryOnly: true,
                        cloudKitDatabase: .none
                    )
                    return try ModelContainer(for: schema, configurations: [inMemoryConfig])
                } catch {
                    fatalError("❌ Could not create in-memory container: \(error)")
                }
            }
        }
    }()
    
    @StateObject private var gamificationManager = GamificationManager.shared
    @StateObject private var themeManager = ThemeManager.shared
        @StateObject private var guideManager = GuideManager.shared
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false

    init() {
        loadRocketSimConnect()
        // Disable app icon badges: clear existing badge and set a delegate to suppress badges.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Use the modern badge API (iOS 17+).
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("Failed to clear badge count: \(error)")
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    
    private func loadRocketSimConnect() {
        #if DEBUG
        if let bundle = Bundle(path: "/Applications/RocketSim.app/Contents/Frameworks/RocketSimConnectLinker.nocache.framework"),
           bundle.load() {
            print("RocketSim Connect successfully linked")
        } else {
            print("Failed to load RocketSim Connect linker framework")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gamificationManager)
                .environmentObject(themeManager)
                .environmentObject(guideManager)
                .tint(themeManager.primaryColor)
                .onAppear {
                    HapticsManager.shared.prepareEngine()
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenTutorial },
                    set: { _ in }
                )) {
                    TutorialView()
                        .environmentObject(themeManager)
                        .environmentObject(guideManager)
                }
                .onChange(of: scenePhase) { newPhase, _ in
                    if newPhase == .active {
                        UNUserNotificationCenter.current().setBadgeCount(0) { error in
                            if let error = error {
                                print("Failed to clear badge count on activate: \(error)")
                            }
                        }
                    }
                }
        }
        .modelContainer(Self.sharedModelContainer)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private override init() { }

    // Present notifications with sound and no badge updates.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        // Clear the app icon badge whenever a notification is shown.
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Clear any badge when the user interacts with a notification.
        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        NotificationManager.shared.handleNotificationResponse(response)
        completionHandler()
    }

}


