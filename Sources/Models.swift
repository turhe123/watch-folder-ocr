import Foundation

/// Where a rule writes its searchable PDFs.
enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case sameFolder, separateFolder
    var id: String { rawValue }
    var label: String { self == .sameFolder ? "Same folder (add suffix)" : "Separate folder" }
}

/// A watched-folder rule: input folder, output destination and recognition options.
struct WatchRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var inputBookmark: Data
    var inputPath: String
    var outputMode: OutputMode = .sameFolder
    var outputBookmark: Data?
    var outputPath: String?
    var suffix: String = "_ocr"
    var languages: [String] = ["en-US"]
    var accurate: Bool = true
    var deleteOriginal: Bool = false
    var writeTextFile: Bool = false
    var forceOCR: Bool = false
    var enabled: Bool = true

    var name: String { (inputPath as NSString).lastPathComponent }

    /// Suffix actually applied; the same-folder mode always needs one so outputs are never reprocessed.
    var effectiveSuffix: String {
        let trimmed = suffix.trimmingCharacters(in: .whitespaces)
        return outputMode == .sameFolder && trimmed.isEmpty ? "_ocr" : trimmed
    }
}

/// One row of the processing log.
struct LogEntry: Identifiable {
    enum Outcome { case success, skipped, failed }
    let id = UUID()
    let date = Date()
    let name: String
    let pages: Int
    let duration: TimeInterval
    let outcome: Outcome
    let message: String
}

/// Creates and resolves security-scoped bookmarks so folder access survives relaunches.
enum Bookmarks {
    static func make(for url: URL) -> Data? {
        (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData())
    }

    static func resolve(_ data: Data) -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                              relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url
        }
        return try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
