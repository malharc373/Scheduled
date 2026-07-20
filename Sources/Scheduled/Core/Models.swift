import Foundation

// MARK: - LLM Structured Output

/// Top-level structured payload returned by the LLM.
struct IntentResponse: Codable {
    /// One or more schedulable items parsed from the user's text.
    var items: [ScheduleItem]
    /// Non-nil when the model needs the user to clarify something ambiguous.
    var clarification: String?
}

/// A single Calendar event or Reminder to create, update, or delete.
struct ScheduleItem: Codable {
    enum Kind: String, Codable {
        case event
        case reminder
    }

    /// What to do with this item. Defaults to `.create` when the model omits it.
    enum Action: String, Codable {
        case create
        case update
        case delete
    }

    /// How to locate an existing item for an `update`/`delete`. The model rarely
    /// knows exact times, so we match by title (substring, case-insensitive)
    /// optionally narrowed to a day.
    struct Match: Codable {
        /// Title (or a distinctive keyword) of the existing item to find.
        var title: String?
        /// Approximate local date "yyyy-MM-dd" to disambiguate, or nil to search
        /// a forward window.
        var date: String?
    }

    /// "event" => time-blocked Calendar entry. "reminder" => task/todo.
    var kind: Kind
    /// create (default) / update / delete.
    var action: Action?
    /// Title of the item. May be null on update/delete (the target is in `match`).
    var title: String?
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

    /// Present on `update`/`delete`: identifies which existing item to act on.
    var match: Match?

    /// The effective action, defaulting to `.create`.
    var resolvedAction: Action { action ?? .create }

    enum CodingKeys: String, CodingKey {
        case kind, action, title, notes, location, start, end
        case allDay = "all_day"
        case recurrence
        case alarmsMinutesBefore = "alarms_minutes_before"
        case match
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
