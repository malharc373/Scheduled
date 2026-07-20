import SwiftUI

/// The frictionless capture surface: a single text field + live activity log.
struct CaptureView: View {
    @ObservedObject var state: AppState
    /// Called to dismiss the hosting panel (Esc / after success).
    var onClose: () -> Void

    @State private var input: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TextField("gym everyday at 6am · lecture tomorrow 2pm for 2h · pay bills Fri 5pm +30m alarm · plan my day",
                      text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...4)
                .focused($focused)
                .onSubmit(submit)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.25)))

            controls

            if !state.log.isEmpty {
                Divider()
                logList
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { focused = true }
        .onExitCommand(perform: onClose) // Esc
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(.tint)
            Text("Scheduled")
                .font(.headline)
            Spacer()
            if !state.hasAPIKey {
                Label("No API key", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var controls: some View {
        HStack {
            if state.isProcessing {
                ProgressView().controlSize(.small)
                Text("Thinking…").foregroundStyle(.secondary).font(.caption)
            }
            Spacer()
            Text("↵ to schedule · esc to close")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Schedule", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(state.isProcessing || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var logList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(state.log.prefix(6)) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: entry.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(entry.isError ? .red : .green)
                            .font(.caption)
                        Text(entry.text)
                            .font(.caption)
                            .foregroundStyle(entry.isError ? .primary : .secondary)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxHeight: 150)
    }

    private func submit() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            let outcome = await state.process(text)
            if outcome.error == nil && outcome.clarification == nil && !outcome.createdSummaries.isEmpty {
                input = ""
            }
        }
    }
}
