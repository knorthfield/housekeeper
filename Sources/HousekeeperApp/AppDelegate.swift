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
import Combine
import HousekeeperCore

/// Closing the window hides it instead of quitting, so Housekeeper keeps
/// watching. A click on the Dock icon shows the window again.
///
/// With the Hide Dock icon setting on, a menu bar icon shows the window
/// instead, and the Dock icon and the menus show only while a window is open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Set by `HousekeeperMacApp` as soon as the model exists, so the model is
    /// available at launch instead of waiting for the main window's
    /// `onAppear`: macOS doesn't open that window when it starts Housekeeper
    /// as a login item, so `onAppear` only fires once the user opens it.
    static var launchContext: AppModel?

    private var model: AppModel?
    /// The window hosting `ContentView`, reported by `HousekeeperMacApp` through
    /// `mainWindowDidAttach`. Tracked explicitly rather than looked up in
    /// `NSApp.windows`, which also holds the Settings window, in no useful
    /// order.
    private weak var mainWindow: NSWindow?
    /// The main window was asked for before it existed (Housekeeper started as a
    /// login item); bring it forward as soon as SwiftUI has created it.
    private var activatesMainWindowWhenAttached = false
    private var statusItem: NSStatusItem?
    private var hideDockIconSubscription: AnyCancellable?
    private var windowObservers: [NSObjectProtocol] = []

    /// `@NSApplicationDelegateAdaptor` requires a zero-argument initializer;
    /// the app's model is handed in afterward once SwiftUI has
    /// constructed it, from `HousekeeperMacApp`'s `onAppear` (or from
    /// `launchContext` at launch, whichever comes first).
    func configure(model: AppModel) {
        self.model = model
        observeHideDockIcon()
        showMainWindowOnFirstLaunch()
    }

    /// Called whenever `ContentView` lands in a window — at launch, or later
    /// when the window is first created by reopening a login-item launch.
    func mainWindowDidAttach(_ window: NSWindow) {
        mainWindow = window
        window.delegate = self
        window.title = "Housekeeper"
        window.titleVisibility = .hidden
        if activatesMainWindowWhenAttached {
            activatesMainWindowWhenAttached = false
            bringForward(window)
        }
    }

    /// The Dock icon and the menus must be there before the window comes
    /// forward, also when the Dock icon is hidden while no window is open.
    private func bringForward(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        WindowActivation.activateSoon(window)
    }

    /// Surface the main window once on a brand-new install, on the rules
    /// home, so a first-time user lands somewhere they can see and start
    /// using right away.
    private func showMainWindowOnFirstLaunch() {
        guard let model else { return }
        guard (try? model.db.getSetting("has_launched_before")) == nil else { return }
        try? model.db.setSetting("has_launched_before", "1")
        model.detailRoute = .rules
        openMainWindow()
        enableLaunchAtLoginByDefault()
    }

    /// Opt-in by default on first install — a folder watcher that isn't
    /// running after a reboot isn't doing its job. The Settings toggle
    /// (and its own `launch_at_login` setting) stays the single source of
    /// truth from here on; this only seeds it once.
    private func enableLaunchAtLoginByDefault() {
        guard let model else { return }
        try? model.db.setSetting("launch_at_login", "1")
        LoginItem.setEnabled(true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if model == nil { model = Self.launchContext }

        // The only window there can be at this point is the main one.
        if mainWindow == nil, let window = NSApp.windows.first {
            mainWindowDidAttach(window)
        }
        observeHideDockIcon()
    }

    /// Keeps the menu bar icon and the Dock icon in step with the setting
    /// and with the windows that are open. The subscription also fires with
    /// the stored value at launch.
    private func observeHideDockIcon() {
        guard hideDockIconSubscription == nil, let model else { return }
        // `@Published` sends the new value before it is set, so read the
        // model one tick later.
        hideDockIconSubscription = model.$hideDockIcon.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
                self?.updateDockIconVisibility()
            }
        }
        // The Settings window opens and closes without this delegate. A
        // closing window is still visible when the notification arrives, so
        // look one tick later.
        for name in [NSWindow.didBecomeMainNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateDockIconVisibility()
                }
            })
        }
    }

    private func updateStatusItem() {
        guard model?.hideDockIcon == true else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
                self.statusItem = nil
            }
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack.fill", accessibilityDescription: "Housekeeper")
        item.button?.toolTip = "Open Housekeeper"
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() {
        openMainWindow()
    }

    private func updateDockIconVisibility() {
        let hasOpenWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        let showsDockIcon = model?.hideDockIcon != true || hasOpenWindow
        let policy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        guard mainWindow != nil else {
            // Returning true lets SwiftUI create the window it skipped at
            // launch; `mainWindowDidAttach` then brings it forward.
            activatesMainWindowWhenAttached = true
            return true
        }
        // The window exists but is hidden: show it ourselves, and return
        // false so SwiftUI doesn't open a second one next to it.
        openMainWindow()
        return false
    }

    private func openMainWindow() {
        guard let mainWindow else {
            // Started as a login item, Housekeeper has no main window yet; reopening
            // the app is what makes SwiftUI create it.
            activatesMainWindowWhenAttached = true
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        bringForward(mainWindow)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        updateDockIconVisibility()
        return false
    }
}
