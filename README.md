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

Or download the DMG from [Releases](https://github.com/knorthfield/housekeeper/releases) and
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
- A menu bar panel with the watched folders and recent activity.

Scripts run with `/bin/bash`, once for each file, with the path in `$HOUSEKEEPER_FILE`.

## Build

```bash
swift build
swift test
./build.sh dev                                # run from a debug .app bundle
./build.sh package v1.0.0 --sign --notarize   # signed, notarised DMG in dist/release
```

## Licence

GPL-3.0-or-later, the same as Forel. See [LICENSE](LICENSE).
