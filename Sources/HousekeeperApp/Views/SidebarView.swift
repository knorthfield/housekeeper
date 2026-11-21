// Housekeeper - A native macOS file-automation app, a fork of Forel
// Copyright (C) 2026  Lab421
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import SwiftUI
import HousekeeperCore
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @State private var draggedFolderId: String?
    @State private var insertionIndex: Int?
    @State private var isFolderDropTargeted = false
    /// The cards and the gaps between them are drop targets of their own, and
    /// SwiftUI does not pass a drop on them to the sidebar's target. This is the
    /// one a folder from Finder is over.
    @State private var folderDropTargetInList: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewHeader(title: "Housekeeper", subtitle: "File automation") {
                StatusBadge(active: !model.paused)
            }

            GlassCard {
                ToggleRow(
                    title: model.paused ? "Paused" : "Watching",
                    subtitle: model.paused ? "New files are ignored" : "Rules run automatically",
                    isOn: watchingBinding
                )
            }

            HStack {
                SectionLabel(title: "Watched Folders")
                Spacer()
                Button(action: addFolder) {
                    Image(systemName: "plus")
                }
                .buttonStyle(IconButtonStyle())
                .help("Add a folder to watch")
            }

            if model.folders.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.folders.enumerated()), id: \.element.id) { index, folder in
                            folderDropTarget(index)

                            folderCard(folder)
                                .opacity(draggedFolderId == folder.id ? 0.55 : 1)
                                .onDrag {
                                    draggedFolderId = folder.id
                                    return NSItemProvider(object: folder.id as NSString)
                                }
                                .onDrop(
                                    of: [.plainText, .fileURL],
                                    delegate: folderDropDelegate(insertionIndex: index, targetName: "card \(index)")
                                )
                        }
                        folderDropTarget(model.folders.count)
                    }
                    .animation(.easeInOut(duration: 0.12), value: insertionIndex)
                    .onDrop(
                        of: [.plainText, .fileURL],
                        delegate: folderDropDelegate(insertionIndex: model.folders.count, targetName: "end of list")
                    )
                }
                .scrollIndicators(.never)
            }

            Spacer(minLength: 0)

            HStack {
                if #available(macOS 14.0, *) {
                    SettingsFooterLink()
                } else {
                    FooterLink(title: "Settings", systemImage: "gearshape") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .help("Settings")
                }
                Spacer()
                FooterLink(title: "Activity", systemImage: "clock.arrow.circlepath") {
                    model.leaveRuleEditor { model.showActivity() }
                }
                .help("Activity history")
            }
        }
        .padding(16)
        .frame(minWidth: 250)
        // The system sidebar material is nearly opaque; this lets the desktop
        // show through, up to the top of the window.
        .background(VisualEffectBlur(material: .hudWindow).ignoresSafeArea())
        .overlay {
            if isFolderDropTargeted || folderDropTargetInList != nil {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(HousekeeperTheme.accent, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isFolderDropTargeted, perform: addDroppedFolders)
    }

    private func folderDropDelegate(insertionIndex: Int, targetName: String) -> FolderInsertionDropDelegate {
        FolderInsertionDropDelegate(
            insertionIndex: insertionIndex,
            folders: model.folders,
            draggedFolderId: $draggedFolderId,
            activeInsertionIndex: $insertionIndex,
            move: model.reorderFolders,
            targetName: targetName,
            activeFolderDropTarget: $folderDropTargetInList,
            addDroppedFolders: addDroppedFolders
        )
    }

    private func folderDropTarget(_ index: Int) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 10)

            if insertionIndex == index, draggedFolderId != nil {
                Capsule()
                    .fill(HousekeeperTheme.accent)
                    .frame(height: 2)
                    .shadow(color: HousekeeperTheme.accent.opacity(0.35), radius: 2, y: 1)
            }
        }
        .contentShape(Rectangle())
        .onDrop(
            of: [.plainText, .fileURL],
            delegate: folderDropDelegate(insertionIndex: index, targetName: "gap \(index)")
        )
    }

    private func folderCard(_ folder: WatchedFolder) -> some View {
        let isSelected = model.selectedFolderId == folder.id
        let isActive = folder.enabled
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(HousekeeperTheme.secondaryText.opacity(0.6))

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? HousekeeperTheme.accent.opacity(0.18) : HousekeeperTheme.secondaryText.opacity(0.08))
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? HousekeeperTheme.accent : HousekeeperTheme.secondaryText)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text((folder.path as NSString).lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HousekeeperTheme.primaryText)
                    .lineLimit(1)
                Text((folder.path as NSString).deletingLastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(HousekeeperTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 4)

            HousekeeperSwitch(isOn: enabledBinding(folder), compact: true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? HousekeeperTheme.accent.opacity(0.14) : HousekeeperTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? HousekeeperTheme.accent.opacity(0.5) : HousekeeperTheme.surfaceBorder)
        )
        .help(folder.path)
        .contentShape(Rectangle())
        .onTapGesture {
            model.leaveRuleEditor {
                model.selectedFolderId = folder.id
                model.detailRoute = .rules
                model.reloadRules()
            }
        }
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder.path)])
            }
            Divider()
            Button("Change path of folder…") { changeFolder(folder) }
            Button("Remove", role: .destructive) {
                // Its rules go with it, including one being edited.
                if model.editingRule?.folderId == folder.id {
                    model.leaveRuleEditor { model.removeFolder(folder) }
                } else {
                    model.removeFolder(folder)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(HousekeeperTheme.secondaryText)
            Text("No folders yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HousekeeperTheme.primaryText)
            Text("Add a folder to start automating files.")
                .font(.system(size: 11))
                .foregroundStyle(HousekeeperTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Add Folder", action: addFolder)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func enabledBinding(_ folder: WatchedFolder) -> Binding<Bool> {
        Binding(get: { folder.enabled }, set: { model.toggleFolder(folder, enabled: $0) })
    }

    private var watchingBinding: Binding<Bool> {
        Binding(get: { !model.paused }, set: { enabled in
            if enabled == model.paused {
                model.togglePaused()
            }
        })
    }

    private func addFolder() {
        if let path = FolderPicker.choose() {
            // Adding a folder selects it, which leaves the rule editor.
            model.leaveRuleEditor { model.addFolder(path: path) }
        }
    }

    private func addDroppedFolders(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var folderPaths: [String] = []
            for provider in providers {
                guard let url = await Self.droppedFileURL(from: provider), Self.isFolder(url) else { continue }
                folderPaths.append(VolumePaths.canonical(url.path))
            }
            guard !folderPaths.isEmpty else {
                model.showNotice(
                    title: "Only folders can be watched",
                    message: "Drag a folder into the sidebar to watch it."
                )
                return
            }
            model.leaveRuleEditor { folderPaths.forEach(model.addFolder) }
        }
        return true
    }

    private static func droppedFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    /// A package (an app, for example) is a file to the user, as in the folder picker.
    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    private func changeFolder(_ folder: WatchedFolder) {
        if let path = FolderPicker.choose(startingAt: folder.path) {
            model.updateFolderPath(folder, path: path)
        }
    }
}

@available(macOS 14.0, *)
private struct SettingsFooterLink: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        FooterLink(title: "Settings", systemImage: "gearshape") {
            openSettings()
        }
        .help("Settings")
    }
}

