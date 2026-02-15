//
//  treehacksApp.swift
//  treehacks
//
//  Created by Dylan Tran on 2/13/26.
//

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap actions
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        
        switch actionIdentifier {
        case "CHECK_IN":
            print("User confirmed they are OK after fall")
        case "EMERGENCY":
            print("User needs help after fall - trigger emergency action")
            // TODO: Implement emergency contact or call functionality
        default:
            break
        }
        
        completionHandler()
    }
}

@main
struct treehacksApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deepLinkManager = DeepLinkManager.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([MeetingTranscript.self])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLinkManager)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "treehacks",
              url.host == "join",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sessionName = components.queryItems?.first(where: { $0.name == "session" })?.value else {
            return
        }
        
        print("Deep link received: joining session '\(sessionName)'")
        deepLinkManager.pendingSessionName = sessionName
        deepLinkManager.shouldShowZoomCall = true
    }
}

// MARK: - Deep Link Manager

class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var shouldShowZoomCall = false
    @Published var pendingSessionName: String?
    
    private init() {}
}
