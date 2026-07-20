import Foundation
import SwiftUI

/// A single line in the capture window's activity log.
struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
    let isError: Bool
}

/// Central observable state shared by the capture and settings UIs.
@MainActor
final class AppState: ObservableObject {
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }
    @Published var hasAPIKey: Bool
    @Published var isProcessing = false
    @Published var log: [LogEntry] = []

    private let eventKit = EventKitManager()
    private lazy var planner = DayPlanner(eventKit: eventKit)

    init() {
        self.model = UserDefaults.standard.string(forKey: "model")
            ?? OpenRouterClient.defaultModel
        self.hasAPIKey = (Keychain.apiKey()?.isEmpty == false)
    }

    // MARK: - API key

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete()
        } else {
            Keychain.save(trimmed)
        }
        hasAPIKey = (Keychain.apiKey()?.isEmpty == false)
    }

    // MARK: - Core pipeline

    /// Parses input via OpenRouter and creates the resulting items in EventKit.
    @discardableResult
    func process(_ input: String) async -> ProcessOutcome {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return ProcessOutcome(createdSummaries: [], clarification: nil, error: nil)
        }

        // Natural shortcut: "plan my day" builds today's checklist directly.
        if Self.isPlanDayCommand(text) {
            return await planToday()
        }

        guard let key = Keychain.apiKey(), !key.isEmpty else {
            let msg = OpenRouterError.missingKey.localizedDescription
            appendLog(msg, isError: true)
            return ProcessOutcome(createdSummaries: [], clarification: nil, error: msg)
        }

        isProcessing = true
        defer { isProcessing = false }

        let client = OpenRouterClient(apiKey: key, model: model)
        do {
            let intent = try await client.parse(text)

            if let clarification = intent.clarification,
               !clarification.isEmpty,
               intent.items.isEmpty {
                appendLog("❓ \(clarification)", isError: false)
                return ProcessOutcome(createdSummaries: [], clarification: clarification, error: nil)
            }

            var summaries: [String] = []
            for item in intent.items {
                let summary = try await eventKit.create(item)
                summaries.append(summary)
                appendLog(summary, isError: false)
            }

            if summaries.isEmpty {
                appendLog("Nothing to schedule from that input.", isError: true)
            }
            return ProcessOutcome(createdSummaries: summaries,
                                  clarification: intent.clarification,
                                  error: nil)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            appendLog("⚠️ \(msg)", isError: true)
            return ProcessOutcome(createdSummaries: [], clarification: nil, error: msg)
        }
    }

    /// Builds today's checklist in the "Today's Plan" reminders list.
    @discardableResult
    func planToday() async -> ProcessOutcome {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let summary = try await planner.planDay()
            appendLog(summary, isError: false)
            return ProcessOutcome(createdSummaries: [summary], clarification: nil, error: nil)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            appendLog("⚠️ \(msg)", isError: true)
            return ProcessOutcome(createdSummaries: [], clarification: nil, error: msg)
        }
    }

    static func isPlanDayCommand(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let triggers = ["plan my day", "plan my today", "plan today",
                        "plan the day", "daily checklist", "make my day",
                        "plan day"]
        return triggers.contains(t)
    }

    private func appendLog(_ text: String, isError: Bool) {
        log.insert(LogEntry(text: text, isError: isError), at: 0)
        if log.count > 50 { log.removeLast(log.count - 50) }
    }
}
