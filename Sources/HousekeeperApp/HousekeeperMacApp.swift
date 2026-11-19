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

@main
struct HousekeeperMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = try! AppModel()
        _model = StateObject(wrappedValue: model)
        AppDelegate.launchContext = model
    }

    var body: some Scene {
        WindowGroup("Housekeeper") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 520)
                .background(WindowAccessor { appDelegate.mainWindowDidAttach($0) })
                .onAppear {
                    appDelegate.configure(model: model)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 620)
        .commands {
            // View > Show/Hide Sidebar (⌃⌘S), like every sidebar app.
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Housekeeper") {
                    let options: [NSApplication.AboutPanelOptionKey: Any] = [
                        .applicationName: AppInfo.name,
                        .applicationVersion: AppInfo.version,
                        .version: "Build \(AppInfo.build)",
                        .credits: Self.aboutCredits,
                    ]

                    NSApplication.shared.orderFrontStandardAboutPanel(options: options)
                }
            }
        }

        // A real `Settings` scene (not an in-app route) so Settings behaves
        // like every other macOS app: its own window, a "Settings…" item
        // under the Housekeeper menu, and the standard ⌘, shortcut, all wired up
        // automatically by SwiftUI.
        Settings {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }

    private static var aboutCredits: NSAttributedString {
        let credits = NSMutableAttributedString(
            string: "\nGitHub Repository",
            attributes: [.link: AppInfo.repositoryURL]
        )

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        credits.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: credits.length)
        )
        return credits
    }
}
