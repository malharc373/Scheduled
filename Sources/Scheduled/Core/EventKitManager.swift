import Foundation
import EventKit

enum EventKitError: LocalizedError {
    case accessDenied(String)
    case noCalendar(String)
    case missingStart(String)
    case save(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let s): return "Access denied: \(s)"
        case .noCalendar(let s): return s
        case .missingStart(let s): return s
        case .save(let s): return "Failed to save: \(s)"
        }
    }
}

/// Creates Calendar events and Reminders through EventKit. Anything written
/// here lands in the user's default iCloud calendar/list and syncs to all their
/// Apple devices automatically; `EKAlarm`s become native cross-device alerts.
final class EventKitManager {
    let store = EKEventStore()

    private let defaultEventDuration: TimeInterval = 60 * 60 // 1 hour

    // MARK: - Authorization

    func ensureEventAccess() async throws {
        if #available(macOS 14.0, iOS 17.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            if !granted { throw EventKitError.accessDenied("Calendar") }
        } else {
            try await legacyRequest(.event)
        }
    }

    func ensureReminderAccess() async throws {
        if #available(macOS 14.0, iOS 17.0, *) {
            let granted = try await store.requestFullAccessToReminders()
            if !granted { throw EventKitError.accessDenied("Reminders") }
        } else {
            try await legacyRequest(.reminder)
        }
    }

    private func legacyRequest(_ type: EKEntityType) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAccess(to: type) { granted, error in
                if let error { cont.resume(throwing: error) }
                else if granted { cont.resume() }
                else { cont.resume(throwing: EventKitError.accessDenied("\(type)")) }
            }
        }
    }

    // MARK: - Public entry point

    /// Creates one item and returns a human-readable summary line.
    func create(_ item: ScheduleItem) async throws -> String {
        switch item.kind {
        case .event:    return try await createEvent(item)
        case .reminder: return try await createReminder(item)
        }
    }

    // MARK: - Events

    private func createEvent(_ item: ScheduleItem) async throws -> String {
        try await ensureEventAccess()
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw EventKitError.noCalendar("No default calendar found for new events.")
        }
        guard let startStr = item.start,
              let (start, dateOnly) = DateParsing.parse(startStr) else {
            throw EventKitError.missingStart("Event \"\(item.title)\" had no usable start time.")
        }

        let event = EKEvent(eventStore: store)
        event.title = item.title
        event.notes = item.notes
        event.location = item.location
        event.calendar = calendar

        let isAllDay = item.allDay ?? dateOnly
        event.isAllDay = isAllDay
        event.startDate = start

        if isAllDay {
            event.endDate = start
        } else if let endStr = item.end, let (end, _) = DateParsing.parse(endStr), end > start {
            event.endDate = end
        } else {
            event.endDate = start.addingTimeInterval(defaultEventDuration)
        }

        if let rule = buildRule(item.recurrence) {
            event.recurrenceRules = [rule]
        }

        for minutes in (item.alarmsMinutesBefore ?? []) {
            event.addAlarm(EKAlarm(relativeOffset: -Double(minutes) * 60))
        }

        do {
            try store.save(event, span: item.recurrence == nil ? .thisEvent : .futureEvents, commit: true)
        } catch {
            throw EventKitError.save(error.localizedDescription)
        }
        return summary(prefix: "📅 Event", item: item, date: start, allDay: isAllDay)
    }

    // MARK: - Reminders

    private func createReminder(_ item: ScheduleItem) async throws -> String {
        try await ensureReminderAccess()
        guard let calendar = store.defaultCalendarForNewReminders()
                ?? store.calendars(for: .reminder).first else {
            throw EventKitError.noCalendar("No Reminders list found.")
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = item.title
        reminder.notes = item.notes
        reminder.calendar = calendar

        var due: Date?
        if let startStr = item.start, let (date, dateOnly) = DateParsing.parse(startStr) {
            due = date
            let comps: Set<Calendar.Component> = dateOnly
                ? [.year, .month, .day]
                : [.year, .month, .day, .hour, .minute]
            reminder.dueDateComponents = Calendar.current.dateComponents(comps, from: date)
        }

        if let rule = buildRule(item.recurrence) {
            reminder.recurrenceRules = [rule]
        }

        // Reminders use absolute-date alarms reliably across devices.
        if let due {
            let offsets = item.alarmsMinutesBefore ?? [0]
            for minutes in offsets {
                let fire = due.addingTimeInterval(-Double(minutes) * 60)
                reminder.addAlarm(EKAlarm(absoluteDate: fire))
            }
        }

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw EventKitError.save(error.localizedDescription)
        }
        return summary(prefix: "✅ Reminder", item: item, date: due, allDay: false)
    }

    // MARK: - Recurrence

    private func buildRule(_ rec: Recurrence?) -> EKRecurrenceRule? {
        guard let rec else { return nil }

        let frequency: EKRecurrenceFrequency
        switch rec.frequency {
        case .daily:   frequency = .daily
        case .weekly:  frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly:  frequency = .yearly
        }

        let days: [EKRecurrenceDayOfWeek]? = rec.daysOfWeek?.compactMap { code in
            Self.weekday(from: code).map { EKRecurrenceDayOfWeek($0) }
        }

        var end: EKRecurrenceEnd?
        if let count = rec.count, count > 0 {
            end = EKRecurrenceEnd(occurrenceCount: count)
        } else if let untilStr = rec.until, let (untilDate, _) = DateParsing.parse(untilStr) {
            end = EKRecurrenceEnd(end: untilDate)
        }

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, rec.interval ?? 1),
            daysOfTheWeek: (days?.isEmpty == false) ? days : nil,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private static func weekday(from code: String) -> EKWeekday? {
        switch code.uppercased() {
        case "SU": return .sunday
        case "MO": return .monday
        case "TU": return .tuesday
        case "WE": return .wednesday
        case "TH": return .thursday
        case "FR": return .friday
        case "SA": return .saturday
        default:   return nil
        }
    }

    // MARK: - Summaries

    private func summary(prefix: String, item: ScheduleItem, date: Date?, allDay: Bool) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = allDay ? "EEE, MMM d" : "EEE, MMM d 'at' h:mm a"

        var parts = ["\(prefix): \(item.title)"]
        if let date { parts.append(df.string(from: date)) }
        if let rec = item.recurrence { parts.append("(\(recurrenceLabel(rec)))") }
        if let alarms = item.alarmsMinutesBefore, !alarms.isEmpty {
            let labels = alarms.map { $0 == 0 ? "at time" : "\($0)m before" }
            parts.append("🔔 " + labels.joined(separator: ", "))
        }
        return parts.joined(separator: " — ")
    }

    private func recurrenceLabel(_ rec: Recurrence) -> String {
        let interval = max(1, rec.interval ?? 1)
        let every = interval == 1 ? "every" : "every \(interval)"
        switch rec.frequency {
        case .daily:   return "\(every) day"
        case .weekly:
            if let days = rec.daysOfWeek, !days.isEmpty {
                return "\(every) week on \(days.joined(separator: ","))"
            }
            return "\(every) week"
        case .monthly: return "\(every) month"
        case .yearly:  return "\(every) year"
        }
    }
}

// MARK: - Date parsing

/// Parses the LLM's local wall-clock strings into `Date`s in the current
/// timezone. Returns whether the string was date-only (=> all-day candidate).
enum DateParsing {
    static func parse(_ raw: String) -> (date: Date, dateOnly: Bool)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        let dateTime = DateFormatter()
        dateTime.locale = Locale(identifier: "en_US_POSIX")
        dateTime.timeZone = .current
        dateTime.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = dateTime.date(from: s) { return (d, false) }

        // Some models emit "T HH:mm" without seconds.
        dateTime.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let d = dateTime.date(from: s) { return (d, false) }

        // Space-separated variant.
        dateTime.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = dateTime.date(from: s) { return (d, false) }
        dateTime.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = dateTime.date(from: s) { return (d, false) }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = .current
        dateOnly.dateFormat = "yyyy-MM-dd"
        if let d = dateOnly.date(from: s) { return (d, true) }

        return nil
    }
}
