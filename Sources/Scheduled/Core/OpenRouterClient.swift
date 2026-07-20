import Foundation

/// Errors surfaced from the OpenRouter round-trip.
enum OpenRouterError: LocalizedError {
    case missingKey
    case http(Int, String)
    case emptyResponse
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No OpenRouter API key. Set it in Settings or export OPENROUTER_API_KEY."
        case .http(let code, let body):
            return "OpenRouter HTTP \(code): \(body)"
        case .emptyResponse:
            return "OpenRouter returned an empty response."
        case .decode(let detail):
            return "Could not parse the model's JSON: \(detail)"
        }
    }
}

/// Talks to the OpenRouter chat-completions endpoint and returns a decoded
/// `IntentResponse`. The current date/time/timezone are injected so the model
/// can resolve relative expressions ("tomorrow", "in 2 hours", "next Monday").
struct OpenRouterClient {
    static let defaultModel = "anthropic/claude-haiku-4.5"

    let apiKey: String
    let model: String

    private let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func parse(_ text: String, now: Date = Date()) async throws -> IntentResponse {
        guard !apiKey.isEmpty else { throw OpenRouterError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Optional attribution headers recommended by OpenRouter.
        request.setValue("https://github.com/scheduled-app/scheduled",
                         forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Scheduled", forHTTPHeaderField: "X-Title")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            // The structured payload is small; cap output to stay fast & cheap.
            "max_tokens": 1500,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.systemPrompt(now: now)],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenRouterError.http(http.statusCode, bodyText)
        }

        let content = try extractContent(from: data)
        let json = Self.stripCodeFences(content)
        guard let jsonData = json.data(using: .utf8) else {
            throw OpenRouterError.decode("content was not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(IntentResponse.self, from: jsonData)
        } catch {
            throw OpenRouterError.decode("\(error.localizedDescription) — raw: \(json)")
        }
    }

    /// Parses a free-text description of a daily routine into structured items.
    func parseRoutine(_ text: String) async throws -> Routine {
        guard !apiKey.isEmpty else { throw OpenRouterError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Scheduled", forHTTPHeaderField: "X-Title")

        let system = """
        Convert the user's description of their daily routine into strict JSON:
        {"items":[{"title":"string","time":"HH:mm" or null,"notes":"string or null"}]}
        - "time" is a 24-hour local clock time ("6am" => "06:00", "6pm" => "18:00").
        - Use null time for anytime/untimed habits.
        - If a habit happens multiple times a day (e.g. meal prep morning and
          evening), emit one item per occurrence with distinct titles.
        - JSON only, no commentary, no markdown.
        """
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_tokens": 1500,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenRouterError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let content = try extractContent(from: data)
        let json = Self.stripCodeFences(content)
        guard let jsonData = json.data(using: .utf8) else {
            throw OpenRouterError.decode("content was not valid UTF-8")
        }
        do {
            return try JSONDecoder().decode(Routine.self, from: jsonData)
        } catch {
            throw OpenRouterError.decode("\(error.localizedDescription) — raw: \(json)")
        }
    }

    // MARK: - Response unwrapping

    private struct ChatCompletion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    private func extractContent(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(ChatCompletion.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.emptyResponse
        }
        return content
    }

    /// Some models wrap JSON in ```json fences despite response_format.
    static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            // Drop first fence line and trailing fence.
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            }
            if let lastFence = t.range(of: "```", options: .backwards) {
                t = String(t[..<lastFence.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt

    static func systemPrompt(now: Date) -> String {
        let tz = TimeZone.current
        let iso = ISO8601DateFormatter()
        iso.timeZone = tz
        iso.formatOptions = [.withInternetDateTime]

        let readable = DateFormatter()
        readable.timeZone = tz
        readable.locale = Locale(identifier: "en_US")
        readable.dateFormat = "EEEE, yyyy-MM-dd HH:mm"

        let nowISO = iso.string(from: now)
        let nowReadable = readable.string(from: now)
        let tzName = tz.identifier
        let offsetMinutes = tz.secondsFromGMT(for: now) / 60

        return """
        You convert a user's natural-language scheduling request into strict JSON.

        GROUND TRUTH (use this as "now"):
        - Current local date/time: \(nowReadable) (\(nowISO))
        - Timezone: \(tzName) (UTC offset \(offsetMinutes) minutes)
        Resolve ALL relative expressions ("today", "tomorrow", "tonight",
        "next Monday", "in 2 hours", "this weekend") against this ground truth.

        Return ONLY a JSON object with this exact shape:
        {
          "items": [
            {
              "kind": "event" | "reminder",
              "title": "string",
              "notes": "string or null",
              "location": "string or null",
              "start": "yyyy-MM-ddTHH:mm:ss" | "yyyy-MM-dd" | null,
              "end": "yyyy-MM-ddTHH:mm:ss" | null,
              "all_day": true | false,
              "recurrence": {
                "frequency": "daily" | "weekly" | "monthly" | "yearly",
                "interval": 1,
                "days_of_week": ["MO","TU","WE","TH","FR","SA","SU"] | null,
                "count": null,
                "until": "yyyy-MM-dd" | null
              } | null,
              "alarms_minutes_before": [30, 0]
            }
          ],
          "clarification": "string or null"
        }

        RULES:
        - Output LOCAL wall-clock times with NO timezone suffix (no "Z", no offset).
        - Choose "event" for time-blocked activities (meetings, gym, lectures,
          appointments). Choose "reminder" for tasks/todos ("pay bills",
          "call mom", "buy milk").
        - If a duration is given ("for 2 hours"), set "end" accordingly.
          If an event has a start but no duration, leave "end" null (a default
          length will be applied).
        - "all_day" is true only when no specific time is given for an event.
        - alarms_minutes_before: 0 means "at the time of the event". "30m alarm"
          or "remind me 15 minutes before" => include that offset. If the user
          asks for an alarm/reminder but gives no offset, use [0]. If no alarm is
          requested, use [] for events and [0] for reminders (a reminder should
          alert at its due time).
        - Recurrence: "everyday"/"daily" => daily. "every Monday"/"weekly" =>
          weekly with days_of_week. "weekdays" => weekly with
          ["MO","TU","WE","TH","FR"]. "monthly" => monthly. Omit (null) for
          one-off items.
        - Split a request that clearly contains multiple distinct items into
          multiple entries in "items".
        - Only set "clarification" (and leave items empty) when the request is
          too ambiguous to schedule at all. Otherwise make a sensible best guess
          and keep clarification null.
        - Never include commentary or markdown — JSON only.
        """
    }
}
