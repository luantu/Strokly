import AppKit
import SwiftUI

public struct ContentView: View {
    @ObservedObject private var store: RuleStore
    @ObservedObject private var engine: GestureEngine
    @ObservedObject private var settings: AppSettingsStore
    @Environment(\.openWindow) private var openWindow
    @State private var selection: GestureRule.ID?
    @State private var showLibrary = false
    @State private var showPermission = false
    @State private var permissionCheckedThisSession = false
    @AppStorage("collapsedCategories") private var collapsedCategoriesData: Data = Data()
    @State private var collapsedCategories: Set<String> = []

    public init(store: RuleStore, engine: GestureEngine, settings: AppSettingsStore) {
        self.store = store
        self.engine = engine
        self.settings = settings
    }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    Section {
                        ForEach(groupedRules.keys.sorted(), id: \.self) { category in
                            // Category header
                            Button {
                                toggleCategory(category)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: collapsedCategories.contains(category) ? "chevron.right" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 8)
                                    Label(category, systemImage: categoryIcon(category))
                                        .font(.body)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.primary)
                                        .help(category)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 0)

                            // Rule rows
                            if !collapsedCategories.contains(category) {
                                ForEach(groupedRules[category] ?? []) { rule in
                                    RuleRowView(rule: rule)
                                        .tag(rule.id)
                                        .padding(.leading, 20)
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(minWidth: 260)

                SidebarStatusView(engine: engine, onSettings: { openWindow(id: "settings") })
            }
        } detail: {
            if let selection, let rule = binding(for: selection) {
                RuleEditorView(rule: rule, engine: engine, store: store)
                                .id(rule.id)
            } else {
                PlaceholderView()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.addRule()
                    selection = store.rules.last?.id
                } label: {
                    Label("Add", systemImage: "plus")
                }

                Button {
                    guard let selection else { return }
                    store.deleteRule(id: selection)
                    self.selection = store.rules.first?.id
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection == nil)

                Divider()

                Button {
                    showLibrary = true
                } label: {
                    Label("Library", systemImage: "books.vertical")
                }

                Divider()

                Button {
                    engine.toggle()
                } label: {
                    Label(LocalizedStringKey(engine.isRunning ? "Stop" : "Start"),
                          systemImage: engine.isRunning ? "pause.fill" : "play.fill")
                }
            }
        }
        .sheet(isPresented: $showLibrary) {
            GestureLibraryView(store: store)
                .environment(\.locale, settings.locale)
        }
        .sheet(isPresented: $showPermission) {
            PermissionGuideView(engine: engine)
        }
        .onAppear {
            loadCollapsedCategories()
            if selection == nil { selection = store.rules.first?.id }
            if !permissionCheckedThisSession && !AccessibilityPermissionService.isTrusted {
                showPermission = true
                permissionCheckedThisSession = true
            }
        }
        .onChange(of: collapsedCategories) { _ in
            saveCollapsedCategories()
        }
    }

    private func toggleCategory(_ category: String) {
        if collapsedCategories.contains(category) {
            collapsedCategories.remove(category)
        } else {
            collapsedCategories.insert(category)
        }
    }

    private func loadCollapsedCategories() {
        guard !collapsedCategoriesData.isEmpty,
              let loaded = try? JSONDecoder().decode(Set<String>.self, from: collapsedCategoriesData) else { return }
        collapsedCategories = loaded
    }

    private func saveCollapsedCategories() {
        collapsedCategoriesData = (try? JSONEncoder().encode(collapsedCategories)) ?? Data()
    }

    private var groupedRules: [String: [GestureRule]] {
        Dictionary(grouping: store.rules, by: { $0.category })
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "Navigation": return "arrow.triangle.turn.up.right.diamond"
        case "Clipboard": return "doc.on.doc"
        case "Tabs": return "square.on.square"
        case "Applications": return "app.badge"
        case "System": return "gearshape"
        case "Window": return "rectangle"
        case "Media": return "speaker.wave.2"
        default: return "scribble.variable"
        }
    }

    private func binding(for id: GestureRule.ID) -> Binding<GestureRule>? {
        guard let index = store.rules.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { store.rules[index] }, set: { store.rules[index] = $0 })
    }
}

private struct PlaceholderView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "scribble.variable")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(), value: isAnimating)

            Text("No Gesture Selected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add or select a rule to customize your gestures.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { isAnimating = true }
    }
}

private struct RuleRowView: View {
    var rule: GestureRule

    var body: some View {
        HStack(spacing: 8) {
            if rule.scope.kind == .application && !rule.scope.bundleIdentifier.isEmpty {
                appIcon(for: rule.scope.bundleIdentifier)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: rule.isEnabled ? "hand.draw" : "hand.raised.slash")
                    .foregroundStyle(rule.isEnabled ? .blue : .secondary)
                    .frame(width: 14)
            }

            Text(rule.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func appIcon(for bundleIdentifier: String) -> some View {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.badge")
                .foregroundStyle(.secondary)
        }
    }
}

private struct SidebarStatusView: View {
    @ObservedObject var engine: GestureEngine
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(alignment: .center) {
                Circle()
                    .fill(engine.isRunning ? Color.green : Color.secondary)
                    .frame(width: 12, height: 12)
                    .shadow(color: engine.isRunning ? .green.opacity(0.5) : .clear, radius: 3)

                Text(engine.isRunning ? LocalizedStringKey("Monitoring") : LocalizedStringKey("Stopped"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { engine.isRunning },
                    set: { _ in engine.toggle() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            if let error = engine.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(alignment: .center) {
                Button {
                    onSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }
}
