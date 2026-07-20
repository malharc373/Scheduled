import SwiftUI

/// Settings popover: OpenRouter key + model selection.
struct SettingsView: View {
    @ObservedObject var state: AppState
    var onClose: () -> Void

    @State private var keyField: String = ""
    @State private var modelField: String = ""
    @State private var savedFlash = false

    private let suggestedModels = [
        "anthropic/claude-haiku-4.5",
        "anthropic/claude-sonnet-4.5",
        "openai/gpt-4o-mini",
        "google/gemini-flash-latest"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("OpenRouter API Key").font(.subheadline).bold()
                SecureField(state.hasAPIKey ? "•••••• (stored in Keychain)" : "sk-or-…",
                            text: $keyField)
                    .textFieldStyle(.roundedBorder)
                Text("Stored in the macOS Keychain. Leave blank to keep the current key; you can also set OPENROUTER_API_KEY.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Model").font(.subheadline).bold()
                TextField("model id", text: $modelField)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    ForEach(suggestedModels.prefix(3), id: \.self) { m in
                        Button(shortName(m)) { modelField = m }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }

            HStack {
                if savedFlash {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                }
                Spacer()
                Button("Close", action: onClose)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear { modelField = state.model }
    }

    private func shortName(_ id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    private func save() {
        if !keyField.isEmpty { state.saveAPIKey(keyField); keyField = "" }
        let m = modelField.trimmingCharacters(in: .whitespaces)
        state.model = m.isEmpty ? OpenRouterClient.defaultModel : m
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedFlash = false }
    }
}
