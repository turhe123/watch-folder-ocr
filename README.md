# WatchFolderOcr

Watch a folder and automatically turn every dropped scan or image into a searchable PDF with a text layer.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![Latest release](https://img.shields.io/github/v/release/turhe123/watch-folder-ocr)

## Why

Scanner output and phone photos are usually not searchable, and many people don't want to upload their documents anywhere to fix that. WatchFolderOcr is a free, open-source, 100% native, backend-free alternative to paid utilities in the *Files & Conversion* category (inspired by OnDevice OCR Pro, $12.99 one-time). Everything runs on your Mac with Apple's Vision framework.

## Features

- **Menu bar app** with a status line (Idle, Processing 3 of 12, Paused), a Pause toggle, Process Now, Open Log, Settings and Quit.
- **Multiple watch rules**: each rule has its own input folder, output options and recognition settings.
- **Automatic detection**: folders are scanned every 3 seconds, and a file is only processed once its size and modification date are stable across two scans, so half-copied files are not read.
- **Existing files are left alone** when a folder is first added; use **Process Now** to convert files already in it (files that already have an output are skipped).
- **PDFs and images**: PDFs plus image formats that macOS can read (via ImageIO), including multi-page images.
- **Searchable output**: the original page image is kept and an invisible text layer is added, so Spotlight and Preview can search and select the words.
- **Output choices**: same folder with a filename suffix (default `_ocr`) or a separate folder. Files ending in the suffix are never reprocessed.
- **Optional plain text file** written next to the PDF.
- **Recognition options**: Fast or Accurate level, language correction, and a checkbox list of the languages Vision supports. With none checked, the language is detected automatically.
- **Skips what it should**: PDFs that already contain text (unless "Re-process PDFs that already contain text" is on) and password-protected PDFs are logged as skipped.
- **Safe by design**: output is written to a temporary file and moved into place, so a failure never leaves a partial PDF. The original is untouched on error.
- **Optional trash of originals**: off by default; when on, originals are moved to the Trash (not deleted permanently) after success.
- **Processing log** with name, pages, duration and result for the last 500 files.
- **Launch at login** via `SMAppService`.
- **Support / Donate ❤️** button in the menu and Settings.

## Screenshots

_Screenshots coming soon._

## Install

1. Download `WatchFolderOcr-macOS.zip` from <https://github.com/turhe123/watch-folder-ocr/releases/latest>.
2. Unzip it and move `WatchFolderOcr.app` to `/Applications`.
3. Because the app is open source and not notarized, run:

   ```bash
   xattr -cr /Applications/WatchFolderOcr.app
   ```

4. Right-click the app and choose **Open** the first time.

## Build from source

Requires macOS 14+ and Xcode with Swift 5.9+.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project WatchFolderOcr.xcodeproj -scheme WatchFolderOcr -configuration Release -derivedDataPath ./build build
```

The app is produced at `build/Build/Products/Release/WatchFolderOcr.app`.

## Permissions

WatchFolderOcr does **not** ask for Accessibility, Screen Recording, Microphone, Camera or any other system privacy permission, and it makes no network connections. The only access it uses is:

- **Folders you choose**: each watch folder (and optional output folder) is picked in a standard open panel. The app remembers them with security-scoped bookmarks stored in UserDefaults, so it can read and write only those folders.
- **Login item** (optional): if you turn on "Launch at login", the app registers itself with `SMAppService`. You can review this in System Settings › General › Login Items.

## Built with AI

WatchFolderOcr was written by [Claude Code](https://claude.com/claude-code) inside an automated pipeline, from a plain-English spec. No code, binaries or assets from any commercial app were used; it is a clean-room reimplementation of a feature set, not a copy.

What that means in practice:

- The full source is in this repo under the MIT license. Read it before you run it.
- No network calls, no analytics, no third-party dependencies. Only Apple frameworks.
- Ad-hoc signed and not notarized, which is why Gatekeeper warns on first launch.
- It has had less human review than a hand-written app. Bug reports and pull requests are welcome.

## Support ❤️

If this saves you time, you can support the author: [Support Or (Leo) Davidai ❤️](https://ko-fi.com/leodavidai)

## License

MIT © Or Davidai Bachar
