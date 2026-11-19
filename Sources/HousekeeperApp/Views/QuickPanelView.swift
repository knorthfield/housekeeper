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

import AppKit
import SwiftUI
import HousekeeperCore

/// The menu-bar quick panel: header with status badge, a "Watching" master
/// switch, watched-folder toggles, and an activity summary. Deep editing
/// (rules, conditions, actions) stays in the main window; this is the
/// glanceable surface.
struct QuickPanelView: View {
    @EnvironmentObject var model: AppModel
    let onOpenMainWindow: () -> Void
    let onQuit: () -> Void
    @State private var totalRuleCount = 0

    var body: some View {
        ZStack {
            // `.popover` (unlike `.hudWindow`) follows the system/app
            // appearance instead of always rendering dark, so the panel
            // stays legible in Light mode.
            VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HousekeeperTheme.background.opacity(0.55))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(HousekeeperTheme.surfaceBorder, lineWidth: 1)

            VStack(alignment: .leading, spacing: 14) {
                header

                GlassCard {
                    ToggleRow(
                        title: "Watching",
                        subtitle: model.paused ? "Paused — new files are ignored" : "Watching folders — rules run automatically",
                        isOn: watchingBinding
                    )
                }

                if !model.folders.isEmpty {
                    SectionLabel(title: "Watched Folders")
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(model.folders, id: \.id) { folder in
                                QuickFolderRow(
                                    folder: folder,
                                    isOn: folderBinding(folder)
                                )
                                if folder.id != model.folders.last?.id {
                                    Divider().overlay(HousekeeperTheme.divider).padding(.leading, 50)
                                }
                            }
                        }
                    }
                }

                SectionLabel(title: "Overview")
                GlassCard {
                    HStack(spacing: 0) {
                        QuickCount(value: model.folders.count, label: "Folders")
                        Divider().overlay(HousekeeperTheme.divider).frame(height: 28)
                        QuickCount(value: totalRuleCount, label: "Rules")
                        Divider().overlay(HousekeeperTheme.divider).frame(height: 28)
                        QuickCount(value: model.historyTotalCount, label: "History")
                    }
                    .padding(.vertical, 10)
                }

                SectionLabel(title: "Recent Activity")
                QuickActivityFeed(db: model.db)

                Divider().overlay(HousekeeperTheme.divider)

                HStack(spacing: 8) {
                    QuickPanelFooterButton(title: "Open Housekeeper", systemImage: "arrow.up.forward.app", action: onOpenMainWindow)
                    QuickPanelFooterButton(title: "Quit", systemImage: "power", action: onQuit)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .padding(.top, 14)
            .frame(width: 320)
        }
        .padding(1)
        .onAppear {
            model.reloadFolders()
            model.reloadHistory()
            reloadTotalRuleCount()
        }
        .onReceive(model.$rules) { _ in reloadTotalRuleCount() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            BrandMark(size: 38)
            VStack(alignment: .leading, spacing: 6) {
                Text("Housekeeper")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(HousekeeperTheme.primaryText)
                StatusBadge(active: !model.paused)
            }
            Spacer(minLength: 0)
        }
    }

    private func reloadTotalRuleCount() {
        totalRuleCount = model.db.withLock { db in (try? db.countRules()) ?? 0 }
    }

    private var watchingBinding: Binding<Bool> {
        Binding(get: { !model.paused }, set: { enabled in
            if enabled == model.paused {
                model.togglePaused()
            }
        })
    }

    private func folderBinding(_ folder: WatchedFolder) -> Binding<Bool> {
        Binding(
            get: {
                model.folders.first { $0.id == folder.id }?.enabled ?? folder.enabled
            },
            set: { model.toggleFolder(folder, enabled: $0) }
        )
    }
}

/// A big number over a small label, used for the quick panel's overview row.
private struct QuickCount: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(HousekeeperTheme.primaryText)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(HousekeeperTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
