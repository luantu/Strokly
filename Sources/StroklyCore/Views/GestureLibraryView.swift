import SwiftUI

public struct GestureLibraryView: View {
    @ObservedObject private var store: RuleStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory = "All"
    @State private var searchText = ""

    public init(store: RuleStore) {
        self.store = store
    }

    private var categories: [String] {
        let cats = Set(GestureRule.libraryPresets.map(\.category))
        return ["All"] + cats.sorted()
    }

    private var filteredPresets: [GestureRule] {
        var results = selectedCategory == "All"
            ? GestureRule.libraryPresets
            : GestureRule.libraryPresets.filter { $0.category == selectedCategory }
        if !searchText.isEmpty {
            results = results.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return results
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Gesture Library")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            HStack {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                Spacer()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            .padding(.horizontal)

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredPresets) { preset in
                        LibraryCardView(preset: preset, isAdded: isAlreadyAdded(preset)) {
                            addPreset(preset)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    private func isAlreadyAdded(_ preset: GestureRule) -> Bool {
        store.rules.contains { $0.name == preset.name && $0.signature == preset.signature }
    }

    private func addPreset(_ preset: GestureRule) {
        guard !isAlreadyAdded(preset) else { return }
        store.rules.append(GestureRule(
            name: preset.name, category: preset.category, signature: preset.signature,
            template: preset.template, triggerButton: preset.triggerButton, scope: preset.scope, action: preset.action
        ))
    }
}

private struct LibraryCardView: View {
    let preset: GestureRule
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                Text(preset.gestureDisplayText)
                    .font(.system(size: 16, design: .monospaced))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(preset.name)
                        .fontWeight(.medium)
                    Text(preset.category)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Label(preset.action.displaySummary, systemImage: preset.action.kind.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isAdded {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Add") { onAdd() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