private struct FolderInsertionDropDelegate: DropDelegate {
    let insertionIndex: Int
    let folders: [WatchedFolder]
    @Binding var draggedFolderId: String?
    @Binding var activeInsertionIndex: Int?
    let move: ([String]) -> Void
    /// Different for each target, so that a target clears only its own highlight.
    /// SwiftUI can tell the old target of the exit after it tells the new target of the entry.
    let targetName: String
    @Binding var activeFolderDropTarget: String?
    let addDroppedFolders: ([NSItemProvider]) -> Bool

    /// A card dragged from this sidebar reorders. A folder from Finder is added.
    private var isReorder: Bool { draggedFolderId != nil }

    func validateDrop(info: DropInfo) -> Bool {
        isReorder || info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        guard isReorder else {
            activeFolderDropTarget = targetName
            return
        }
        activeInsertionIndex = insertionIndex
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isReorder else {
            activeFolderDropTarget = targetName
            return DropProposal(operation: .copy)
        }
        activeInsertionIndex = insertionIndex
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if activeFolderDropTarget == targetName {
            activeFolderDropTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedFolderId = nil
            activeInsertionIndex = nil
            activeFolderDropTarget = nil
        }

        guard isReorder else {
            return addDroppedFolders(info.itemProviders(for: [.fileURL]))
        }

        guard
            let draggedFolderId,
            let sourceIndex = folders.firstIndex(where: { $0.id == draggedFolderId })
        else { return false }

        var ids = folders.map(\.id)
        ids.remove(at: sourceIndex)
        let targetIndex = sourceIndex < insertionIndex ? insertionIndex - 1 : insertionIndex
        let boundedTargetIndex = max(0, min(targetIndex, ids.count))
        ids.insert(draggedFolderId, at: boundedTargetIndex)

        guard ids != folders.map(\.id) else { return true }
        move(ids)
        return true
    }
}
