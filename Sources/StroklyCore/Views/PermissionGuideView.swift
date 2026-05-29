import AppKit
import SwiftUI

public struct PermissionGuideView: View {
    @ObservedObject private var engine: GestureEngine
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthorized = false
    @State private var checkTimer: Timer?

    public init(engine: GestureEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: isAuthorized ? "checkmark.shield.fill" : "scribble.variable")
                    .font(.system(size: 56))
                    .foregroundStyle(isAuthorized ? .green : .accentColor)
                    .symbolRenderingMode(.hierarchical)

                Text(isAuthorized ? "Ready to Go!" : "Welcome to Strokly")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(isAuthorized
                    ? "Accessibility permission granted. You can now use mouse gestures."
                    : "Strokly needs Accessibility permission to detect mouse gestures and execute actions.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            }

            Spacer()

            if !isAuthorized {
                VStack(spacing: 16) {
                    stepRow(number: 1, text: "Click the button below to open System Settings")

                    Button {
                        AccessibilityPermissionService.requestTrustPrompt()
                        startChecking()
                    } label: {
                        Label("Open Accessibility Settings", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    stepRow(number: 2, text: "Enable Strokly in Privacy & Security → Accessibility")

                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for permission...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 380)
            }

            Spacer()

            Button("Skip for Now") {
                dismiss()
            }
        }
        .padding(40)
        .frame(width: 520, height: 500)
        .onAppear {
            checkAuthorization()
            startChecking()
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    private func checkAuthorization() {
        isAuthorized = AccessibilityPermissionService.isTrusted
    }

    private func startChecking() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                checkAuthorization()
                if isAuthorized {
                    checkTimer?.invalidate()
                    engine.start()
                    dismiss()
                }
            }
        }
    }
}
