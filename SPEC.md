# WatchFolderOcr — specification

**Tagline:** Watch a folder and automatically turn every dropped scan or image into a searchable PDF with a text layer.

**Category:** Files & Conversion

**Inspired by (paid):** OnDevice OCR Pro ($12.99 one-time)

**Frameworks:** SwiftUI, AppKit, Vision, PDFKit, CoreGraphics, UniformTypeIdentifiers, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: OnDevice OCR Pro runs local text recognition with Apple's Vision framework, batch processes PDFs and nearly all image formats, and monitors folders so new files are processed in the background, priced at 12.99 one-time. Other small apps such as OCRmyPDF Batch at about 4 dollars show the same need: scanner output and phone photos are not searchable, and people want a private, no-upload fix. Our clean-room version focuses on the watch-folder workflow.

Feature set for WatchFolderOcr: a menu bar app with a list of watched folders. Each watch rule has an input folder, an output choice (same folder with a suffix, or a separate folder), and a language list. When a new PDF or image appears, the app renders each page, recognizes text, and writes a new PDF in which the original page image is kept and an invisible text layer is added so Spotlight and Preview can search and select the words. Optionally also write a plain text file beside it. A Process Now button handles files already in the folder, and a small log shows each file with status and page count.

UI spec: MenuBarExtra with status line (Idle or Processing 3 of 12), Pause toggle, Open Log, Settings, Quit. The Settings window is a list and detail layout: add or remove folder rules, set output mode, suffix text, language checkboxes, recognition level (fast or accurate), delete original toggle default off, also write text file toggle, and launch at login. The log window is a table with name, pages, duration and result. Empty state: Add a folder to start watching.

Technical approach: watch folders with a DispatchSource file system object or a 3 second polling scan, waiting for stable file size before reading. Folder access uses an NSOpenPanel with security-scoped bookmarks saved to UserDefaults. For PDFs, use PDFKit to render each PDFPage into a CGImage at about 200 DPI, and for images load with ImageIO. Recognize with Vision VNRecognizeTextRequest, using recognitionLanguages, accurate level and language correction. To build the output, create a CGContext PDF with CGContext(consumer:mediaBox:), draw the page image, then draw each recognized string invisibly using CoreText with text rendering mode invisible (mode 3), positioned and sized from the observation's bounding box, converting from Vision's normalized coordinates to page coordinates. Processing uses a serial queue with progress reported to the UI, and each file handled in an autorelease pool to cap memory. No permissions beyond the folders chosen. Launch at login uses SMAppService.

Edge cases and error handling: skip PDFs that already contain a text layer, detected by extracting page strings with PDFKit, unless forced. Do not reprocess outputs, ignoring files with the chosen suffix. Password protected PDFs are logged as skipped. Handle huge page counts by processing page by page and writing incrementally. If recognition returns nothing for a page, still copy the page image. On failure leave the original untouched and log the error. Never delete originals unless the toggle is on, and move them to the Trash rather than removing them permanently.
