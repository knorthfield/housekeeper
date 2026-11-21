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
import HousekeeperCore

/// `housekeeper`: lets a coding agent read and change the folders and rules
/// of Housekeeper, and try a rule with a Dry Run. It only uses Core, and it
/// never runs an action.
@main
struct HousekeeperCLI {
    static func main() {
        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            let databasePath = try takeOption("--database", from: &arguments)
            guard let command = arguments.first, !["help", "--help", "-h"].contains(command) else {
                print(usage)
                return
            }
            if command == "schema" {
                try printJSON(schema())
                return
            }
            let db = try Database(path: databasePath ?? Database.defaultPath())
            var tool = HousekeeperCLI(db: db, arguments: Array(arguments.dropFirst()))
            switch command {
            case "folders": try tool.folders()
            case "rules": try tool.rules()
            case "dry-run": try tool.dryRun()
            default: throw ToolError("Unknown command \"\(command)\". Run `housekeeper help`.")
            }
        } catch {
            FileHandle.standardError.write(Data("housekeeper: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    let db: Database
    var arguments: [String]

    // MARK: - Folders

    mutating func folders() throws {
        switch try takeArgument("a folders command: list, add or remove") {
        case "list":
            let paused = try db.getSetting("paused").map { $0 == "1" } ?? true
            try printJSON(FolderList(watchingPaused: paused, folders: db.listFolders().map(FolderOutput.init)))
        case "add":
            let path = (try takeArgument("the path of the folder") as NSString).expandingTildeInPath
            let standardPath = (URL(fileURLWithPath: path).path as NSString).standardizingPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ToolError("\"\(standardPath)\" is not a folder.")
            }
            if try db.listFolders().contains(where: { ($0.path as NSString).standardizingPath == standardPath }) {
                throw ToolError("\"\(standardPath)\" is already a watched folder.")
            }
            let folder = WatchedFolder(path: standardPath)
            try db.insertFolder(folder)
            notifyApp()
            try printJSON(FolderOutput(folder))
        case "remove":
            let folder = try resolveFolder(takeArgument("the id or the path of the folder"))
            try db.deleteFolder(folder.id)
            notifyApp()
            try printJSON(FolderOutput(folder))
        case let other:
            throw ToolError("Unknown folders command \"\(other)\". Use list, add or remove.")
        }
    }

    // MARK: - Rules

    mutating func rules() throws {
        let subcommand = try takeArgument("a rules command: list, get, add, update, delete, enable or disable")
        switch subcommand {
        case "list":
            let only = try takeOption("--folder", from: &arguments).map(resolveFolder)
            let folders = try only.map { [$0] } ?? db.listFolders()
            try printJSON(folders.map { folder in
                FolderRules(folder: FolderOutput(folder), rules: try db.listRules(folderId: folder.id).map(RuleDocument.init))
            })
        case "get":
            try printJSON(RuleDocument(findRule(takeArgument("the id of the rule"))))
        case "add":
            guard let folder = try takeOption("--folder", from: &arguments).map(resolveFolder) else {
                throw ToolError("Give the watched folder of the new rule: --folder <id or path>.")
            }
            let rule = try readDocument().rule(folderId: folder.id)
            try refuseIssues(in: rule)
            try db.insertRule(rule)
            notifyApp()
            try printJSON(RuleDocument(findRule(rule.id)))
        case "update":
            let existing = try findRule(takeArgument("the id of the rule"))
            let rule = try readDocument().rule(folderId: existing.folderId, replacing: existing)
            try refuseIssues(in: rule)
            try db.updateRule(rule)
            notifyApp()
            try printJSON(RuleDocument(findRule(rule.id)))
        case "delete":
            let rule = try findRule(takeArgument("the id of the rule"))
            try db.deleteRule(rule.id)
            notifyApp()
            try printJSON(RuleDocument(rule))
        case "enable", "disable":
            let rule = try findRule(takeArgument("the id of the rule"))
            guard rule.isSupported else { throw UnsupportedRuleError() }
            try db.toggleRule(rule.id, enabled: subcommand == "enable")
            notifyApp()
            try printJSON(RuleDocument(findRule(rule.id)))
        default:
            throw ToolError("Unknown rules command \"\(subcommand)\". Use list, get, add, update, delete, enable or disable.")
        }
    }

    /// The rule JSON from the file given as the last argument, or from stdin.
    private mutating func readDocument() throws -> RuleDocument {
        let data: Data
        if let file = arguments.first, file != "-" {
            arguments.removeFirst()
            data = try Data(contentsOf: URL(fileURLWithPath: (file as NSString).expandingTildeInPath))
        } else {
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        do {
            return try JSONDecoder().decode(RuleDocument.self, from: data)
        } catch let error as DecodingError {
            throw ToolError("The rule JSON is not valid: \(describe(error)). Run `housekeeper schema` for the format.")
        }
    }

    private func describe(_ error: DecodingError) -> String {
        func location(_ context: DecodingError.Context) -> String {
            let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
            return path.isEmpty ? "" : " at \(path)"
        }
        switch error {
        case .keyNotFound(let key, let context): return "\"\(key.stringValue)\" is missing\(location(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.debugDescription + location(context)
        @unknown default: return error.localizedDescription
        }
    }

    private func refuseIssues(in rule: Rule) throws {
        let issues = RuleValidator.validateAgainstSchema(rule)
        guard issues.isEmpty else {
            throw ToolError("The rule was not saved:\n" + issues.map { "  - \($0.message)" }.joined(separator: "\n"))
        }
    }

    // MARK: - Dry Run

    mutating func dryRun() throws {
        guard let folder = try takeOption("--folder", from: &arguments).map(resolveFolder) else {
            throw ToolError("Give the watched folder: --folder <id or path>.")
        }
        let rules: [Rule]
        if let ruleId = try takeOption("--rule", from: &arguments) {
            // One rule, also when it is disabled: the way to try a new rule
            // before it is turned on.
            var rule = try findRule(ruleId)
            guard rule.folderId == folder.id else {
                throw ToolError("The rule \"\(ruleId)\" is not in the folder \"\(folder.path)\".")
            }
            guard rule.isSupported else { throw UnsupportedRuleError() }
            rule.enabled = true
            rules = [rule]
        } else {
            rules = try db.executionRules(folderID: folder.id)
        }
        let result = rules.isEmpty
            ? PreviewResult(filesScanned: 0, matches: [])
            : RuleEngine.previewFolder(root: folder.path, rules: rules, matchLimit: 500)
        try printJSON(DryRunOutput(
            folder: folder.path,
            rulesRun: rules.map(\.name),
            filesScanned: result.filesScanned,
            reachedMatchLimit: result.reachedMatchLimit,
            matches: result.matches.map { file in
                DryRunOutput.File(path: file.path, rules: file.rules.map { rule in
                    DryRunOutput.Rule(ruleId: rule.ruleId, ruleName: rule.ruleName, actions: rule.actions.map {
                        DryRunOutput.Action(kind: $0.kind.rawValue, description: $0.description, sourcePath: $0.sourcePath,
                                            targetPath: $0.targetPath, status: $0.status.rawValue, warning: $0.warning)
                    })
                })
            }
        ))
    }

    // MARK: - Lookups and arguments

    private func resolveFolder(_ idOrPath: String) throws -> WatchedFolder {
        let folders = try db.listFolders()
        let path = ((idOrPath as NSString).expandingTildeInPath as NSString).standardizingPath
        let absolutePath = (URL(fileURLWithPath: path).path as NSString).standardizingPath
        guard let folder = folders.first(where: { $0.id == idOrPath })
            ?? folders.first(where: { ($0.path as NSString).standardizingPath == absolutePath }) else {
            throw ToolError("\"\(idOrPath)\" is not a watched folder. Run `housekeeper folders list`.")
        }
        return folder
    }

    private func findRule(_ id: String) throws -> Rule {
        for folder in try db.listFolders() {
            if let rule = try db.listRules(folderId: folder.id).first(where: { $0.id == id }) { return rule }
        }
        throw ToolError("There is no rule with the id \"\(id)\". Run `housekeeper rules list`.")
    }

    private mutating func takeArgument(_ what: String) throws -> String {
        guard !arguments.isEmpty else { throw ToolError("Give \(what). Run `housekeeper help`.") }
        return arguments.removeFirst()
    }

    private func notifyApp() {
        DistributedNotificationCenter.default().postNotificationName(
            Database.changedOutsideAppNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}

struct ToolError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Removes `name <value>` from `arguments` and returns the value.
func takeOption(_ name: String, from arguments: inout [String]) throws -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard index + 1 < arguments.count else { throw ToolError("\(name) needs a value.") }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}

// MARK: - Output

struct FolderOutput: Encodable {
    let id: String
    let path: String
    let enabled: Bool

    init(_ folder: WatchedFolder) {
        id = folder.id
        path = folder.path
        enabled = folder.enabled
    }
}

struct FolderList: Encodable {
    /// True when the user paused watching in the app: no rule runs by itself.
    let watchingPaused: Bool
    let folders: [FolderOutput]

    enum CodingKeys: String, CodingKey {
        case watchingPaused = "watching_paused"
        case folders
    }
}

struct FolderRules: Encodable {
    let folder: FolderOutput
    let rules: [RuleDocument]
}

struct DryRunOutput: Encodable {
    struct Action: Encodable {
        let kind: String
        let description: String
        let sourcePath: String
        let targetPath: String?
        let status: String
        let warning: String?

        enum CodingKeys: String, CodingKey {
            case kind, description, status, warning
            case sourcePath = "source_path"
            case targetPath = "target_path"
        }
    }

    struct Rule: Encodable {
        let ruleId: String
        let ruleName: String
        let actions: [Action]

        enum CodingKeys: String, CodingKey {
            case actions
            case ruleId = "rule_id"
            case ruleName = "rule_name"
        }
    }

    struct File: Encodable {
        let path: String
        let rules: [Rule]
    }

    let folder: String
    let rulesRun: [String]
    let filesScanned: Int
    let reachedMatchLimit: Bool
    let matches: [File]

    enum CodingKeys: String, CodingKey {
        case folder, matches
        case rulesRun = "rules_run"
        case filesScanned = "files_scanned"
        case reachedMatchLimit = "reached_match_limit"
    }
}

let usage = """
housekeeper: read and change the folders and rules of the Housekeeper app.

  housekeeper folders list
  housekeeper folders add <path>
  housekeeper folders remove <folder>
  housekeeper rules list [--folder <folder>]
  housekeeper rules get <rule-id>
  housekeeper rules add --folder <folder> [<file>]
  housekeeper rules update <rule-id> [<file>]
  housekeeper rules delete <rule-id>
  housekeeper rules enable <rule-id>
  housekeeper rules disable <rule-id>
  housekeeper dry-run --folder <folder> [--rule <rule-id>]
  housekeeper schema
  housekeeper help

<folder> is the id or the path of a watched folder.
Output is JSON. An error goes to stderr, with exit status 1.

`rules add` and `rules update` read one rule as JSON from <file>, or from
stdin. `rules update` replaces all conditions and actions of the rule.
`housekeeper schema` gives the format and all permitted names and values.

A new rule is disabled unless its JSON has "enabled": true. To try a rule:
add it, run `housekeeper dry-run --folder <folder> --rule <rule-id>` (this
changes no file, and works on a disabled rule), then enable it. Without
--rule, the Dry Run uses all enabled rules of the folder.

Rules run by themselves only while the app is open and watching is not paused
(see "watching_paused" in `folders list`). Removing a folder deletes its rules.

  --database <path>   Use this database file, not the one of the app.
"""
