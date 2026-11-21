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

import Testing
import Foundation
@testable import HousekeeperCore

@Suite struct RuleDocumentTests {
    private func decode(_ json: String) throws -> RuleDocument {
        try JSONDecoder().decode(RuleDocument.self, from: Data(json.utf8))
    }

    @Test func documentRoundTripsThroughTheDatabase() throws {
        let db = try Database(path: ":memory:")
        let folder = WatchedFolder(path: "/tmp/housekeeper-test-\(UUID().uuidString)")
        try db.insertFolder(folder)
        let document = try decode("""
        {
          "name": "File PDFs",
          "enabled": true,
          "condition_match": "any",
          "recursion_depth": null,
          "conditions": [{ "kind": "extension", "operator": "is", "value": "pdf" },
                         { "kind": "locked", "operator": "is_false" }],
          "actions": [{ "kind": "rename", "params": { "pattern": "{name}-filed" } },
                      { "kind": "move_to_folder", "params": { "destination": "/tmp/pdfs", "on_conflict": "skip" } }]
        }
        """)
        let rule = try document.rule(folderId: folder.id)
        #expect(RuleValidator.validateAgainstSchema(rule).isEmpty)
        try db.insertRule(rule)

        let saved = try #require(try db.listRules(folderId: folder.id).first)
        #expect(saved.recursionDepth == nil)
        #expect(saved.actions.map(\.kind) == [.rename, .moveToFolder])
        var expected = document
        expected.id = rule.id
        expected.conditions[1].value = ""
        #expect(RuleDocument(saved) == expected)

        let reencoded = try JSONEncoder().encode(RuleDocument(saved))
        #expect(try JSONDecoder().decode(RuleDocument.self, from: reencoded) == expected)
    }

    @Test func missingKeysTakeTheModelDefaults() throws {
        let rule = try decode(#"{ "name": "Trash", "actions": [{ "kind": "move_to_trash" }] }"#).rule(folderId: "folder")
        #expect(rule.enabled == false)
        #expect(rule.conditionMatch == .all)
        #expect(rule.recursionDepth == 0)
        #expect(rule.actions.first?.params == .object([:]))
    }

    @Test func replacingKeepsTheIdentityOfTheSavedRule() throws {
        let existing = Rule(id: "kept", folderId: "folder", name: "Old", enabled: true, priority: 4, createdAt: "then")
        let rule = try decode(#"{ "id": "other", "name": "New", "actions": [{ "kind": "delete" }] }"#)
            .rule(folderId: "ignored", replacing: existing)
        #expect(rule.id == "kept")
        #expect(rule.folderId == "folder")
        #expect(rule.enabled)
        #expect(rule.priority == 4)
        #expect(rule.createdAt == "then")
        #expect(rule.name == "New")
        #expect(rule.actions.first?.ruleId == "kept")
    }

    @Test func unknownNamesAreRefusedNotGuessed() throws {
        let unknownAction = try decode(#"{ "name": "X", "actions": [{ "kind": "move" }] }"#)
        #expect(throws: RuleDocumentError.self) { try unknownAction.rule(folderId: "folder") }
        let unknownOperator = try decode(#"{ "name": "X", "conditions": [{ "kind": "name", "operator": "equals", "value": "a" }] }"#)
        #expect(throws: RuleDocumentError.self) { try unknownOperator.rule(folderId: "folder") }
        let negativeDepth = try decode(#"{ "name": "X", "recursion_depth": -1 }"#)
        #expect(throws: RuleDocumentError.self) { try negativeDepth.rule(folderId: "folder") }
    }
}

@Suite struct PreviewFolderTests {
    @Test func previewFolderMatchesPreviewFilePerEntry() throws {
        let dir = TempDir()
        _ = dir.file("a.txt")
        _ = dir.file("b.pdf")
        let sub = dir.dir("sub")
        try "".write(toFile: sub + "/c.txt", atomically: true, encoding: .utf8)
        let rules = [makeRule(name: "Text", conditions: [makeCondition(.extension_, .is, "txt")],
                              actions: [makeAction(.moveToTrash, .object([:]))], recursionDepth: nil)]

        let result = RuleEngine.previewFolder(root: dir.path, rules: rules, matchLimit: 500)

        let entries = RuleEngine.walkEntries(root: dir.path, maxDepth: RuleEngine.maxRuleDepth(rules))
        let perEntry = entries.compactMap {
            RuleEngine.previewFile(path: $0.path, depth: $0.depth, rules: rules, root: dir.path)?.path
        }
        #expect(result.filesScanned == entries.count)
        #expect(Set(result.matches.map(\.path)) == Set(perEntry))
        #expect(result.matches.count == 2)
        #expect(!result.reachedMatchLimit)
    }

    @Test func previewFolderStopsAtTheMatchLimit() {
        let dir = TempDir()
        for name in ["a.txt", "b.txt", "c.txt"] { _ = dir.file(name) }
        let rules = [makeRule(name: "Text", conditions: [makeCondition(.extension_, .is, "txt")],
                              actions: [makeAction(.moveToTrash, .object([:]))])]
        let result = RuleEngine.previewFolder(root: dir.path, rules: rules, matchLimit: 2)
        #expect(result.matches.count == 2)
        #expect(result.reachedMatchLimit)
    }
}
