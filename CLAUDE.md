# Housekeeper - AI & Agent Guidelines

> Source of truth for AI coding agents working on the Swift app in this repository.

## What Housekeeper is

Housekeeper is a fork of Forel (lab421, GPL-3.0). It has no licence checks, no limits, no updater and no network calls. Keep it that way. It builds for Apple silicon only.

Homebrew installs the updates. `UpdateRelauncher` (`Sources/HousekeeperApp/System`) is not an updater: it downloads nothing. When Homebrew replaces the app on the disk, it starts the new version when no rule runs and Housekeeper is not the active app.

Housekeeper is a native macOS file-automation app. It watches folders and runs user-defined rules on files locally. The active app is the Swift package at the repository root.

## Stack

| Layer | Technology |
|---|---|
| App shell | SwiftUI / AppKit |
| Backend | Swift 6 |
| Core persistence | SQLite via the in-house `Database` wrapper |
| File watching | `FileWatcher` / FSEvents on macOS |
| Build | Swift Package Manager |

## Repository layout

```text
housekeeper/
├── Package.swift
├── Sources/
│   ├── HousekeeperApp/
│   └── HousekeeperCore/
├── Tests/
└── README.md
```

## Working rules

- Use `swift build` and `swift test` from the repository root.
- When changing Swift code, keep edits aligned with the existing package structure and avoid unnecessary refactors.
- Do not revert user changes you did not make.
- Avoid destructive commands unless explicitly requested.

## App structure

- `Sources/HousekeeperApp` contains the SwiftUI app, windows and views.
- `Sources/HousekeeperCore` contains models, persistence, watcher, and rule engine logic.
- `Tests/HousekeeperCoreTests` contains the core unit tests. Add or update tests with behavior changes.

## Execution pipeline

```
Input (FSEvents / Run Now / Dry Run)
        ↓
Rule Engine (per file)
  ├─ Scope check (recursion depth)
  ├─ Condition matching (sorted by evaluation cost)
  └─ Plan actions (conflict‑aware, plan‑before‑act)
        ↓
Action Executor (execute or skip)
        ↓
History / Undo (SQLite)
```

All three execution paths (Dry Run, Run Now, watcher) share the same `plan()`
logic — only Dry Run skips `execute()`. `previewFile()` and `run()` both use a
`PendingFile` queue for chain processing (copies enqueued, renames update path).

## Persistence and rules

- Rules, conditions, actions, and history are stored in SQLite via the in-house `Database` wrapper.
- The rule engine lives in `Sources/HousekeeperCore/Engine`.
- UI changes that affect persistence should be backed by tests in `Tests/HousekeeperCoreTests`.
- Any change to rule behavior **or** to core file-system-touching internals —
  folder enumeration (`RuleEngine.walkEntriesInner`), file filtering/exclusion
  (`SystemFileFilter`), watcher event handling (`FileWatcher`), action
  execution, scope, recursion depth, matching, action chains — must be
  checked across all three execution paths: Dry Run preview, manual Run Now,
  and automatic watcher execution. These share most of their underlying code,
  but not all of it, so it's easy to fix or change something on one path
  (e.g. the watcher) and forget the others (e.g. Dry Run's folder scan).
  Include tests or explicit verification that all three stay consistent.

## Build and test commands

```bash
swift build
swift test
./build.sh dev      # run from a debug .app bundle
./build.sh package v1.2.3 --sign --notarize
```

## UX & design guidelines

Housekeeper's UI should feel like it belongs on the user's Mac, not like a
cross-platform app that happens to run on macOS. When adding or changing UI:

- Follow the current [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
  for macOS — standard control sizes, spacing, and SF Symbols rather than
  custom-drawn equivalents, unless the existing design system
  (`Sources/HousekeeperApp/Theme.swift`, `Components.swift`) already defines one.
- Prefer native SwiftUI/AppKit components and behaviors (sheets, popovers,
  menus, `.alert`, drag-and-drop, keyboard shortcuts) over hand-rolled ones.
  A custom control is justified only when no native one fits.
- Support both Light and Dark mode, and Dynamic Type where practical — verify
  contrast and readability in both appearances, not just the one in your
  screenshot.
- Every destructive or hard-to-reverse action (delete, clear history,
  irreversible undo) needs a clear, specific confirmation or warning — never
  a generic "Are you sure?".
- Long-running work (Run Now, Dry Run on large folders) must show progress or
  a loading state; the UI should never appear frozen or unresponsive.
- Errors and blocked actions (e.g. an unsafe undo) get a plain-language
  explanation of *why*, not just a generic failure message.
- Favor progressive disclosure: keep the default view simple, push advanced
  options (e.g. action options popovers) behind an explicit, discoverable
  affordance — and hide that affordance entirely when there's nothing to show
  (see `ActionKind.hasOptions`).
- Text the user might want to copy (file paths, error messages, history
  entries) should be selectable, not just displayed.
- When in doubt, match how a well-built native Mac app already solves the
  same problem (Finder, Mail, System Settings) rather than inventing a new
  pattern.

## Notes for contributors

- Keep the codebase macOS-only.
- Prefer the existing Swift patterns in the repo over introducing new abstractions.
- When a UI change affects saved rules or execution behavior, verify the database round-trip and execution path together.
