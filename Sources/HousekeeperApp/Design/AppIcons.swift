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

/// The app icon image for the in-app brand mark (`Resources/AppIcon.png`,
/// exported from `AppIcon.icon`). It has no margin, so do not use it as the
/// Dock or About panel icon; the bundle's compiled icon does that job.
@MainActor
enum AppIcons {
    static let appIcon: NSImage? = loadImage("AppIcon")

    private static func loadImage(_ name: String) -> NSImage? {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: name, withExtension: "png"),
            Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
            Bundle.main.resourceURL?.appendingPathComponent("Housekeeper_HousekeeperApp.bundle/Resources/\(name).png"),
            Bundle.main.resourceURL?.appendingPathComponent("Housekeeper_HousekeeperApp.bundle/Resources/Resources/\(name).png"),
            Bundle.main.resourceURL?.appendingPathComponent("Housekeeper_HousekeeperApp.bundle/Contents/Resources/\(name).png"),
            Bundle.main.resourceURL?.appendingPathComponent("Housekeeper_HousekeeperApp.bundle/Contents/Resources/Resources/\(name).png"),
            Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/\(name).png")
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: candidate) {
                return image
            }
        }
        return nil
    }
}
