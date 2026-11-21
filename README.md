# Housekeeper

Free file automation for macOS. Housekeeper watches folders and runs your rules on the files
that arrive: move, copy, rename, tag, compress, import to Photos or Music, run a script, and more.

Housekeeper is a fork of [Forel](https://github.com/lab421/forel) by Lab421, changed by
Kris Northfield in November 2026. Thank you to the Forel authors.

## Differences from Forel

- No licence, no paid plan, and no limits: unlimited watched folders and files, with text
  recognition (OCR) and Photos/Music/TV imports for everyone.
- No licence server, no self-updater, and no network calls.
- Apple silicon only.
- A new name and icon.

## Install

```bash
brew install --cask knorthfield/tap/housekeeper
```

Or download `Housekeeper.zip` from [Releases](https://github.com/knorthfield/housekeeper/releases) and
move Housekeeper to Applications. Housekeeper needs macOS 14 or later on an Apple silicon Mac.

## What it does

- **Conditions:** name, extension, kind, size, tags, colour label, Finder comment, contents
  (with OCR for images and scanned PDFs), download source, locked state, and the created,
  modified, added and last-opened dates. Combine them with *all* or *any*.
- **Actions:** move, copy, sync folders, rename, compress, uncompress, add or remove a tag, set
  a colour label, lock, show or hide the extension, run a shell script, run a Shortcut, open
  with an application, import to Photos, Music or TV, move to Trash, delete.
- **Dry Run** shows what the rules will do before they do it. **Run Now** processes a folder
  by hand.
- **History and undo** for moves, tags, labels and locks.
- **Hide Dock icon** (in Settings) moves Housekeeper to the menu bar. A click on the menu bar
  icon opens the window.

Scripts run with `/bin/bash`, once for each file, with the path in `$HOUSEKEEPER_FILE`.

## Coding agents

A coding agent (Claude Code, Codex and others) can read and change your folders and rules with
the `housekeeper` command. The Homebrew cask puts it on the PATH. In the download, it is
`Housekeeper.app/Contents/MacOS/housekeeper`.

```bash
housekeeper help                                  # all commands
housekeeper schema                                # the rule format, with all permitted values
housekeeper folders add ~/Downloads
housekeeper rules add --folder ~/Downloads rule.json
housekeeper dry-run --folder ~/Downloads --rule <rule-id>
housekeeper rules enable <rule-id>
```

Rules are JSON. The command checks each rule before it saves the rule, and a new rule is
disabled until you or the agent enable it. A Dry Run shows what a rule will do and changes no
file. The command does not run actions: the app does, while it is open. The open app shows each
change immediately.

## Build

```bash
swift build
swift test
./build.sh dev                                # run from a debug .app bundle
./build.sh package v1.0.0 --sign --notarize   # signed, notarised zip in dist/release
```

## Licence

GPL-3.0-or-later, the same as Forel. See [LICENSE](LICENSE).
