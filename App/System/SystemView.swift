import AppKit
import SweepCore
import SwiftUI

struct SystemView: View {
    @Bindable var model: SystemModel

    var body: some View {
        List {
            Section("Privileged Helper") {
                HelperStatusRow(model: model)
            }

            if model.status == .enabled {
                Section {
                    Label("Everything here is permanently deleted. Nothing goes to the Trash and it can't be undone.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    if let result = model.lastResult {
                        ResultRow(result: result)
                    }
                }
                ForEach(SystemCategory.allCases) { category in
                    CategorySection(model: model, category: category)
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("System")
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isLoading)
            }
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
        .sheet(item: $model.pending) { request in
            CleanConfirmationSheet(
                itemCount: request.names.count,
                totalBytes: request.totalBytes,
                moveToTrash: false,
                onConfirm: { Task { await model.confirmClean() } },
                onCancel: { model.pending = nil }
            )
        }
        .alert("System Action Failed", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
    }
}

private struct HelperStatusRow: View {
    let model: SystemModel

    private var description: String {
        switch model.status {
        case .enabled: "Installed and enabled."
        case .requiresApproval: "Waiting for approval in System Settings → General → Login Items & Extensions."
        case .notRegistered: "Not installed. Install it to clean snapshots, system caches, logs and root trash."
        case .notFound: "The helper was not found in this build of Sweep."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(description)
            HStack {
                Button("Install", action: model.install)
                    .disabled(model.status == .enabled || model.status == .requiresApproval)
                Button("Uninstall") { Task { await model.uninstall() } }
                    .disabled(model.status == .notRegistered || model.status == .notFound)
                Button("Open Login Items", action: model.openLoginItems)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategorySection: View {
    let model: SystemModel
    let category: SystemCategory

    var body: some View {
        Section {
            if let error = model.loadErrors[category] {
                Text(error)
                    .foregroundStyle(.red)
            } else if model.entries(for: category).isEmpty {
                Text(model.isLoading ? "Loading…" : category.emptyMessage)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.entries(for: category)) { entry in
                HStack {
                    if category.isSelectable {
                        Toggle(entry.id, isOn: Binding(get: { model.isSelected(entry, in: category) }, set: { _ in model.toggle(entry, in: category) }))
                            .toggleStyle(.checkbox)
                    } else {
                        Text(entry.id)
                    }
                    Spacer()
                    if let bytes = entry.bytes {
                        Text(ByteFormatter.string(bytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text(category.title)
                Spacer()
                if model.cleaningCategory == category {
                    ProgressView().controlSize(.small)
                }
                Button(category.isSelectable ? "Clean Selected" : "Clean All") { model.requestClean(category) }
                    .tint(.red)
                    .disabled(!model.canClean(category))
            }
        }
    }
}

private struct ResultRow: View {
    let result: PrivilegedCleanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Freed \(ByteFormatter.string(result.freedBytes)) (\(result.removed.count) items)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(result.failures.isEmpty ? .green : .orange)
            ForEach(result.failures, id: \.self) { failure in
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }
}
