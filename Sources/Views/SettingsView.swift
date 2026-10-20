import SwiftUI

/// List/detail editor for watch rules plus global options (launch at login, support).
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(model.rules) { rule in
                    Label(rule.name, systemImage: model.unavailableRules.contains(rule.id) ? "exclamationmark.triangle"
                          : rule.enabled ? "folder.fill" : "folder")
                        .tag(rule.id)
                }
            }
            .overlay {
                if model.rules.isEmpty {
                    Text("Add a folder to start watching")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .safeAreaInset(edge: .bottom) { sidebarFooter }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            if let id = selection, let rule = binding(for: id) {
                RuleDetailView(rule: rule, unavailable: model.unavailableRules.contains(id))
            } else {
                ContentUnavailableView {
                    Label(model.rules.isEmpty ? "Add a folder to start watching" : "Select a folder",
                          systemImage: "folder.badge.plus")
                } description: {
                    Text("New scans and images dropped into a watched folder become searchable PDFs, entirely on this Mac.")
                } actions: {
                    Button("Add Folder…") { selection = model.addRule() ?? selection }
                }
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button { selection = model.addRule() ?? selection } label: { Image(systemName: "plus") }
                    .help("Add a folder to watch")
                Button {
                    if let id = selection { model.removeRule(id); selection = nil }
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help("Stop watching the selected folder")
                Spacer()
            }
            .buttonStyle(.borderless)
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let error = model.loginError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Button("Support / Donate ❤️") { AppModel.openDonationPage() }
        }
        .padding(10)
    }

    private func binding(for id: UUID) -> Binding<WatchRule>? {
        guard let current = model.rules.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.rules.first { $0.id == id } ?? current },
            set: { newValue in
                if let index = model.rules.firstIndex(where: { $0.id == id }) { model.rules[index] = newValue }
            })
    }
}

/// Options for a single watch rule.
struct RuleDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var rule: WatchRule
    let unavailable: Bool

    var body: some View {
        Form {
            Section("Input") {
                LabeledContent("Folder") {
                    Text(rule.inputPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if unavailable {
                    Label("This folder can't be read. It may have been moved or access was revoked — remove it and add it again.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Toggle("Watch this folder", isOn: $rule.enabled)
                HStack {
                    Spacer()
                    Button("Process Now") { model.processNow(ruleID: rule.id) }
                        .disabled(!rule.enabled || unavailable)
                        .help("Process files already in the folder that have no output yet")
                }
            }

            Section("Output") {
                Picker("Save to", selection: $rule.outputMode) {
                    ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if rule.outputMode == .separateFolder {
                    LabeledContent("Output folder") {
                        HStack {
                            Text(rule.outputPath ?? "Not chosen").lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(rule.outputPath == nil ? .red : .primary)
                            Button("Choose…") { model.chooseOutputFolder(for: rule.id) }
                        }
                    }
                }
                TextField("File name suffix", text: $rule.suffix, prompt: Text("_ocr"))
                Text("Files whose names end with this suffix are never processed again.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Also write a plain text file", isOn: $rule.writeTextFile)
                Toggle("Move originals to the Trash after success", isOn: $rule.deleteOriginal)
            }

            Section("Recognition") {
                Picker("Level", selection: $rule.accurate) {
                    Text("Fast").tag(false)
                    Text("Accurate").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Re-process PDFs that already contain text", isOn: $rule.forceOCR)
                LanguagePicker(languages: $rule.languages, accurate: rule.accurate)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(rule.name)
    }
}

/// Checkbox grid of the languages Vision supports; none checked means automatic detection.
struct LanguagePicker: View {
    @Binding var languages: [String]
    let accurate: Bool

    var body: some View {
        let available = OCRProcessor.supportedLanguages(accurate: accurate)
        VStack(alignment: .leading, spacing: 6) {
            Text("Languages").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(available, id: \.self) { code in
                    Toggle(Locale.current.localizedString(forIdentifier: code) ?? code, isOn: Binding(
                        get: { languages.contains(code) },
                        set: { on in
                            if on { languages.append(code) } else { languages.removeAll { $0 == code } }
                        }))
                    .toggleStyle(.checkbox)
                }
            }
            Text(languages.isEmpty ? "No language selected — the language is detected automatically."
                 : "Order matters: the first checked language is preferred.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
