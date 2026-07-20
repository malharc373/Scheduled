import AppKit
import Foundation

// Entry point. Two modes:
//   • No text args        -> launch the menu-bar app (global hotkey ⌘⌥J).
//   • Text args provided  -> headless CLI: parse + create + print, then exit.
//     e.g.  scheduled "gym everyday at 6am"
// This makes the same binary usable from Raycast / Alfred / Shortcuts / cron.

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--help" || args.first == "-h" {
    print("""
    Scheduled — natural language → Apple Calendar/Reminders

    USAGE:
      Scheduled                      Launch the menu-bar app (hotkey ⌘⌥J)
      Scheduled "<text>"             Parse & schedule one request, then exit
      Scheduled --dry-run "<text>"   Parse only; print JSON intent, create nothing
      Scheduled --plan-day           Build today's checklist in "Today's Plan"
      Scheduled --set-routine "<t>"  Save a daily routine from natural language
      Scheduled --show-routine       Print the saved daily routine
      Scheduled --selftest           Run the built-in logic tests
      Scheduled --help               Show this help

    ENV:
      OPENROUTER_API_KEY             API key (Keychain value takes precedence)

    EXAMPLES:
      Scheduled "lecture tomorrow at 2pm for 2 hours"
      Scheduled "remind me to pay bills on Friday at 5pm with a 30m alarm"
      Scheduled "gym every weekday at 6am, alarm 15 min before"
      Scheduled "move my dentist appointment to 4pm"        # edit an existing item
      Scheduled "add a 15-minute alarm to gym"              # edit an existing item
      Scheduled "cancel my dentist appointment next Tuesday"# delete an existing item
      Scheduled --set-routine "gym 6am, meal prep 7am and 6pm, read 30 min at 9pm"
      Scheduled --plan-day
    """)
    exit(0)
}

if args.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

let dryRun = args.contains("--dry-run")
let textArgs = args.filter { !$0.hasPrefix("--") }

if args.contains("--show-routine") {
    print(RoutineStore.describe(RoutineStore.load()))
    exit(0)
}

if args.contains("--set-routine") {
    runSetRoutine(textArgs.joined(separator: " "))
}

if args.contains("--plan-day") || args.contains("--today") {
    runPlanDay()
}

if textArgs.isEmpty {
    // ---- GUI mode ----
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
} else {
    // ---- CLI mode ----
    runCLI(textArgs.joined(separator: " "))
}

/// Runs the parse→create pipeline once and exits. Blocks the main thread on a
/// semaphore while the (non-main-actor) async work completes on a background
/// executor.
func runCLI(_ text: String) -> Never {
    let semaphore = DispatchSemaphore(value: 0)
    let exitCode = ExitBox()

    Task {
        defer { semaphore.signal() }
        guard let key = Keychain.apiKey(), !key.isEmpty else {
            errPrint("Error: no API key. Set OPENROUTER_API_KEY or configure the app.")
            exitCode.value = 2
            return
        }
        let model = UserDefaults.standard.string(forKey: "model")
            ?? OpenRouterClient.defaultModel
        let client = OpenRouterClient(apiKey: key, model: model)
        do {
            let intent = try await client.parse(text)

            if dryRun {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(intent),
                   let json = String(data: data, encoding: .utf8) {
                    print(json)
                }
                return
            }

            if let clarification = intent.clarification,
               !clarification.isEmpty, intent.items.isEmpty {
                print("❓ \(clarification)")
                exitCode.value = 3
                return
            }
            let eventKit = EventKitManager()
            if intent.items.isEmpty {
                errPrint("Nothing to schedule from that input.")
                exitCode.value = 3
                return
            }
            for item in intent.items {
                let summary = try await eventKit.apply(item)
                print(summary)
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errPrint("Error: \(msg)")
            exitCode.value = 1
        }
    }

    semaphore.wait()
    exit(exitCode.value)
}

/// Builds today's checklist and exits.
func runPlanDay() -> Never {
    let semaphore = DispatchSemaphore(value: 0)
    let exitCode = ExitBox()
    Task {
        defer { semaphore.signal() }
        do {
            let summary = try await DayPlanner().planDay()
            print(summary)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errPrint("Error: \(msg)")
            exitCode.value = 1
        }
    }
    semaphore.wait()
    exit(exitCode.value)
}

/// Parses a natural-language routine description and saves it, then exits.
func runSetRoutine(_ text: String) -> Never {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
        errPrint("Usage: Scheduled --set-routine \"gym 6am, meal prep 7am and 6pm, ...\"")
        exit(2)
    }
    let semaphore = DispatchSemaphore(value: 0)
    let exitCode = ExitBox()
    Task {
        defer { semaphore.signal() }
        guard let key = Keychain.apiKey(), !key.isEmpty else {
            errPrint("Error: no API key. Set OPENROUTER_API_KEY or configure the app.")
            exitCode.value = 2
            return
        }
        let model = UserDefaults.standard.string(forKey: "model") ?? OpenRouterClient.defaultModel
        do {
            let routine = try await OpenRouterClient(apiKey: key, model: model).parseRoutine(text)
            if RoutineStore.save(routine) {
                print("Saved routine (\(routine.items.count) items):")
                print(RoutineStore.describe(routine))
            } else {
                errPrint("Error: could not write routine file.")
                exitCode.value = 1
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errPrint("Error: \(msg)")
            exitCode.value = 1
        }
    }
    semaphore.wait()
    exit(exitCode.value)
}

/// Thread-safe-enough box for the exit code shared with the detached Task.
final class ExitBox: @unchecked Sendable {
    var value: Int32 = 0
}
