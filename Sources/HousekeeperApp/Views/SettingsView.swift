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

/// Modern macOS Settings layout: a category sidebar on the left (matching
/// System Settings' own convention), detail content on the right — instead
/// of one long scrolling list of sections.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedCategory: SettingsCategory = .general
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(HousekeeperTheme.divider)
            detail
        }
        .frame(width: 600, height: 440)
        .background(HousekeeperTheme.background)
        .navigationTitle("Settings")
        .onAppear {
            let storedLogin = (try? model.db.getSetting("launch_at_login")) ?? nil
            launchAtLogin = LoginItem.isEnabled || storedLogin == "1"
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsCategory.allCases) { category in
                SettingsSidebarRow(
                    category: category,
                    isSelected: selectedCategory == category,
                    action: { selectedCategory = category }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 170, alignment: .top)
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selectedCategory {
                case .general:
                    generalPane
                case .permissions:
                    PermissionsSection()
                case .about:
                    aboutPane
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var generalPane: some View {
        Group {
            SectionLabel(title: "Appearance")
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent color").font(.system(size: 13)).foregroundStyle(HousekeeperTheme.primaryText)
                    AccentColorPicker(selection: accentBinding)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }

            SectionLabel(title: "General")
            GlassCard {
                ToggleRow(
                    title: "Automatic watching",
                    subtitle: model.paused ? "Paused — new files are ignored" : "Watching folders — rules run automatically",
                    isOn: watchingBinding
                )
                Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                ToggleRow(
                    title: "Start at login",
                    subtitle: "Open Housekeeper automatically when you log in",
                    isOn: launchAtLoginBinding
                )
                Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                ToggleRow(
                    title: "Show Dock icon",
                    subtitle: "Keep Housekeeper visible in the Dock while it runs",
                    isOn: dockIconBinding
                )
                Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                ToggleRow(
                    title: "Watcher notifications",
                    subtitle: "Notify when automatic rules process files",
                    isOn: watcherNotificationsBinding
                )
                Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Keep history for").font(.system(size: 13, weight: .semibold)).foregroundStyle(HousekeeperTheme.primaryText)
                        Spacer()
                        Text("\(model.historyMaxDays) day\(model.historyMaxDays > 1 ? "s" : "")").font(.system(size: 12)).foregroundStyle(HousekeeperTheme.secondaryText)
                    }
                    Slider(value: historyMaxDaysDoubleBinding, in: 1...30, step: 1)
                        .tint(HousekeeperTheme.accent)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
        }
    }

    private var aboutPane: some View {
        Group {
            SectionLabel(title: "About")
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppInfo.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(HousekeeperTheme.primaryText)
                        Text(AppInfo.tagline).font(.system(size: 11)).foregroundStyle(HousekeeperTheme.secondaryText)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                aboutRow(title: "Version", value: AppInfo.version)
                Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                aboutRow(title: "Build", value: AppInfo.build)
                if let copyright = AppInfo.copyright {
                    Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                    aboutRow(title: "Copyright", value: copyright)
                }
                Divider().overlay(HousekeeperTheme.divider).padding(.leading, 14)
                HStack {
                    Text("GitHub Repository").font(.system(size: 13)).foregroundStyle(HousekeeperTheme.primaryText)
                    Spacer()
                    Link("knorthfield/housekeeper", destination: AppInfo.repositoryURL)
                        .font(.system(size: 12))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
        }
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(HousekeeperTheme.primaryText)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(HousekeeperTheme.secondaryText)
                .textSelection(.enabled)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private var accentBinding: Binding<AccentPreset> {
        Binding(get: { model.accentPreset }, set: { model.setAccentPreset($0) })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin }, set: { enabled in
            launchAtLogin = enabled
            try? model.db.setSetting("launch_at_login", enabled ? "1" : "0")
            // In a signed .app this registers/unregisters the login item; in an
            // unsigned dev build it fails silently — the preference is still
            // saved and applies once running from a packaged build.
            LoginItem.setEnabled(enabled)
        })
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(get: { model.showDockIcon }, set: { model.setShowDockIcon($0) })
    }

    private var watcherNotificationsBinding: Binding<Bool> {
        Binding(get: { model.watcherNotificationsEnabled }, set: { model.setWatcherNotificationsEnabled($0) })
    }

    private var watchingBinding: Binding<Bool> {
        Binding(get: { !model.paused }, set: { enabled in
            if enabled == model.paused {
                model.togglePaused()
            }
        })
    }

    private var historyMaxDaysBinding: Binding<Int> {
        Binding(get: { model.historyMaxDays }, set: { model.setHistoryMaxDays($0) })
    }

    private var historyMaxDaysDoubleBinding: Binding<Double> {
        Binding(get: { Double(model.historyMaxDays) }, set: { model.setHistoryMaxDays(Int($0)) })
    }
}

enum SettingsCategory: CaseIterable, Identifiable {
    case general, permissions, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: Color(red: 0.36, green: 0.34, blue: 0.90)
        case .permissions: Color(red: 0.95, green: 0.55, blue: 0.13)
        case .about: Color(red: 0.31, green: 0.55, blue: 0.95)
        }
    }
}

private struct SettingsSidebarRow: View {
    let category: SettingsCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(category.tint)
                    Image(systemName: category.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)

                Text(category.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : HousekeeperTheme.primaryText)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? HousekeeperTheme.accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
