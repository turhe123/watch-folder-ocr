import SwiftUI

/// Table of processed files with page count, duration and result.
struct LogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Table(model.log) {
            TableColumn("Name", value: \.name)
            TableColumn("Pages") { entry in Text(entry.pages > 0 ? "\(entry.pages)" : "–") }
                .width(min: 40, ideal: 50, max: 70)
            TableColumn("Duration") { entry in Text(String(format: "%.1f s", entry.duration)) }
                .width(min: 60, ideal: 70, max: 90)
            TableColumn("Result") { entry in
                Label(entry.message, systemImage: icon(entry.outcome))
                    .foregroundStyle(color(entry.outcome))
                    .help(entry.message)
            }
        }
        .overlay {
            if model.log.isEmpty {
                ContentUnavailableView("No Files Processed Yet", systemImage: "doc.text.magnifyingglass",
                                       description: Text(model.rules.isEmpty ? "Add a folder to start watching." : model.statusLine))
            }
        }
        .toolbar {
            ToolbarItem {
                Text(model.statusLine).foregroundStyle(.secondary)
            }
            ToolbarItem {
                Button("Clear", systemImage: "trash") { model.clearLog() }
                    .disabled(model.log.isEmpty)
            }
        }
    }

    private func icon(_ outcome: LogEntry.Outcome) -> String {
        switch outcome {
        case .success: return "checkmark.circle.fill"
        case .skipped: return "forward.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func color(_ outcome: LogEntry.Outcome) -> Color {
        switch outcome {
        case .success: return .green
        case .skipped: return .secondary
        case .failed: return .red
        }
    }
}
