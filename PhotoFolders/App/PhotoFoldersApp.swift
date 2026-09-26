import BackgroundTasks
import SwiftUI
import UIKit

@main
struct PhotoFoldersApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .task { await library.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: library.sync()
            case .background: library.scheduleBackgroundSorting()
            default: break
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: LibraryModel.backgroundTaskID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in LibraryModel.shared.runBackgroundTask(task) }
        }
        return true
    }
}
