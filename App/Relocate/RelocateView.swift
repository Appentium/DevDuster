import AppKit
import DusterCore
import SwiftUI

struct RelocateView: View {
    @Bindable var model: RelocateModel
    @State private var isConfirming = false
    @State private var showsBlocked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro
                messages
                if case .moving(let title) = model.activity {
                    progressCard(title)
                }
                if !model.relocations.isEmpty {
                    movedCard
                }
                targetsCard
                if let candidate = model.selected {
                    destinationCard(candidate)
                }
            }
            .padding(16)
        }
        .navigationTitle("Move Tools")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
            }
        }
        .task { await model.load() }
        .alert("Move \(model.selected?.target.title ?? "")?", isPresented: $isConfirming) {
            Button("Move", action: model.move)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("DevDuster copies it to \(model.destinationPath), checks every file, links the old path to the new folder, then deletes the old copy. You can move it back at any time.")
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Move tool data to another drive, safely")
                    .font(.headline)
                Text("DevDuster copies the folder, checks every file against the original, then leaves a link at the old path, so tools, scripts and saved paths keep working. The old copy is deleted only after that. One folder at a time, and any move can be undone.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }

    @ViewBuilder
    private var messages: some View {
        if let message = model.resultMessage {
            banner(message, systemImage: "checkmark.circle.fill", color: .green)
        }
        if let message = model.errorMessage {
            banner(message, systemImage: "exclamationmark.triangle.fill", color: .orange)
        }
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss", action: model.dismissMessages)
                .buttonStyle(.borderless)
        }
        .dashboardCard()
    }

    private func progressCard(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Stop", action: model.cancel)
            }
            ProgressView(value: model.progress)
            Text(model.progress < 1 ? "Copying. Nothing changes until every file is checked." : "Checking every file, then switching over.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .dashboardCard()
    }

    private var movedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Moved")
                .font(.headline)
            ForEach(model.relocations) { relocation in
                MovedRow(relocation: relocation, isDisabled: model.isBusy) {
                    model.moveBack(relocation)
                }
            }
        }
        .dashboardCard()
    }

    private var targetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Folders you can move")
                    .font(.headline)
                if model.activity == .loading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if model.movable.isEmpty, model.activity != .loading {
                Text("No movable developer tool folders found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.movable) { candidate in
                TargetRow(candidate: candidate, isSelected: model.selectedID == candidate.id) {
                    model.selectedID = candidate.id
                }
                .disabled(model.isBusy)
            }
            if !model.blocked.isEmpty {
                DisclosureGroup("Can't be moved here (\(model.blocked.count))", isExpanded: $showsBlocked) {
                    ForEach(model.blocked) { candidate in
                        BlockedRow(target: candidate.target)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCard()
    }

    private func destinationCard(_ candidate: RelocateModel.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Move \(candidate.target.title) to")
                .font(.headline)
            if model.volumes.isEmpty {
                Text("Connect an APFS or Mac OS Extended drive to move tools onto it.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(model.volumes) { volume in
                    Button {
                        model.useVolume(volume)
                    } label: {
                        Label("\(volume.name) · \(ByteFormatter.string(volume.availableBytes)) free", systemImage: "externaldrive")
                    }
                    .disabled(!volume.canHoldMovedTools || model.isBusy)
                    .help(volume.canHoldMovedTools ? "Use \(volume.name)" : "\(volume.name) is \(volume.format). Tools need APFS or Mac OS Extended.")
                }
            }
            HStack {
                TextField("Destination folder", text: $model.destinationPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose...", action: chooseFolder)
            }
            .disabled(model.isBusy)
            if let check = model.check {
                ForEach(check.problems, id: \.self) { problem in
                    Label(problem, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                if check.problems.isEmpty {
                    ForEach(check.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                if model.activity == .checking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Check") {
                    Task { await model.runCheck() }
                }
                .disabled(model.isBusy || model.destinationPath.isEmpty || candidate.bytes == nil)
                Button("Move...") {
                    isConfirming = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.check?.problems.isEmpty != true)
            }
        }
        .dashboardCard()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.chooseFolder(url)
    }
}

private struct TargetRow: View {
    let candidate: RelocateModel.Candidate
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Image(systemName: candidate.target.platform.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.target.title)
                    Text(candidate.target.url.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if let bytes = candidate.bytes {
                    Text(ByteFormatter.string(bytes))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct BlockedRow: View {
    let target: RelocationTarget

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: target.platform.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                Text(target.blockedReason ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct MovedRow: View {
    let relocation: Relocation
    let isDisabled: Bool
    let onMoveBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(relocation.title)
                Text("\(relocation.original.path(percentEncoded: false)) → \(relocation.destination.path(percentEncoded: false))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if relocation.isDestinationConnected {
                StatusBadge(title: "Connected", color: .green)
            } else {
                StatusBadge(title: "Drive missing", color: .orange)
                    .help("Connect the drive. \(relocation.title) can't work until then.")
            }
            Button {
                FinderActions.reveal(relocation.destination)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .disabled(!relocation.isDestinationConnected)
            .help("Reveal in Finder")
            Button("Move Back", action: onMoveBack)
                .disabled(isDisabled || !relocation.isDestinationConnected)
        }
    }
}
