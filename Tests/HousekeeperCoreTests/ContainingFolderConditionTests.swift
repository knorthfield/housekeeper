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
import Testing
@testable import HousekeeperCore

@Suite struct ContainingFolderConditionTests {
    @Test func usesTheTextOperatorsAndIsInTheCatalog() {
        #expect(ConditionKind.containingFolder.validOperators == ConditionKind.name.validOperators)
        #expect(RuleSchema.conditionKinds.contains(.containingFolder))
    }

    @Test func matchesOnlyTheNearestFolderNameWithEveryOperator() {
        let dir = TempDir()
        _ = dir.dir("Holiday 2026/Raw")
        let photo = dir.file("Holiday 2026/beach.jpg")
        let nestedPhoto = dir.file("Holiday 2026/Raw/beach.jpg")
        let matching: [Operator: String] = [
            .is: "Holiday 2026", .isNot: "Work", .contains: "day", .doesNotContain: "Work",
            .startsWith: "Holiday", .endsWith: "2026", .matchesRegex: "^Holiday \\d{4}$",
        ]
        #expect(Set(matching.keys) == Set(ConditionKind.containingFolder.validOperators))
        for (op, value) in matching {
            #expect(ConditionEvaluator.evaluate(makeCondition(.containingFolder, op, value), path: photo), "\(op)")
        }
        #expect(!ConditionEvaluator.evaluate(makeCondition(.containingFolder, .is, "holiday 2026"), path: photo))
        #expect(!ConditionEvaluator.evaluate(makeCondition(.containingFolder, .matchesRegex, "["), path: photo))
        #expect(ConditionEvaluator.evaluate(makeCondition(.containingFolder, .is, "Raw"), path: nestedPhoto))
        #expect(!ConditionEvaluator.evaluate(makeCondition(.containingFolder, .contains, "Holiday"), path: nestedPhoto))
    }

    @Test(arguments: ["preview", "manual", "watcher"])
    func oneRuleForEachSubfolderMovesItsFilesOnEveryExecutionPath(execution: String) throws {
        let dir = TempDir()
        let input = dir.dir("Input")
        let photosShare = dir.dir("Photos")
        let projectsShare = dir.dir("Projects")
        _ = dir.dir("Input/Holiday")
        _ = dir.dir("Input/Work")
        _ = dir.dir("Input/Other")
        let holidayPhoto = dir.file("Input/Holiday/beach.jpg", contents: "beach")
        let workPlan = dir.file("Input/Work/plan.pdf", contents: "plan")
        let stayingFiles = [dir.file("Input/Other/notes.txt", contents: "notes"), dir.file("Input/Holiday.txt", contents: "top")]
        let expected = [photosShare + "/beach.jpg", projectsShare + "/plan.pdf"]
        let folder = WatchedFolder(path: input)
        let databasePath = dir.path + "/rules.db"
        do {
            let db = try Database(path: databasePath)
            try db.insertFolder(folder)
            for (subfolder, destination) in [("Holiday", photosShare), ("Work", projectsShare)] {
                var rule = makeRule(folderId: folder.id, name: "Move \(subfolder)", recursionDepth: 1)
                rule.conditions = [makeCondition(.containingFolder, .is, subfolder, ruleId: rule.id)]
                rule.actions = [makeAction(.moveToFolder, .object([ActionParam.destination: .string(destination)]), ruleId: rule.id)]
                try db.insertRule(rule)
            }
        }
        let db = try Database(path: databasePath)
        let rules = try db.executionRules(folderID: folder.id)
        #expect(rules.flatMap(\.conditions).map(\.kind) == [.containingFolder, .containingFolder])
        #expect(rules.allSatisfy { RuleValidator.validate($0.conditions).isEmpty })
        let entries = RuleEngine.walkEntries(root: input, maxDepth: RuleEngine.maxRuleDepth(rules))
        if execution == "preview" {
            let targets = entries
                .compactMap { RuleEngine.previewFile(path: $0.path, depth: $0.depth, rules: rules, root: input) }
                .flatMap { $0.rules.flatMap(\.actions) }
                .compactMap(\.targetPath)
            #expect(targets.sorted() == expected)
            #expect(FileManager.default.fileExists(atPath: holidayPhoto))
            return
        }
        if execution == "manual" {
            for entry in entries {
                _ = RuleEngine.run(path: entry.path, depth: entry.depth, rules: rules, batchId: "folder", root: input)
            }
        } else {
            let coordinator = WatcherCoordinator(db: db, settleInterval: 0.01)
            for path in [holidayPhoto, workPlan] + stayingFiles {
                coordinator.enqueue(event: .pathArrived(path))
            }
            coordinator.waitForPendingEvents()
        }
        for path in expected + stayingFiles + [input + "/Holiday", input + "/Work"] {
            #expect(FileManager.default.fileExists(atPath: path), "\(path)")
        }
        #expect(!FileManager.default.fileExists(atPath: holidayPhoto))
        #expect(!FileManager.default.fileExists(atPath: workPlan))
    }
}
