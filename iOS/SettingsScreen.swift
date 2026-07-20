import SwiftUI

/// iOS settings: OpenRouter API key (BYO-key, stored in Keychain) + model + a
/// natural-language routine editor used by "Plan My Day".
struct SettingsScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var keyField = ""
    @State private var modelField = ""
    @State private var routineText = ""
    @State private var routineStatus = ""
    @State private var savingRoutine = false

    private let suggestedModels = [
        "anthropic/claude-haiku-4.5",
        "anthropic/claude-sonnet-4.5",
        "openai/gpt-4o-mini",
        "google/gemini-flash-latest"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenRouter API Key") {
                    SecureField(state.hasAPIKey ? "•••••• (stored)" : "sk-or-…", text: $keyField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Stored securely in the Keychain. Get a key at openrouter.ai/keys.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Model") {
                    TextField("model id", text: $modelField)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Suggested", selection: $modelField) {
                        ForEach(suggestedModels, id: \.self) { Text($0).tag($0) }
                    }
                }

                Section("Daily routine") {
                    Text("Describe your day in plain English; used by Plan My Day.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("gym 6am, meal prep 7am and 6pm, read 30 min at 9pm",
                              text: $routineText, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                    Button {
                        saveRoutine()
                    } label: {
                        HStack {
                            if savingRoutine { ProgressView().controlSize(.small) }
                            Text("Save Routine")
                        }
                    }
                    .disabled(savingRoutine || routineText.trimmingCharacters(in: .whitespaces).isEmpty)
                    if !routineStatus.isEmpty {
                        Text(routineStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { save(); dismiss() }
                }
            }
            .onAppear {
                modelField = state.model
                routineText = RoutineStore.describe(RoutineStore.load()) == "(routine is empty)"
                    ? "" : routineText
            }
        }
    }

    private func save() {
        if !keyField.isEmpty { state.saveAPIKey(keyField); keyField = "" }
        let m = modelField.trimmingCharacters(in: .whitespaces)
        state.model = m.isEmpty ? OpenRouterClient.defaultModel : m
    }

    private func saveRoutine() {
        save() // ensure key/model are current
        guard let key = Keychain.apiKey(), !key.isEmpty else {
            routineStatus = "Add your API key first."
            return
        }
        savingRoutine = true
        routineStatus = ""
        let text = routineText
        Task {
            defer { savingRoutine = false }
            do {
                let routine = try await OpenRouterClient(apiKey: key, model: state.model)
                    .parseRoutine(text)
                _ = RoutineStore.save(routine)
                routineStatus = "Saved \(routine.items.count) routine items."
            } catch {
                routineStatus = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
