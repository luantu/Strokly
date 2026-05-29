import AppKit
import SwiftUI

public struct MenuBarContentView: View {
    @ObservedObject private var engine: GestureEngine
    private let openMainWindow: () -> Void

    public init(engine: GestureEngine, openMainWindow: @escaping () -> Void) {
        self.engine = engine
        self.openMainWindow = openMainWindow
    }

    public var body: some View {
        Group {
            Button {
                openMainWindow()
            } label: {
                Label("Open Strokly", systemImage: "scribble.variable")
            }
            .keyboardShortcut("o")

            Divider()

            Button {
                engine.toggle()
            } label: {
                Label(LocalizedStringKey(engine.isRunning ? "Stop Monitoring" : "Start Monitoring"),
                      systemImage: engine.isRunning ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut("m")

            if !engine.isRunning && !engine.accessibilityTrusted {
                Button {
                    AccessibilityPermissionService.requestTrustPrompt()
                    engine.refreshPermissionStatus()
                } label: {
                    Label("Grant Accessibility Access", systemImage: "lock.shield")
                }
            }

            Divider()

            Menu("Debug") {
                Toggle("Show Edge Zones", isOn: Binding(
                    get: { engine.debugWindow.isShowing },
                    set: { on in
                        if on { engine.debugWindow.showZones() }
                        else { engine.debugWindow.hideZones() }
                    }
                ))

                Toggle("Debug Logging", isOn: $engine.debugMode)

                Button("Open Log File") {
                    NSWorkspace.shared.open(StroklyLogger.shared.currentLogFileURL)
                }
            }

            if #available(macOS 14, *) {
            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        } else {
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

            Button("Quit Strokly") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
