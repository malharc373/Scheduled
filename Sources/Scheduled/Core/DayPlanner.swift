import Foundation
import EventKit

/// Builds a single, tickable Reminders checklist for a given day by merging:
///   1. Calendar events happening that day (incl. recurring instances such as
///      "gym everyday at 6am" and that day's lectures / one-off extras),
///   2. the user's personal routine template (meal prep, journaling, …),
///   3. incomplete reminders already due that day (from other lists).
///
/// Everything lands in a dedicated iCloud "Today's Plan" reminders list so it
/// syncs to iPhone/iPad/Watch and can be checked off item by item.
final class DayPlanner {
    static let listTitle = "Today's Plan"
    /// Hidden marker written into each generated reminder's notes so re-running
    /// a plan for the same day replaces (rather than duplicates) its items.
    private static let marker = "[scheduled-plan]"

    private let eventKit: EventKitManager
    private var store: EKEventStore { eventKit.store }

    init(eventKit: EventKitManager = EventKitManager()) {
        self.eventKit = eventKit
    }

    /// A merged checklist entry before it becomes a reminder.
    private struct Entry {
        var title: String
        var time: Date?      // due time; nil == anytime
        var notes: String?
        var source: String   // for the summary
    }

    func planDay(for date: Date = Date()) async throws -> String {
        try await eventKit.ensureEventAccess()
        try await eventKit.ensureReminderAccess()

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? date

        var entries: [Entry] = []
        var seenKeys = Set<String>()

        // Dedupe only true duplicates: same title AND same time (e.g. "gym" as
        // both a calendar event and a routine item). Repeats at different times
        // (meal prep at 7am and 6pm) are intentionally kept.
        func addUnique(_ entry: Entry) {
            let title = entry.title.lowercased().trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            let timeKey = entry.time.map {
                String(Int($0.timeIntervalSinceReferenceDate / 60)) // minute bucket
            } ?? "anytime"
            let key = "\(title)@\(timeKey)"
            guard !seenKeys.contains(key) else { return }
            seenKeys.insert(key)
            entries.append(entry)
        }

        // 1. Calendar events for the day (recurrences auto-expanded).
        let eventPredicate = store.predicateForEvents(
            withStart: dayStart, end: dayEnd, calendars: nil)
        for event in store.events(matching: eventPredicate) {
            let title = event.title ?? "Event"
            addUnique(Entry(
                title: title,
                time: event.isAllDay ? nil : event.startDate,
                notes: event.location,
                source: "calendar"))
        }

        // 2. Personal routine template.
        for item in RoutineStore.load().items {
            addUnique(Entry(
                title: item.title,
                time: Self.time(item.time, on: dayStart, cal: cal),
                notes: item.notes,
                source: "routine"))
        }

        // 3. Incomplete reminders due today, excluding our own plan list.
        let planCalendar = try findOrCreatePlanList()
        let others = store.calendars(for: .reminder).filter {
            $0.calendarIdentifier != planCalendar.calendarIdentifier
        }
        let duePredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: dayStart, ending: dayEnd, calendars: others)
        let dueReminders = await fetchReminders(matching: duePredicate)
        for reminder in dueReminders {
            let due = reminder.dueDateComponents.flatMap { cal.date(from: $0) }
            addUnique(Entry(
                title: reminder.title ?? "Task",
                time: due,
                notes: reminder.notes,
                source: "reminder"))
        }

        guard !entries.isEmpty else {
            return "🗓️ Nothing found for \(Self.dayLabel(date)). Add calendar events or set a routine (--set-routine)."
        }

        // Sort: timed items chronologically, anytime items last.
        entries.sort { a, b in
            switch (a.time, b.time) {
            case let (x?, y?): return x < y
            case (nil, _?):    return false
            case (_?, nil):    return true
            case (nil, nil):   return a.title < b.title
            }
        }

        // Idempotency: clear previously generated items for this day.
        try await clearExistingPlan(in: planCalendar, dayStart: dayStart, dayEnd: dayEnd, cal: cal)

        // Create the checklist.
        let dateTag = Self.dateTag(dayStart)
        var created = 0
        for entry in entries {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = planCalendar
            reminder.title = entry.title
            reminder.notes = Self.stampNotes(entry.notes, dateTag: dateTag)
            if let time = entry.time {
                reminder.dueDateComponents = cal.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: time)
                reminder.addAlarm(EKAlarm(absoluteDate: time))
            } else {
                reminder.dueDateComponents = cal.dateComponents(
                    [.year, .month, .day], from: dayStart)
            }
            try store.save(reminder, commit: false)
            created += 1
        }
        try store.commit()

        return "🗓️ Planned \(created) item\(created == 1 ? "" : "s") for \(Self.dayLabel(date)) in \"\(Self.listTitle)\" — open Reminders to check them off."
    }

    // MARK: - Reminders list management

    private func findOrCreatePlanList() throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder)
            .first(where: { $0.title == Self.listTitle }) {
            return existing
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = Self.listTitle
        // Prefer the same (iCloud) source the user's default reminders use so
        // the new list syncs across devices.
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first { $0.sourceType == .calDAV }
            ?? store.sources.first
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func clearExistingPlan(in calendar: EKCalendar,
                                   dayStart: Date, dayEnd: Date,
                                   cal: Calendar) async throws {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let existing = await fetchReminders(matching: predicate)
        let dateTag = Self.dateTag(dayStart)
        var removedAny = false
        for reminder in existing where {
            let notes = reminder.notes ?? ""
            return notes.contains(Self.marker) && notes.contains(dateTag)
        }() {
            try store.remove(reminder, commit: false)
            removedAny = true
        }
        if removedAny { try store.commit() }
    }

    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { (cont: CheckedContinuation<[EKReminder], Never>) in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
    }

    // MARK: - Helpers

    private static func time(_ hhmm: String?, on day: Date, cal: Calendar) -> Date? {
        guard let hhmm else { return nil }
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day)
    }

    private static func stampNotes(_ notes: String?, dateTag: String) -> String {
        let base = notes?.isEmpty == false ? notes! + "\n" : ""
        return "\(base)\(marker) \(dateTag)"
    }

    private static func dateTag(_ day: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: day)
    }

    private static func dayLabel(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "EEEE, MMM d"
        return df.string(from: date)
    }
}
