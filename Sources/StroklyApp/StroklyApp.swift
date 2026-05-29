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
        _store = StateObject(wrappedValue: sharedStore)
        _engine = StateObject(wrappedValue: GestureEngine(ruleStore: sharedStore, settingsStore: sharedSettings))
        _settings = StateObject(wrappedValue: sharedSettings)
    }

    var body: some Scene {
        WindowGroup("Strokly", id: "main") {
            ContentView(store: store, engine: engine, settings: settings)
                .frame(minWidth: 1080, minHeight: 768)
                .environment(\.locale, settings.locale)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    // Tag the NSWindow so we can find it later
                    if let win = NSApp.windows.first(where: { $0.title == "Strokly" }) {
                        win.identifier = NSUserInterfaceItemIdentifier("main")
                    }
                    if settings.autoStartMonitoring && AccessibilityPermissionService.isTrusted {
                        engine.start()
                    }
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView(settings: settings, ruleStore: store)
                .environment(\.locale, settings.locale)
        }

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

        // Hide dock icon by default — only show menu bar icon
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
