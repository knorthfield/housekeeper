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

/// A rule as JSON for the `housekeeper` command-line tool: what a coding
/// agent reads and writes. It has the same names as the database
/// (`move_to_folder`, `is_not`…), and none of the rows' ids, positions or
/// priorities. The order of `actions` is the order they run in.
public struct RuleDocument: Codable, Equatable, Sendable {
    public struct ConditionDocument: Codable, Equatable, Sendable {
        public var kind: String
        public var `operator`: String
        public var value: String?
    }

    public struct ActionDocument: Codable, Equatable, Sendable {
        public var kind: String
        public var params: JSONValue?
    }

    public var id: String?
    public var name: String
    public var enabled: Bool?
    public var conditionMatch: String?
    /// nil = all subfolders, 0 = the watched folder only, N = N levels deep.
    public var recursionDepth: Int64?
    public var conditions: [ConditionDocument]
    public var actions: [ActionDocument]
    /// Parts saved by a newer Housekeeper. Such a rule can't be changed here.
    public var unsupportedParts: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, conditions, actions
        case conditionMatch = "condition_match"
        case recursionDepth = "recursion_depth"
        case unsupportedParts = "unsupported_parts"
    }

    public init(_ rule: Rule) {
        id = rule.id
        name = rule.name
        enabled = rule.enabled
        conditionMatch = rule.conditionMatch.rawValue
        recursionDepth = rule.recursionDepth
        conditions = rule.conditions.map {
            ConditionDocument(kind: $0.kind.rawValue, operator: $0.operator.rawValue, value: $0.value)
        }
        actions = rule.actions.sorted { $0.position < $1.position }.map {
            ActionDocument(kind: $0.kind.rawValue, params: $0.params)
        }
        unsupportedParts = rule.unsupportedParts.isEmpty ? nil : rule.unsupportedParts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        conditionMatch = try container.decodeIfPresent(String.self, forKey: .conditionMatch)
        // A missing key is the default (this folder only); an explicit null is all subfolders.
        recursionDepth = container.contains(.recursionDepth)
            ? try container.decodeIfPresent(Int64.self, forKey: .recursionDepth)
            : 0
        conditions = try container.decodeIfPresent([ConditionDocument].self, forKey: .conditions) ?? []
        actions = try container.decodeIfPresent([ActionDocument].self, forKey: .actions) ?? []
        unsupportedParts = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(enabled, forKey: .enabled)
        try container.encodeIfPresent(conditionMatch, forKey: .conditionMatch)
        try container.encode(recursionDepth, forKey: .recursionDepth)
        try container.encode(conditions, forKey: .conditions)
        try container.encode(actions, forKey: .actions)
        try container.encodeIfPresent(unsupportedParts, forKey: .unsupportedParts)
    }

    /// The rule to save: a new one in `folderId`, or `existing` with its
    /// content replaced. Throws `RuleDocumentError` for a name the engine
    /// doesn't know, and never guesses one.
    public func rule(folderId: String, replacing existing: Rule? = nil) throws -> Rule {
        var rule = existing ?? Rule(folderId: folderId, name: name)
        rule.name = name
        rule.enabled = enabled ?? existing?.enabled ?? false
        rule.conditionMatch = try Self.known(conditionMatch ?? ConditionMatch.all.rawValue, "condition_match",
                                             among: ConditionMatch.allCases)
        if let recursionDepth, recursionDepth < 0 {
            throw RuleDocumentError("recursion_depth must be 0 or more, or null for all subfolders")
        }
        rule.recursionDepth = recursionDepth
        rule.conditions = try conditions.map {
            Condition(
                ruleId: rule.id,
                kind: try Self.known($0.kind, "condition kind", among: ConditionKind.allCases),
                operator: try Self.known($0.operator, "operator", among: Operator.allCases),
                value: $0.value ?? ""
            )
        }
        rule.actions = try actions.enumerated().map { index, action in
            Action(
                ruleId: rule.id,
                kind: try Self.known(action.kind, "action kind", among: ActionKind.allCases),
                params: action.params ?? .object([:]),
                position: Int64(index)
            )
        }
        return rule
    }

    private static func known<Value: RawRepresentable>(_ raw: String, _ what: String, among values: [Value]) throws -> Value
    where Value.RawValue == String {
        guard let value = values.first(where: { $0.rawValue == raw }) else {
            throw RuleDocumentError("Unknown \(what) \"\(raw)\". Use one of: \(values.map(\.rawValue).joined(separator: ", "))")
        }
        return value
    }
}

public struct RuleDocumentError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
