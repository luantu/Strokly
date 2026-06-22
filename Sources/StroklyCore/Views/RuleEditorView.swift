import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct RuleEditorView: View {
    @Binding private var rule: GestureRule
    @ObservedObject private var engine: GestureEngine
    @ObservedObject private var store: RuleStore
    @State private var gestureError: String?
    @State private var conflictWarning: String?

    public init(rule: Binding<GestureRule>, engine: GestureEngine, store: RuleStore) {
        self._rule = rule
        self.engine = engine
        self.store = store
    }

    private static let categoryOptions = ["Navigation", "Clipboard", "Tabs", "Applications", "Window", "Media", "System", "Edge Scroll", "Custom"]

    private var isCustomCategory: Bool {
        !Self.categoryOptions.contains(rule.category) || rule.category == "Custom"
    }

    public var body: some View {
        Form {
            ruleSection
            if rule.triggerButton != .edgeScroll {
                gestureSection
            }
            if rule.triggerButton == .edgeScroll {
                edgeScrollSection
            }
            modifierSection
            scopeSection
            actionSection
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle(rule.name)
        .onChange(of: rule.id) { _ in
            gestureError = nil
            conflictWarning = nil
        }
    }

    // MARK: - Rule Section

    private var ruleSection: some View {
        Section {
            Toggle("Enabled", isOn: $rule.isEnabled)
            Toggle("Show Tip on Trigger", isOn: $rule.showTip)
            TextField("Name", text: $rule.name)
            Picker("Category", selection: categoryBinding) {
                ForEach(Self.categoryOptions, id: \.self) { Text($0).tag($0) }
            }
            if isCustomCategory {
                TextField("Category Name", text: $rule.category, prompt: Text("Enter category name"))
            }
            Picker("Trigger", selection: $rule.triggerButton) {
                ForEach(TriggerButton.allCases) { button in
                    Label(button.displayName, systemImage: button.icon).tag(button)
                }
            }
            if rule.triggerButton != .edgeScroll {
                LabeledContent("Gesture") {
                    Text(rule.gestureDisplayText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }
        } header: {
            Label("Rule", systemImage: "list.bullet.rectangle")
        }
    }

    // MARK: - Edge Scroll Section

    private var edgeScrollSection: some View {
        Section {
            Picker("Screen Edge", selection: edgeBinding) {
                ForEach(ScreenEdge.allCases) { edge in
                    Text("\(edge.arrowSymbol) \(edge.displayName)").tag(edge)
                }
            }
            Picker("Direction", selection: directionBinding) {
                ForEach(ScrollDirection.allCases) { dir in
                    Text(dir.displayName).tag(dir)
                }
            }
            Text("Move the mouse to the screen edge, then scroll to trigger.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Edge Scroll", systemImage: "rectangle.dashed")
        }
    }

    // MARK: - Gesture Section

    private var gestureSection: some View {
        Section {
            GestureTemplateCanvasView(template: $rule.template) { points, _ in
                let recognizer = GestureRecognizer(minSegmentLength: 18)
                rule.signature = recognizer.recognize(points) ?? GestureSignature([])
                gestureError = nil
                checkConflicts()
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Image(systemName: "cursorarrow.click.2")
                    .foregroundStyle(.secondary)
                Text("Use left mouse button to draw gestures in the canvas above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Match Similarity")
                    .font(.callout)
                Slider(value: similarityBinding, in: 58...92, step: 1)
                Text("≥\(Int(similarityBinding.wrappedValue))%")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            if let gestureError {
                Label(gestureError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let conflictWarning {
                Label(conflictWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Label("Gesture", systemImage: "hand.draw")
        }
    }

    // MARK: - Modifier Section

    private var modifierSection: some View {
        Section {
            Text("Hold these keys while gesturing (optional).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(KeyboardModifier.allCases) { modifier in
                    Toggle(modifier.symbol, isOn: modifierRequirementBinding(modifier))
                        .toggleStyle(.button)
                }
            }
        } header: {
            Label("Modifier Keys", systemImage: "command")
        }
    }

    // MARK: - Scope Section

    private var scopeSection: some View {
        Section {
            Picker("Applies To", selection: scopeKindBinding) {
                Text("All Apps").tag(RuleScope.Kind.global)
                Text("Specific App").tag(RuleScope.Kind.application)
            }
            .pickerStyle(.segmented)

            if rule.scope.kind == .application {
                RunningAppPicker(bundleIdentifier: bundleIdentifierBinding)
            }
        } header: {
            Label("Scope", systemImage: "app.badge")
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Section {
            Picker("Type", selection: actionKindBinding) {
                ForEach(GestureAction.Kind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.icon).tag(kind)
                }
            }
            Toggle("Focus Visible Window Before Action", isOn: $rule.action.focusVisibleWindowBeforeExecution)
            actionFields
        } header: {
            Label("Action", systemImage: "bolt.fill")
        }
    }

    @ViewBuilder
    private var actionFields: some View {
        switch rule.action.kind {
        case .keyStroke:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(KeyboardModifier.allCases) { modifier in
                        Toggle(modifier.symbol, isOn: modifierBinding(modifier))
                            .toggleStyle(.button)
                    }
                }
                ShortcutRecorderView(
                    key: keyBinding,
                    modifiers: Binding(
                        get: { rule.action.keyShortcut?.modifiers ?? [] },
                        set: {
                            let k = rule.action.keyShortcut?.key ?? ""
                            rule.action.keyShortcut = KeyboardShortcutSpec(key: k, modifiers: $0)
                        }
                    )
                )
            }
        case .openURL:
            TextField("URL", text: actionValueBinding, prompt: Text("https://example.com"))
        case .openApplication:
            RunningAppPicker(bundleIdentifier: actionValueBinding)
        case .shellScript:
            TextEditor(text: actionValueBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
            Toggle("Run as Administrator", isOn: $rule.action.runAsAdmin)
                .help("Runs the script with administrator privileges (macOS will ask for your password).")
        case .appleScript:
            TextEditor(text: actionValueBinding)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
        case .systemAction:
            SystemActionPicker(selection: systemActionBinding)
        }
    }

    // MARK: - Bindings

    private var categoryBinding: Binding<String> {
        Binding(
            get: { Self.categoryOptions.contains(rule.category) ? rule.category : "Custom" },
            set: { newValue in
                if newValue != "Custom" {
                    rule.category = newValue
                } else if Self.categoryOptions.contains(rule.category) {
                    rule.category = ""
                }
            }
        )
    }

    private var scopeKindBinding: Binding<RuleScope.Kind> {
        Binding(get: { rule.scope.kind }, set: { v in
            rule.scope.kind = v
            if v == .global { rule.scope.bundleIdentifier = "" }
        })
    }

    private var bundleIdentifierBinding: Binding<String> {
        Binding(get: { rule.scope.bundleIdentifier }, set: { rule.scope.bundleIdentifier = $0 })
    }

    private var actionKindBinding: Binding<GestureAction.Kind> {
        Binding(get: { rule.action.kind }, set: { rule.action = defaultAction(for: $0) })
    }

    private var actionValueBinding: Binding<String> {
        Binding(get: { rule.action.value }, set: { rule.action.value = $0 })
    }

    private var keyBinding: Binding<String> {
        Binding(get: { rule.action.keyShortcut?.key ?? "" }, set: { v in
            let mods = rule.action.keyShortcut?.modifiers ?? []
            rule.action.keyShortcut = KeyboardShortcutSpec(key: v, modifiers: mods)
        })
    }

    private var similarityBinding: Binding<Double> {
        Binding(
            get: { (1 - rule.matchTolerance) * 100 },
            set: { rule.matchTolerance = 1 - ($0 / 100) }
        )
    }

    private var systemActionBinding: Binding<SystemAction?> {
        Binding(get: { rule.action.systemAction }, set: { rule.action = .systemAction($0 ?? .maximizeWindow) })
    }

    private var edgeBinding: Binding<ScreenEdge> {
        Binding(get: { rule.edge ?? .top }, set: { rule.edge = $0 })
    }

    private var directionBinding: Binding<ScrollDirection> {
        Binding(get: { rule.scrollDirection ?? .up }, set: { rule.scrollDirection = $0 })
    }

    private func modifierBinding(_ m: KeyboardModifier) -> Binding<Bool> {
        Binding(get: { rule.action.keyShortcut?.modifiers.contains(m) ?? false }, set: { on in
            var s = rule.action.keyShortcut ?? KeyboardShortcutSpec(key: "space", modifiers: [])
            if on { s.modifiers.append(m) } else { s.modifiers.removeAll { $0 == m } }
            rule.action.keyShortcut = KeyboardShortcutSpec(key: s.key, modifiers: s.modifiers)
        })
    }

    private func modifierRequirementBinding(_ m: KeyboardModifier) -> Binding<Bool> {
        Binding(get: { rule.modifierRequirements.contains(m) }, set: { on in
            if on { rule.modifierRequirements.append(m) } else { rule.modifierRequirements.removeAll { $0 == m } }
        })
    }

    private func defaultAction(for kind: GestureAction.Kind) -> GestureAction {
        switch kind {
        case .keyStroke: return .keyStroke(rule.action.keyShortcut ?? KeyboardShortcutSpec(key: "space", modifiers: [.command]))
        case .openURL: return .openURL(rule.action.value)
        case .openApplication: return .openApplication(rule.action.value)
        case .shellScript: return .shellScript(rule.action.value)
        case .appleScript: return .appleScript(rule.action.value)
        case .systemAction: return .systemAction(rule.action.systemAction ?? .maximizeWindow)
        }
    }

    private func checkConflicts() {
        let conflicts = RuleMatcher.detectConflicts(template: rule.template, triggerButton: rule.triggerButton, scope: rule.scope, excludeRuleID: rule.id, rules: store.rules)
        conflictWarning = conflicts.first.map { "Similar to \"\($0.name)\" — may conflict." }
    }
}

// MARK: - Running App Picker

private struct RunningAppPicker: View {
    @Binding var bundleIdentifier: String
    @State private var runningApps: [NSRunningApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Application", selection: $bundleIdentifier) {
                Text("Select an app...").tag("")
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    HStack(spacing: 6) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.localizedName ?? app.bundleIdentifier ?? "Unknown")
                    }
                    .tag(app.bundleIdentifier ?? "")
                }
            }

            HStack {
                Button("Use Frontmost App") {
                    bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
                }
                .controlSize(.small)

                Spacer()

                Text(bundleIdentifier.isEmpty ? "No app selected" : bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .onAppear { refreshApps() }
    }

    private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

// MARK: - System Action Picker

private struct SystemActionPicker: View {
    @Binding var selection: SystemAction?

    var body: some View {
        Picker("System Action", selection: Binding(
            get: { selection ?? .maximizeWindow },
            set: { selection = $0 }
        )) {
            Section("Window") {
                ForEach([SystemAction.maximizeWindow, .centerWindow, .fullscreen, .minimizeWindow], id: \.self) { action in
                    Label(action.displayName, systemImage: action.icon).tag(action)
                }
            }
            Section("Media") {
                ForEach([SystemAction.volumeUp, .volumeDown, .volumeMute, .brightnessUp, .brightnessDown], id: \.self) { action in
                    Label(action.displayName, systemImage: action.icon).tag(action)
                }
            }
            Section("System") {
                ForEach([SystemAction.showDesktop, .missionControl, .appExpose, .spotlight, .forceQuit, .lockScreen, .sleepDisplay], id: \.self) { action in
                    Label(action.displayName, systemImage: action.icon).tag(action)
                }
            }
        }
    }
}

// MARK: - RulesDocument (shared)

public struct RulesDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var rules: [GestureRule]

    public init(rules: [GestureRule]) { self.rules = rules }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        rules = try JSONDecoder().decode([GestureRule].self, from: data)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder().encode(rules))
    }
}
