import AppKit
import StroklyCore
import SwiftUI

@main
struct StroklyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: RuleStore
    @StateObject private var engine: GestureEngine
    @StateObject private var settings: AppSettingsStore

    init() {
        let sharedStore = RuleStore()
        let sharedSettings = AppSettingsStore()
        let sharedEngine = GestureEngine(ruleStore: sharedStore, settingsStore: sharedSettings)
        _store = StateObject(wrappedValue: sharedStore)
        _engine = StateObject(wrappedValue: sharedEngine)
        _settings = StateObject(wrappedValue: sharedSettings)

        // Auto-start monitoring on app launch, independent of any window
        if sharedSettings.autoStartMonitoring && AccessibilityPermissionService.isTrusted {
            DispatchQueue.main.async {
                sharedEngine.start()
            }
        }

        // Handle silent start notification (when main window is not shown)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("StroklySilentStart"), object: nil, queue: .main) { _ in
            sharedEngine.start()
        }
    }

    var body: some Scene {
        WindowGroup("Strokly", id: "main") {
            ContentView(store: store, engine: engine, settings: settings)
                .frame(minWidth: 1080, minHeight: 768)
                .environment(\.locale, settings.locale)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if let win = NSApp.windows.first(where: { $0.title == "Strokly" }) {
                        win.identifier = NSUserInterfaceItemIdentifier("main")
                    }
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .defaultSize(width: 900, height: 640)

        WindowGroup("Settings", id: "settings") {
            SettingsView(settings: settings, ruleStore: store)
                .environment(\.locale, settings.locale)
        }
        .defaultSize(width: 620, height: 500)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Strokly", systemImage: "scribble.variable") {
            MenuBarSceneContent(engine: engine, store: store, settings: settings)
                .environment(\.locale, settings.locale)
        }
    }
}

private struct MenuBarSceneContent: View {
    @ObservedObject var engine: GestureEngine
    @ObservedObject var store: RuleStore
    @ObservedObject var settings: AppSettingsStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MenuBarContentView(engine: engine) {
            bringMainWindowToFront()
        }
    }

    private func bringMainWindowToFront() {
        // Find existing main window by identifier or title — prevent duplicates
        let existing = NSApp.windows.first(where: {
            ($0.identifier?.rawValue == "main" || $0.title == "Strokly") && $0.className.contains("Window")
        })
        if let existing {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        // Tag the window so subsequent calls find it reliably
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let win = NSApp.windows.first(where: { $0.title == "Strokly" }) {
                win.identifier = NSUserInterfaceItemIdentifier("main")
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleID && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        if let existing = running.first {
            existing.activate()
            NSApp.terminate(nil)
            return
        }

        // Silent launch: if permission is granted, stay in menu bar only
        let defaults = UserDefaults(suiteName: "com.luantu.Strokly") ?? .standard
        let silentLaunch = defaults.bool(forKey: "silentLaunch")
        let autoStart = defaults.object(forKey: "autoStartMonitoring") as? Bool ?? true
        let hasPermission = AccessibilityPermissionService.isTrusted

        if silentLaunch && hasPermission {
            // Stay accessory (menu bar only), don't show main window
            NSApp.setActivationPolicy(.accessory)
            if autoStart {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("StroklySilentStart"), object: nil)
                }
            }
            return
        }

        // Show the main window so the user sees the app is running.
        DispatchQueue.main.async {
            if let win = NSApp.windows.first(where: { $0.title == "Strokly" || $0.identifier?.rawValue == "main" }) {
                win.makeKeyAndOrderFront(nil)
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                DispatchQueue.main.async {
                    if let win = NSApp.windows.first(where: { $0.title == "Strokly" || $0.identifier?.rawValue == "main" }) {
                        win.makeKeyAndOrderFront(nil)
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
