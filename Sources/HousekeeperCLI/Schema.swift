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

/// What `housekeeper schema` prints: the rule format with every name and
/// value the engine accepts, read from the `RuleSchema` catalog.
struct SchemaOutput: Encodable {
    struct ConditionKindOutput: Encodable {
        let kind: String
        let label: String
        let operators: [String]
        let value: String
        let note: String?
    }

    struct ParameterOutput: Encodable {
        let key: String
        let type: String
        let values: [String]?
    }

    struct ActionKindOutput: Encodable {
        let kind: String
        let label: String
        let params: [ParameterOutput]
        let options: [ParameterOutput]
    }

    let rule: [String: String]
    let example: RuleDocument
    let conditions: [ConditionKindOutput]
    let conditionValues: [String: String]
    let actions: [ActionKindOutput]
    let parameterTypes: [String: String]

    enum CodingKeys: String, CodingKey {
        case rule, example, conditions, actions
        case conditionValues = "condition_values"
        case parameterTypes = "parameter_types"
    }
}

func schema() throws -> SchemaOutput {
    let example = """
    {
      "name": "File old PDFs",
      "enabled": false,
      "condition_match": "all",
      "recursion_depth": 0,
      "conditions": [
        { "kind": "extension", "operator": "is", "value": "pdf" },
        { "kind": "date_modified", "operator": "older_than", "value": "30 days" }
      ],
      "actions": [
        { "kind": "move_to_folder", "params": { "destination": "~/Documents/PDFs/{year}", "on_conflict": "rename" } }
      ]
    }
    """
    return SchemaOutput(
        rule: [
            "name": "Text. Necessary.",
            "enabled": "true or false. Default: false for a new rule, no change for an update.",
            "condition_match": "\"all\" (default) or \"any\": how many conditions a file must match. No conditions: every file matches.",
            "recursion_depth": "0 (default): files in the watched folder only. N: also N levels of subfolders. null: all subfolders.",
            "conditions": "A list of { kind, operator, value }. All values are text.",
            "actions": "A list of { kind, params }, run in this order. At least one.",
            "id": "Given by Housekeeper. Ignored in input.",
        ],
        example: try JSONDecoder().decode(RuleDocument.self, from: Data(example.utf8)),
        conditions: ConditionKind.allCases.map { kind in
            SchemaOutput.ConditionKindOutput(
                kind: kind.rawValue,
                label: kind.label,
                operators: kind.validOperators.map(\.rawValue),
                value: valueName(kind.baseValueKind),
                note: kind.helpText
            )
        },
        conditionValues: [
            "none": "No value. The operator is_true or is_false is the condition.",
            "text": "Text. With matches_regex: a regular expression.",
            "size": "A number of bytes, or a number with KB, MB or GB: \"5 MB\".",
            "date": "With before or after: \"yyyy-MM-dd\". With older_than or within_last: a number with hours, days, weeks, months or years: \"30 days\".",
            "file_kind": "One of: " + FileKindCatalog.all.map(\.value).joined(separator: ", "),
            "color_label": "One of: " + (ActionParam.permittedValues(for: ActionParam.color) ?? []).filter { !$0.isEmpty }.joined(separator: ", "),
            "app": "The name of the app, such as \"Safari\".",
        ],
        actions: ActionKind.allCases.map { kind in
            SchemaOutput.ActionKindOutput(
                kind: kind.rawValue,
                label: kind.label,
                params: kind.params.map {
                    SchemaOutput.ParameterOutput(key: $0.key, type: typeName($0.kind), values: ActionParam.permittedValues(for: $0.key))
                },
                options: kind.optionKeys.map {
                    let values = ActionParam.permittedValues(for: $0)
                    return SchemaOutput.ParameterOutput(key: $0, type: values == nil ? "boolean" : "one_of", values: values)
                }
            )
        },
        parameterTypes: [
            "boolean": "true or false.",
            "one_of": "One of the values in \"values\".",
            "folder_path": "A folder path; ~ is the home folder. For move, copy and sync, it can contain {kind}, {extension}, {year}, {month}, {day}, {hour}, {minute} and {quarter}, from the file and its creation date, and {folder}, the name of the folder that contains the file. For compress, empty means the folder of the file.",
            "rename_pattern": "The new name, without the extension unless {extension} is used. Tokens: {name}, {extension}, {date_created}, {date_modified}, {current_date}, {size}.",
            "archive_name": "The name of the ZIP file. Tokens: {name}, {current_date}, {timestamp}. Empty means {name}.zip.",
            "tags": "A list of Finder tag names: [\"Work\", \"Invoices\"].",
            "color_label": "A Finder colour. Empty text removes the colour.",
            "script": "A shell script, run with /bin/bash. $HOUSEKEEPER_FILE is the path of the file.",
            "shortcut": "The name of a shortcut in the Shortcuts app.",
            "application_path": "The path of an app: \"/Applications/Preview.app\".",
            "library_type": "The library to import into.",
            "playlist": "The name of a playlist (Music, TV) or an album (Photos). Optional.",
        ]
    )
}

private func valueName(_ kind: ConditionValueKind) -> String {
    switch kind {
    case .none: return "none"
    case .text, .regex: return "text"
    case .size: return "size"
    case .absoluteDate, .relativeDate: return "date"
    case .fileKind: return "file_kind"
    case .colorLabel: return "color_label"
    case .appPicker: return "app"
    }
}

private func typeName(_ kind: ActionParamKind) -> String {
    switch kind {
    case .boolean: return "boolean"
    case .folderPath: return "folder_path"
    case .renamePattern: return "rename_pattern"
    case .archiveName: return "archive_name"
    case .tags: return "tags"
    case .colorLabel: return "color_label"
    case .script: return "script"
    case .shortcut: return "shortcut"
    case .applicationPath: return "application_path"
    case .libraryType: return "library_type"
    case .playlist: return "playlist"
    }
}
