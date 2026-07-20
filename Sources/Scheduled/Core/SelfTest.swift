import Foundation

/// Lightweight, dependency-free test suite exercised via `Scheduled --selftest`.
/// Covers the pure logic (no network, no EventKit permissions) so it can run
/// locally and in CI without Xcode/XCTest. Returns true if all checks pass.
enum SelfTest {
    private static var failures: [String] = []

    static func run() -> Bool {
        failures = []

        codeFenceStripping()
        dateParsing()
        intentDecoding()
        actionDecoding()

        if failures.isEmpty {
            print("✅ selftest: all checks passed")
            return true
        }
        for f in failures { errPrint("❌ \(f)") }
        errPrint("selftest: \(failures.count) failure(s)")
        return false
    }

    // MARK: - Checks

    private static func codeFenceStripping() {
        expectEqual(
            OpenRouterClient.stripCodeFences("```json\n{\"items\": []}\n```"),
            "{\"items\": []}", "strips ```json fence")
        expectEqual(
            OpenRouterClient.stripCodeFences("```\n{\"a\":1}\n```"),
            "{\"a\":1}", "strips bare fence")
        expectEqual(
            OpenRouterClient.stripCodeFences("{\"items\": []}"),
            "{\"items\": []}", "leaves plain JSON untouched")
    }

    private static func dateParsing() {
        guard let dt = DateParsing.parse("2026-07-22T14:00:00") else {
            fail("parse datetime-with-seconds returned nil"); return
        }
        expect(!dt.dateOnly, "datetime is not date-only")
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dt.date)
        expectEqual(c.year, 2026, "year")
        expectEqual(c.month, 7, "month")
        expectEqual(c.day, 22, "day")
        expectEqual(c.hour, 14, "hour")
        expectEqual(c.minute, 0, "minute")

        expect(DateParsing.parse("2026-07-22T14:00") != nil, "parses datetime without seconds")

        if let dOnly = DateParsing.parse("2026-07-22") {
            expect(dOnly.dateOnly, "date-only flagged all-day")
        } else {
            fail("date-only parse returned nil")
        }

        expect(DateParsing.parse("not a date") == nil, "rejects garbage")
        expect(DateParsing.parse("") == nil, "rejects empty")
    }

    private static func intentDecoding() {
        let json = """
        {
          "items": [{
            "kind": "reminder",
            "title": "pay bills",
            "start": "2026-07-24T17:00:00",
            "all_day": false,
            "recurrence": {"frequency": "weekly", "interval": 1, "days_of_week": ["FR"]},
            "alarms_minutes_before": [30, 0]
          }],
          "clarification": null
        }
        """
        do {
            let intent = try JSONDecoder().decode(IntentResponse.self, from: Data(json.utf8))
            expectEqual(intent.items.count, 1, "one item decoded")
            let item = intent.items[0]
            expectEqual(item.kind, .reminder, "kind == reminder")
            expectEqual(item.title ?? "", "pay bills", "title")
            expectEqual(item.recurrence?.frequency, .weekly, "weekly recurrence")
            expectEqual(item.recurrence?.daysOfWeek ?? [], ["FR"], "days_of_week")
            expectEqual(item.alarmsMinutesBefore ?? [], [30, 0], "alarm offsets")
        } catch {
            fail("intent decode threw: \(error)")
        }
    }

    private static func actionDecoding() {
        // Omitted action must default to .create.
        let createJSON = """
        {"items":[{"kind":"event","title":"gym","start":"2026-07-22T06:00:00"}],
         "clarification":null}
        """
        do {
            let intent = try JSONDecoder().decode(IntentResponse.self, from: Data(createJSON.utf8))
            expectEqual(intent.items.first?.resolvedAction, .create, "missing action defaults to create")
        } catch {
            fail("create-default decode threw: \(error)")
        }

        // Delete with a match block.
        let deleteJSON = """
        {"items":[{"kind":"event","action":"delete","title":"Dentist",
                   "match":{"title":"Dentist","date":"2026-07-28"}}],
         "clarification":null}
        """
        do {
            let intent = try JSONDecoder().decode(IntentResponse.self, from: Data(deleteJSON.utf8))
            let item = intent.items.first
            expectEqual(item?.resolvedAction, .delete, "action == delete")
            expectEqual(item?.match?.title, "Dentist", "match title")
            expectEqual(item?.match?.date, "2026-07-28", "match date")
        } catch {
            fail("delete decode threw: \(error)")
        }
    }

    // MARK: - Tiny assertion helpers

    private static func expect(_ cond: Bool, _ label: String) {
        if !cond { fail(label) }
    }

    private static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ label: String) {
        if a != b { fail("\(label): \(a) != \(b)") }
    }

    private static func fail(_ label: String) {
        failures.append(label)
    }
}
