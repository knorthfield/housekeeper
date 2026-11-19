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

import Foundation

/// Automatic runs whose destination disk or network share isn't connected:
/// run again when that disk or share comes back.
extension WatcherCoordinator {
    /// Runs the rules again on the files that couldn't be moved or copied
    /// because the disk or share mounted at `mountPoint` wasn't connected.
    public func volumeDidMount(atPath mountPoint: String) {
        let volume = (mountPoint as NSString).lastPathComponent
        processingQueue.async { [weak self] in
            self?.retryWaiting(forVolume: volume)
        }
    }

    /// Forgets the waiting files `isWatched` rejects.
    func keepWaiting(where isWatched: (String) -> Bool) {
        waitingForSyncOnlyPaths = waitingForSyncOnlyPaths.filter(isWatched)
        waitingForVolume = waitingForVolume.compactMapValues { paths in
            let kept = paths.filter(isWatched)
            return kept.isEmpty ? nil : kept
        }
    }

    private func retryWaiting(forVolume volume: String) {
        guard let paths = waitingForVolume.removeValue(forKey: volume) else { return }
        for path in paths.sorted() {
            // A file waiting on several volumes is retried once; it waits
            // again for whichever is still missing.
            waitingForVolume = waitingForVolume.compactMapValues { waiting in
                let kept = waiting.subtracting([path])
                return kept.isEmpty ? nil : kept
            }
            let syncOnly = waitingForSyncOnlyPaths.remove(path) != nil
            handle(path: path, retrying: true, syncOnly: syncOnly)
        }
    }

    /// Keeps a file whose move or copy failed because the destination disk or
    /// share isn't connected, to run its rules again when it is. Not when
    /// another action already changed the file this time.
    func waitForDisconnectedVolumes(_ history: [HistoryEntry], path: String, rules: [Rule], syncOnly: Bool = false) {
        let volumes = Self.disconnectedVolumes(in: history, rules: rules)
        guard !volumes.isEmpty else { return }
        // A failed Sync can be retried on its own: already updated mirrors
        // are skipped, and arrival actions must not be repeated. Other kinds
        // still require that no action changed the file on the first run.
        let applied = history.contains { $0.status == .applied }
        let failed = history.filter { $0.status == .failed }
        let canRetrySync = !failed.isEmpty && failed.allSatisfy { $0.actionKind == .syncFolders }
            && FileManager.default.fileExists(atPath: path)
        guard !applied || canRetrySync else { return }
        if syncOnly || (applied && canRetrySync) { waitingForSyncOnlyPaths.insert(path) }
        else { waitingForSyncOnlyPaths.remove(path) }
        for volume in volumes {
            waitingForVolume[volume, default: []].insert(path)
        }
    }

    /// The disks or shares, by name, that the failed moves and copies in
    /// `history` were headed to and that aren't connected.
    static func disconnectedVolumes(in history: [HistoryEntry], rules: [Rule]) -> [String] {
        var volumes = Set<String>()
        for entry in history where entry.status == .failed && [.moveToFolder, .copyToFolder, .compress, .syncFolders].contains(entry.actionKind) {
            guard let rule = rules.first(where: { $0.id == entry.ruleId }) else { continue }
            for action in rule.actions where action.kind == entry.actionKind {
                guard let destination = action.params[ActionParam.destination]?.stringValue,
                      let volume = VolumePaths.unmountedVolume(of: destination)
                else { continue }
                volumes.insert(volume)
            }
        }
        return volumes.sorted()
    }
}
