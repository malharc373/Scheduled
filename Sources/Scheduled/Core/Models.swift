import Foundation

// MARK: - LLM Structured Output

/// Top-level structured payload returned by the LLM.
struct IntentResponse: Codable {
    /// One or more schedulable items parsed from the user's text.
    var items: [ScheduleItem]
    /// Non-nil when the model needs the user to clarify something ambiguous.
    var clarification: String?
}

/// A single Calendar event or Reminder to create.
struct ScheduleItem: Codable {
    enum Kind: String, Codable {
        case event
        case reminder
    }

    /// "event" => time-blocked Calendar entry. "reminder" => task/todo.
    var kind: Kind
    var title: String
    var notes: String?
    var location: String?

    /// Local wall-clock start, "yyyy-MM-dd'T'HH:mm:ss" or "yyyy-MM-dd" for all-day.
    var start: String?
    /// Local wall-clock end (events only).
    var end: String?
    var allDay: Bool?

    var recurrence: Recurrence?

    /// Alarm offsets in minutes *before* the start/due time. 0 == at time of event.
    var alarmsMinutesBefore: [Int]?

    enum CodingKeys: String, CodingKey {
        case kind, title, notes, location, start, end
        case allDay = "all_day"
        case recurrence
        case alarmsMinutesBefore = "alarms_minutes_before"
    }
}

/// A recurrence rule (daily / weekly / monthly / yearly).
struct Recurrence: Codable {
    enum Frequency: String, Codable {
        case daily, weekly, monthly, yearly
    }

    var frequency: Frequency
    /// Every N units. Defaults to 1 when omitted.
    var interval: Int?
    /// Two-letter weekday codes for weekly rules: MO TU WE TH FR SA SU.
    var daysOfWeek: [String]?
    /// Stop after N occurrences.
    var count: Int?
    /// Stop on/after this local date, "yyyy-MM-dd".
    var until: String?

    enum CodingKeys: String, CodingKey {
        case frequency, interval, count, until
        case daysOfWeek = "days_of_week"
    }
}

// MARK: - App-facing result types

/// Outcome of processing one line of natural-language input.
struct ProcessOutcome {
    var createdSummaries: [String]
    var clarification: String?
    var error: String?
}
