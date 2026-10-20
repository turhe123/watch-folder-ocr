import SwiftUI

/// App entry point: a menu bar extra plus the Settings and Log windows.
@main
struct WatchFolderOcrApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("WatchFolderOcr",
                     systemImage: model.isProcessing ? "arrow.triangle.2.circlepath" : "doc.text.viewfinder") {
            MenuContent()
                .environmentObject(model)
        }

        Window("WatchFolderOcr Settings", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .defaultSize(width: 760, height: 560)

        Window("Processing Log", id: "log") {
            LogView()
                .environmentObject(model)
        }
        .defaultSize(width: 680, height: 420)
    }
}

/// Items shown in the menu bar dropdown.
struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusLine)
        if let file = model.currentFile {
            Text(file)
        }
        Divider()
        Toggle("Pause", isOn: $model.isPaused)
        Button("Process Now") { model.processNow() }
            .disabled(model.rules.isEmpty)
        Divider()
        Button("Open Log…") { show("log") }
            .keyboardShortcut("l")
        Button("Settings…") { show("settings") }
            .keyboardShortcut(",")
        Divider()
        Button("Support / Donate ❤️") { AppModel.openDonationPage() }
        Divider()
        Button("Quit WatchFolderOcr") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}
