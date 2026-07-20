import AppIntents

/// Siri / Shortcuts entry: "Schedule with Scheduled — gym everyday at 6am".
/// This is the iOS analog of the macOS global hotkey: capture from anywhere.
struct ScheduleTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Schedule"
    static var description = IntentDescription(
        "Create a calendar event or reminder from natural language.")
    /// Run in-app so EventKit permission prompts and Keychain access behave.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Request", requestValueDialog: "What should I schedule?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Schedule \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppState()
        let outcome = await state.process(text)

        if let error = outcome.error {
            return .result(dialog: IntentDialog("Sorry — \(error)"))
        }
        if let clarification = outcome.clarification, outcome.createdSummaries.isEmpty {
            return .result(dialog: IntentDialog("I need a bit more detail: \(clarification)"))
        }
        let msg = outcome.createdSummaries.joined(separator: "; ")
        return .result(dialog: IntentDialog("\(msg.isEmpty ? "Nothing to schedule." : msg)"))
    }
}

/// Siri / Shortcuts entry: "Plan my day with Scheduled".
struct PlanMyDayIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan My Day"
    static var description = IntentDescription(
        "Build today's checklist from your calendar, routine, and due reminders.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppState().planToday()
        if let error = outcome.error {
            return .result(dialog: IntentDialog("Sorry — \(error)"))
        }
        let msg = outcome.createdSummaries.first ?? "Your day is planned."
        return .result(dialog: IntentDialog("\(msg)"))
    }
}

/// Registers spoken phrases so the intents work from Siri with no setup.
struct ScheduledShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScheduleTextIntent(),
            phrases: [
                "Schedule with \(.applicationName)",
                "Add to \(.applicationName)",
                "\(.applicationName) schedule"
            ],
            shortTitle: "Schedule",
            systemImageName: "calendar.badge.plus")

        AppShortcut(
            intent: PlanMyDayIntent(),
            phrases: [
                "Plan my day with \(.applicationName)",
                "\(.applicationName) plan my day"
            ],
            shortTitle: "Plan My Day",
            systemImageName: "checklist")
    }
}
