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

/// Validates rule-level constraints so callers can surface issues before
/// persisting a rule that would silently produce wrong results at run time.
public enum RuleValidator {
    public struct Issue: Equatable {
        public let message: String
        public init(message: String) { self.message = message }
    }

    /// Why `rule` can't be saved yet, as the rule editor reports it.
    public static func validate(_ rule: Rule) -> [Issue] {
        var issues: [Issue] = []
        if rule.name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(Issue(message: "The rule needs a name."))
        }
        return issues + validate(rule.conditions) + validate(rule.actions)
    }

    /// `validate(rule)` plus what the rule editor's pickers make impossible,
    /// for rules that come from outside the app: an operator the condition
    /// doesn't accept, a parameter the action doesn't read, or a value that
    /// isn't one of the permitted ones. The engine would silently fall back
    /// to a default for these.
    public static func validateAgainstSchema(_ rule: Rule) -> [Issue] {
        var issues = validate(rule)
        for condition in rule.conditions where !condition.kind.validOperators.contains(condition.operator) {
            let permitted = condition.kind.validOperators.map(\.rawValue).joined(separator: ", ")
            issues.append(Issue(message: "Condition \"\(condition.kind.rawValue)\" does not accept the operator \"\(condition.operator.rawValue)\". Use one of: \(permitted)"))
        }
        if rule.actions.isEmpty {
            issues.append(Issue(message: "The rule needs at least one action."))
        }
        for action in rule.actions {
            let kind = action.kind.rawValue
            guard case .object(let params) = action.params else {
                issues.append(Issue(message: "The params of action \"\(kind)\" must be an object"))
                continue
            }
            // "tag" is the old single-tag form, which the engine still reads.
            let legacyKeys = action.kind == .addTag || action.kind == .removeTag ? ["tag"] : []
            let knownKeys = action.kind.params.map(\.key) + action.kind.optionKeys + legacyKeys
            for key in params.keys.sorted() {
                guard knownKeys.contains(key) else {
                    let list = knownKeys.isEmpty ? "it takes none" : "it takes: \(knownKeys.joined(separator: ", "))"
                    issues.append(Issue(message: "Action \"\(kind)\" does not take the parameter \"\(key)\"; \(list)"))
                    continue
                }
                guard let permitted = ActionParam.permittedValues(for: key) else { continue }
                let value = params[key]?.stringValue?.lowercased()
                if value.map(permitted.contains) != true {
                    let list = permitted.map { "\"\($0)\"" }.joined(separator: ", ")
                    issues.append(Issue(message: "The parameter \"\(key)\" of action \"\(kind)\" must be one of: \(list)"))
                }
            }
        }
        return issues
    }

    public static func validate(_ conditions: [Condition]) -> [Issue] {
        conditions.compactMap { condition in
            if condition.kind == .locked {
                return condition.kind.validOperators.contains(condition.operator)
                    ? nil : Issue(message: "Locked requires true or false")
            }
            if condition.value.trimmingCharacters(in: .whitespaces).isEmpty {
                return Issue(message: "Condition value cannot be empty")
            }
            if condition.operator == .matchesRegex,
               (try? NSRegularExpression(pattern: condition.value)) == nil {
                return Issue(message: "Regex pattern is invalid")
            }
            return nil
        }
    }

    public static func validate(_ actions: [Action]) -> [Issue] {
        actions.compactMap { action in
            switch action.kind {
            case .toggleLock, .toggleExtension:
                let key = action.kind == .toggleLock ? ActionParam.locked : ActionParam.extensionHidden
                if action.params[key]?.boolValue == nil {
                    return Issue(message: "\(action.kind.label) requires a true or false value")
                }
            case .moveToFolder, .copyToFolder, .syncFolders:
                if action.params[ActionParam.destination]?.stringValue?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                    return Issue(message: "Destination path cannot be empty")
                }
            case .rename:
                if action.params[ActionParam.pattern]?.stringValue?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                    return Issue(message: "Rename pattern cannot be empty")
                }
            case .compress:
                do {
                    _ = try ActionExecutor.archiveFileName(pattern: action.params[ActionParam.archiveName]?.stringValue ?? "", sourceName: "file")
                    _ = try ActionExecutor.archiveDestinationPath(action.params[ActionParam.destination]?.stringValue ?? "")
                } catch {
                    return Issue(message: String(describing: error))
                }
            case .addTag, .removeTag:
                if tags(in: action).isEmpty {
                    return Issue(message: "At least one tag is required")
                }
            case .openApplication:
                if action.params[ActionParam.applicationPath]?.stringValue?.trimmingCharacters(in: .whitespaces).isEmpty != false {
                    return Issue(message: "Application cannot be empty")
                }
            default:
                break
            }
            return nil
        }
    }

    private static func tags(in action: Action) -> [String] {
        if let tags = action.params[ActionParam.tags]?.arrayValue {
            return tags.compactMap(\.stringValue)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let tag = action.params["tag"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tag.isEmpty {
            return [tag]
        }
        return []
    }
}
