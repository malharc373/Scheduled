import SwiftUI

/// First-run screen. Explains the bring-your-own-key model and lets the user
/// paste their OpenRouter key (or skip). Shown once until a key is stored.
struct OnboardingScreen: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var keyField = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    steps
                    keyEntry
                    privacyNote
                }
                .padding()
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("Plain English → Calendar & Reminders")
                .font(.title2).bold()
            Text("Scheduled runs on your own OpenRouter API key, so it uses your account — free to start, no subscription, nothing billed to anyone else.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            step("1.circle.fill") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get a free API key").bold()
                    Link("openrouter.ai/keys",
                         destination: URL(string: "https://openrouter.ai/keys")!)
                }
            }
            step("2.circle.fill") {
                Text("Paste it below — it's stored only in this device's Keychain.")
            }
            step("3.circle.fill") {
                Text("Type things like \u{201C}gym everyday at 6am\u{201D} — or ask Siri.")
            }
        }
        .font(.subheadline)
    }

    private func step<Content: View>(_ symbol: String,
                                     @ViewBuilder _ content: () -> Content) -> some View {
        Label { content() } icon: {
            Image(systemName: symbol).foregroundStyle(.tint)
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("sk-or-\u{2026}", text: $keyField)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                state.saveAPIKey(keyField)
                if state.hasAPIKey { dismiss() }
            } label: {
                Text("Save & Get Started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("No cost? Pick a model ending in \u{201C}:free\u{201D} in Settings (rate-limited).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var privacyNote: some View {
        Text("Privacy: the text you enter is sent to OpenRouter to interpret your request. Nothing else leaves your device.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}
