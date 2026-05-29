import AppKit
import SwiftUI

struct ShortcutRecorderView: View {
    @Binding var key: String
    @Binding var modifiers: [KeyboardModifier]
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            isRecording = true
            let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
                guard isRecording else { return event }
                isRecording = false

                let flags = event.modifierFlags
                var mods: [KeyboardModifier] = []
                if flags.contains(.command) { mods.append(.command) }
                if flags.contains(.option) { mods.append(.option) }
                if flags.contains(.shift) { mods.append(.shift) }
                if flags.contains(.control) { mods.append(.control) }
                self.modifiers = mods

                let keyCode = event.keyCode
                if let name = KeyCodeResolver.keyCodeToName(keyCode) {
                    self.key = name
                } else {
                    let chars = event.charactersIgnoringModifiers ?? event.characters ?? ""
                    let c = String(chars.prefix(1)).lowercased()
                    self.key = c
                }

                if let m = monitor {
                    NSEvent.removeMonitor(m)
                    self.monitor = nil
                }
                return nil
            }
            monitor = m
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press shortcut...")
                        .foregroundStyle(.blue)
                } else {
                    Text(KeyboardShortcutSpec(key: key, modifiers: modifiers).displayText)
                        .foregroundStyle(key.isEmpty ? .secondary : .primary)
                }
            }
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 100, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.blue : Color.secondary.opacity(0.3), lineWidth: isRecording ? 2 : 1)
            )
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onDisappear {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
    }
}