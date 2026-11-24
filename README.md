# Worshpick

A macOS app that helps you choose the worship songs for a church service from your own library of lyric videos.

You import your lyric videos. Worshpick reads the lyrics from the video frames and uses Claude to tag each song: what it invites people to do (reflection, joy, hope…), its themes, related Bible passages, the moment of the service it fits, and its energy. Then you build a setlist in one of two ways:

- **Suggest:** describe the service (passages, main idea, occasion) and Claude picks songs from your catalog. You can swap any of them.
- **Search:** fast, offline search by title, artist, lyrics, meaning, tags, and Bible references such as `Romanos 8` or `Sal 23`.

The result is an ordered list of video files that you drag straight into your presentation software or any other app that accepts video files.

> The app interface is in Spanish.

## Features

- **Import:** drag videos (`.mp4`, `.mov`, `.m4v`) onto the window, or use *Importar…*. Each video is copied into Worshpick's own library. Duplicates are detected by file hash.
- **AI ingest pipeline:** frame sampling with near-duplicate removal → OCR with Apple Vision (or Claude as an alternative engine) → analysis by Claude with a strict JSON schema. The queue is saved to disk and resumes when the app opens again.
- **Search without AI:** SQLite FTS5, facet filters (invitation, theme, moment, energy, language, not used recently), and a Bible reference parser that matches whole chapters, verses and ranges across chapters.
- **Suggester:** uses service templates (for example two opening songs, two worship songs and one response song) and avoids songs used in the last N Sundays. Claude can only return songs that are in your catalog.
- **Editable results:** every AI field can be edited by hand, and later reprocessing does not overwrite your edits.
- **Bulk actions:** select several songs (Shift + click, Shift + arrow keys, ⌘ + click) to add them to the setlist, reanalyze them, reprocess them with Claude OCR, or remove them.
- **Setlists:** reorder songs, save drafts, mark a setlist as used (this feeds the usage history), and drag the video files into your presentation app.

## Requirements

- macOS 15 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Claude Code](https://claude.com/claude-code), installed and signed in. Worshpick runs the `claude` CLI with your own account, so you do not need an API key.

## Build and run

```bash
scripts/generate-project.sh
```

```bash
open Worshpick.xcodeproj
```

Run the **Worshpick** scheme from Xcode. To build a Release copy and install it in `/Applications`:

```bash
xcodebuild -project Worshpick.xcodeproj -scheme Worshpick -configuration Release -derivedDataPath DerivedData build
```

```bash
ditto DerivedData/Build/Products/Release/Worshpick.app /Applications/Worshpick.app
```

The Release build is signed ad hoc, so it runs on the Mac that built it.

The app is not sandboxed, because it must run your own `claude` binary. If Worshpick cannot find the CLI, set its path in *Ajustes → CLI de Claude*.

## Tests

```bash
scripts/test.sh
```

This runs the `WorshpickCore` test suite and builds the app. Tests use a fake Claude runner with fixed answers, so they do not use your Claude account.

## Where your data lives

Everything is stored on your Mac in `~/Library/Application Support/Worshpick/`:

| Path | Contents |
|---|---|
| `catalog.sqlite` | Songs, tags, passages, setlists, and usage history |
| `Videos/<uuid>/<original name>` | The copied videos. The original file name is kept, because presentation apps show it. |
| `settings.json` | Settings, vocabularies, and service templates |

Claude receives only the OCR text and the file name of a song, except when you choose *Reprocesar con Claude OCR*. In that case it also reads up to 40 frames of the video.

## Project layout

```
Worshpick/                 SwiftUI app
├── App/                   App entry point and AppModel (connects the core services to the views)
├── Components/            Stateless views
├── Containers/            Stateful screens: library, suggest, setlists, settings
├── Helpers/
└── Assets/
Packages/WorshpickCore/    Swift package with all the logic and its tests
├── Models/                Song, passage, setlist, service template
├── Stores/                SQLite (GRDB) catalog, setlists, settings
├── Services/              Ingest pipeline, frame sampler, OCR, Claude CLI, analyzer, suggester, search
├── Helpers/               Bible reference parser, search query parser, text helpers
└── Constants/             Bible books, default vocabularies, JSON schemas
docs/                      Design spec, implementation plan, app icon sources
scripts/                   Project generation, tests, test video tools
```

`project.yml` is the source of truth for the Xcode project. After you add or remove files, run `scripts/generate-project.sh` again.
