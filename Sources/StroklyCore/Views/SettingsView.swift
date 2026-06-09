import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var ruleStore: RuleStore
    @State private var showExportPanel = false
    @State private var showImportPanel = false
    @State private var runningApps: [NSRunningApplication] = []

    public init(settings: AppSettingsStore, ruleStore: RuleStore) {
        self.settings = settings
        self.ruleStore = ruleStore
    }

    public var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    leftColumn
                    rightColumn
                }
            }

            // About — pinned to bottom (same top/bottom margin via VStack padding)
            GroupBox {
                HStack {
                    LabeledContent("Version", value: "0.9.1")
                        .frame(maxWidth: 200)
                    LabeledContent("Bundle ID", value: "com.luantu.Strokly")
                        .textSelection(.enabled)
                        .frame(maxWidth: 300)
                    Link("GitHub", destination: URL(string: "https://github.com/luantu/Strokly")!)
                    Spacer()
                }
                .padding(10)
            } label: {
                Label("About", systemImage: "info.circle")
                    .font(.headline)
            }

            Button("Close Settings") {
                NSApp.keyWindow?.close()
            }
            .frame(maxWidth: .infinity)
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 600, height: 480)
        .fileExporter(isPresented: $showExportPanel, document: RulesDocument(rules: ruleStore.rules), contentType: .json) { _ in }
        .fileImporter(isPresented: $showImportPanel, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                try? ruleStore.importFromFile(url)
            }
        }
        .onAppear { refreshRunningApps() }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        VStack(spacing: 16) {
            // General
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    Toggle("Auto-start Monitoring", isOn: $settings.autoStartMonitoring)
                    Divider()
                    Picker("Language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text("Restart to apply language change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            } label: {
                Label("General", systemImage: "gearshape")
                    .font(.headline)
            }

            // Blocked Apps
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gestures disabled when these apps are frontmost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(settings.blockedAppBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Image(nsImage: iconFor(bundleID: bundleID))
                                .resizable().frame(width: 14, height: 14)
                            Text(nameFor(bundleID: bundleID))
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Button { settings.blockedAppBundleIDs.removeAll { $0 == bundleID } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Picker("Add App", selection: $selectedAppToBlock) {
                        Text("Select...").tag("")
                        ForEach(runningApps, id: \.bundleIdentifier) { app in
                            HStack {
                                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                                Text(app.localizedName ?? app.bundleIdentifier ?? "?")
                            }
                            .tag(app.bundleIdentifier ?? "")
                        }
                    }
                    .onChange(of: selectedAppToBlock) { v in
                        guard !v.isEmpty, !settings.blockedAppBundleIDs.contains(v) else { return }
                        settings.blockedAppBundleIDs.append(v)
                        selectedAppToBlock = ""
                    }
                }
                .padding(8)
            } label: {
                Label("Blocked Apps", systemImage: "nosign")
                    .font(.headline)
            }
        }
        .frame(maxWidth: 300)
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        VStack(spacing: 16) {
            // Rules
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Slider(value: $settings.minGestureDistance, in: 8...80, step: 4) {
                            Text("Min Trigger Distance")
                        } minimumValueLabel: {
                            Text("8").font(.caption).foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("80").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(Int(settings.minGestureDistance))pt — larger = less accidental triggers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack(spacing: 8) {
                        Button("Export Rules...") { showExportPanel = true }
                        Button("Import Rules...") { showImportPanel = true }
                        Spacer()
                    }
                    Divider()
                    Button("Reset to Defaults") { ruleStore.resetDefaults() }
                        .foregroundStyle(.red)
                }
                .padding(8)
            } label: {
                Label("Rules", systemImage: "list.bullet.rectangle")
                    .font(.headline)
            }

            // Logging
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Level", selection: $settings.logLevel) {
                        ForEach(StroklyLogLevel.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Write Log File", isOn: $settings.fileLoggingEnabled)
                    HStack {
                        Button("Open Log File") { settings.openLogFile() }
                            .controlSize(.small)
                        Spacer()
                    }
                }
                .padding(8)
            } label: {
                Label("Logging", systemImage: "doc.text")
                    .font(.headline)
            }
        }
        .frame(maxWidth: 280)
    }

    @State private var selectedAppToBlock = ""

    private func refreshRunningApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func iconFor(bundleID: String) -> NSImage {
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleID }), let icon = app.icon { return icon }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil) ?? NSImage()
    }

    private func nameFor(bundleID: String) -> String {
        if let app = runningApps.first(where: { $0.bundleIdentifier == bundleID }) {
            return app.localizedName ?? bundleID
        }
        return bundleID
    }
}