import SwiftUI

/// The iOS capture surface: a text field, Schedule + Plan My Day actions, and a
/// running activity log. Mirrors the macOS panel using the same `AppState`.
struct CaptureScreen: View {
    @ObservedObject var state: AppState

    @State private var input: String = ""
    @State private var showSettings = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !state.hasAPIKey {
                        apiKeyBanner
                    }

                    inputCard
                    actionRow

                    if !state.log.isEmpty {
                        logSection
                    }
                }
                .padding()
            }
            .navigationTitle("Scheduled")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsScreen(state: state)
            }
        }
    }

    private var apiKeyBanner: some View {
        Button { showSettings = true } label: {
            HStack {
                Image(systemName: "key.fill")
                Text("Add your OpenRouter API key to get started")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
            .background(Color.orange.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("gym everyday at 6am · lecture tomorrow 2pm for 2h · pay bills Fri 5pm +30m alarm",
                      text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(schedule)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Tip: say “plan my day” to build today’s checklist.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: schedule) {
                HStack {
                    if state.isProcessing { ProgressView().controlSize(.small) }
                    Text(state.isProcessing ? "Working…" : "Schedule")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.isProcessing || input.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                Task { await state.planToday() }
            } label: {
                Label("Plan My Day", systemImage: "checklist")
            }
            .buttonStyle(.bordered)
            .disabled(state.isProcessing)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.headline)
            ForEach(state.log.prefix(12)) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: entry.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(entry.isError ? .red : .green)
                    Text(entry.text)
                        .font(.subheadline)
                        .foregroundStyle(entry.isError ? .primary : .secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func schedule() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            let outcome = await state.process(text)
            if outcome.error == nil && outcome.clarification == nil && !outcome.createdSummaries.isEmpty {
                input = ""
                focused = false
            }
        }
    }
}
