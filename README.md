# Scheduled

Turn plain English into real Apple Calendar events and Reminders — with native,
cross-device alarms that sync through iCloud to your iPhone, iPad, Mac, and Apple
Watch.

Type something like:

- `gym everyday at 6am`
- `lecture tomorrow at 2pm for 2 hours`
- `remind me to pay bills on Friday at 5pm with a 30m alarm`
- `move my dentist appointment to 4pm` — edits the existing event
- `cancel gym on Friday` — deletes the existing item
- `plan my day`

…and it lands in the right place instantly.

> Built as a native macOS menu-bar app (Swift + SwiftUI/AppKit + EventKit). The
> same binary doubles as a CLI, so it also plugs into Raycast, Alfred, Shortcuts,
> or cron.

---

## Why this design

| Goal | How it's achieved |
| --- | --- |
| **Real-time iCloud sync** | Writes directly to the system EventKit store — the exact store iCloud already syncs. No custom backend, no polling. |
| **Native alarms on every device** | Uses `EKAlarm` on events/reminders, so alerts fire on iPhone/iPad/Mac/Watch. |
| **Frictionless capture** | Menu-bar icon + global hotkey **⌘⌥J** (Carbon hotkey — no Accessibility permission needed). |
| **Accurate relative dates** | Current date/time/timezone are sent to the LLM as ground truth. |
| **Reliable structured parsing** | OpenRouter call forces JSON output and is defensively decoded. |
| **Low friction install** | Command-Line-Tools-only build (no full Xcode). `make` assembles a signed `.app`. |

---

## Requirements

- macOS 14 (Sonoma) or later
- **Xcode Command Line Tools** (`xcode-select --install`) — full Xcode not required
- An **OpenRouter API key** — <https://openrouter.ai/keys>

---

## Quick start

```bash
# 1. (optional) provide your key up front so setup stores it for you
export OPENROUTER_API_KEY="sk-or-..."

# 2. build the app bundle, install a CLI shim, and launch
./setup.sh
```

`setup.sh` will:

1. verify the Swift toolchain,
2. build and ad-hoc-sign `dist/Scheduled.app`,
3. store your API key in the Keychain (if `OPENROUTER_API_KEY` is set),
4. install a `scheduled` shim into `~/.local/bin`,
5. launch the app.

Prefer `make`? See [Build targets](#build-targets).

---

## Supplying the OpenRouter API key

The key is read in this order:

1. **macOS Keychain** (service `com.scheduled.app`, account `OPENROUTER_API_KEY`)
   — set it in the app's **Settings** window, or via `setup.sh`.
2. **`OPENROUTER_API_KEY` environment variable** — handy for CLI/CI.

Nothing is ever written to the repo. Choose the model in Settings (default:
`anthropic/claude-haiku-4.5` — fast and cheap for this task).

---

## Required macOS permissions

On first use macOS will prompt for:

- **Calendar** — to create events (`NSCalendarsFullAccessUsageDescription`)
- **Reminders** — to create reminders (`NSRemindersFullAccessUsageDescription`)

Grant both. (The global hotkey uses Carbon and needs **no** Accessibility
permission.) You can review/change these later in **System Settings → Privacy &
Security → Calendars / Reminders**.

### It only asks once

macOS remembers the grant per app — it does **not** re-prompt every time. Once
you've allowed Calendar and Reminders, the app (and the `scheduled` CLI shim,
which runs the same signed bundle) just works silently afterward.

One nuance for developers: the default build is **ad-hoc signed**, and an ad-hoc
signature changes on every rebuild, so macOS may re-ask after you rebuild. To get
a permanent, rebuild-proof grant, sign with a **stable identity**:

```bash
make CODESIGN_IDENTITY="Apple Development: you@example.com (TEAMID)"
# …or a self-signed "Code Signing" certificate you create once in
# Keychain Access → Certificate Assistant → Create a Certificate.
```

For normal use — build/install once, grant once — it's already one-time.

---

## Using it

### Menu-bar app
- **Left-click** the calendar icon (or press **⌘⌥J**) to open the capture box.
- Type your request, press **↵**. Press **esc** to dismiss.
- **Right-click** the icon for the menu: *New Schedule*, *Plan My Day*,
  *Settings*, *Quit*.

### Plan My Day
Builds one tickable checklist for today in a dedicated **"Today's Plan"**
Reminders list, merging:
1. today's **calendar events** (including recurring ones like gym and that day's
   lectures/extras),
2. your **personal routine** (meal prep, journaling, …),
3. **reminders already due today** from your other lists.

Re-running replaces the day's items instead of duplicating them.

Set your routine once, in plain English:

```bash
scheduled --set-routine "gym 6am, meal prep 7am and 6pm, standup 9:30am, read 30 min at 9pm"
scheduled --show-routine
scheduled --plan-day            # or type "plan my day" in the capture box / menu
```

The routine is stored at `~/.config/scheduled/routine.json`.

### CLI
The same binary runs headless — great for Raycast/Alfred/Shortcuts/cron:

```bash
scheduled "team standup every weekday at 9:30am, alarm 5 min before"
scheduled --dry-run "dentist next Tuesday 3pm"   # parse only, print JSON, create nothing
scheduled --plan-day
scheduled --help
```

Exit codes: `0` success · `1` error · `2` missing key/usage · `3` needs clarification.

### Editing & deleting

Beyond creating, the same natural-language box can **update** or **delete**
existing events and reminders. The model infers the action from the verb:

```bash
scheduled "move my dentist appointment to 4pm"   # update time
scheduled "rename standup to team sync"          # update title
scheduled "add a 15-minute alarm to gym"         # update alarms
scheduled "cancel my dentist appointment"        # delete
scheduled "delete gym on Friday"                 # delete that occurrence
```

How it works: create / update / delete map to an `action` field, and for
update/delete the model emits a `match` (title + optional date) used to locate
the existing item by title (case-insensitive) within a date window. Notes:

- Matching is by **title**; give a distinctive keyword and a date if you have
  duplicates. Delete reports exactly what it removed.
- Update/delete act on the **single named occurrence** of a recurring series,
  not the whole series — manage series-wide changes in the Calendar app.
- `--dry-run` shows the parsed `action`/`match` and changes **nothing**, so it's
  the safe way to preview a delete.

---

## Build targets

```bash
make            # build + assemble + sign dist/Scheduled.app
make run        # build and launch the menu-bar app
make install    # copy the app into /Applications
make cli TEXT="gym at 6am"   # build, then run one request
make clean
make help
```

Run the built-in logic tests anytime:

```bash
swift build -c release && .build/release/Scheduled --selftest
```

---

## How it works

```
 natural language
        │
        ▼
 OpenRouterClient ──► OpenRouter (JSON-only, temp 0, current date/tz injected)
        │
        ▼
 IntentResponse (Codable)         Routine (~/.config/scheduled)
        │                                   │
        ▼                                   ▼
 EventKitManager  ───────────────►  DayPlanner ("Plan My Day")
        │                                   │
        ▼                                   ▼
 EKEvent / EKReminder + EKAlarm  →  system EventKit store
        │
        ▼
 iCloud → iPhone · iPad · Mac · Watch
```

Source layout (`Sources/Scheduled/`):

| File | Responsibility |
| --- | --- |
| `main.swift` | Entry point; GUI vs CLI dispatch and CLI subcommands |
| `AppDelegate.swift` | Menu bar, floating capture panel, settings window |
| `HotKey.swift` | Global ⌘⌥J via Carbon |
| `CaptureView.swift` / `SettingsView.swift` | SwiftUI UI |
| `AppState.swift` | Orchestrates parse → create; command routing |
| `OpenRouterClient.swift` | LLM calls + prompts + JSON decoding |
| `EventKitManager.swift` | Events, reminders, recurrence, alarms, auth |
| `DayPlanner.swift` | "Plan My Day" checklist builder |
| `RoutineStore.swift` | Routine template persistence |
| `Keychain.swift` | Secure API-key storage |
| `Models.swift` | Codable intent model |
| `SelfTest.swift` | Dependency-free logic tests (`--selftest`) |

---

## iOS app (App Store target)

The same Core pipeline powers a native **iOS app** (SwiftUI + App Intents). Code
is shared at the source level — no duplication:

```
Sources/Scheduled/Core/   ← shared, platform-agnostic (models, OpenRouter,
                             EventKit, DayPlanner, routine, Keychain, AppState)
Sources/Scheduled/macOS/  ← macOS-only (menu bar, global hotkey, CLI)
iOS/                      ← iOS-only (SwiftUI screens + Siri/Shortcuts intents)
```

The iOS target compiles `Core/ + iOS/` via an **XcodeGen** project generated from
[`project.yml`](project.yml):

```bash
brew install xcodegen
xcodegen generate          # creates Scheduled.xcodeproj (gitignored)
open Scheduled.xcodeproj   # build/run the "Scheduled (iOS)" scheme in Xcode
```

Highlights:
- **Capture screen** — text field + Schedule + Plan My Day, shared `AppState`.
- **Siri / Shortcuts** via App Intents: “Schedule with Scheduled — gym at 6am”,
  “Plan my day with Scheduled”. This is the iOS analog of the macOS hotkey.
- **BYO-key**: users paste their OpenRouter key in Settings (stored in Keychain).
- Deployment target **iOS 17** (for EventKit full-access APIs), iPhone + iPad.

> **Building the iOS app requires full Xcode** (the Command-Line-Tools-only setup
> used for the macOS app can't compile for iOS). CI builds it on every push; see
> below.

### Shipping to the App Store (roadmap)
1. Set `DEVELOPMENT_TEAM` in `project.yml` (your Apple Developer Team ID) and a
   unique `PRODUCT_BUNDLE_IDENTIFIER`.
2. `xcodegen generate`, then Archive in Xcode → upload to App Store Connect.
3. Add a **privacy policy** disclosing that request text is sent to OpenRouter;
   fill App Privacy “Data Used” accordingly.
4. For distributing to others without each user needing a key, front OpenRouter
   with a small **auth’d proxy** and point `OpenRouterClient` at it (keeps your
   key server-side, adds rate limiting). BYO-key works out of the box today.

## Continuous integration

`.github/workflows/ci.yml` runs on every push/PR to `main` on `macos-latest`,
with two jobs:

- **Build & Test (macOS)** — `swift build -c release`, `--selftest`, `make bundle`.
- **Build iOS app** — `brew install xcodegen`, `xcodegen generate`, then
  `xcodebuild` the `Scheduled (iOS)` scheme for the simulator (no signing).

This is where the iOS target is compile-verified end-to-end (a full Xcode is
available on the runner).

---

## Troubleshooting

- **"No endpoints found for <model>"** — the model slug is wrong/unavailable.
  Pick another in Settings (e.g. `anthropic/claude-haiku-4.5`).
- **HTTP 402 / needs more credits** — top up your OpenRouter account. The client
  already caps `max_tokens` to keep requests tiny.
- **Nothing created / access denied** — grant Calendar & Reminders in System
  Settings, then retry. TCC identifies the app by its signature, so always run
  the built `dist/Scheduled.app` (the Makefile ad-hoc-signs it).
- **Hotkey does nothing** — another app may own ⌘⌥J; quit it or rebind (see
  `HotKey.swift`).

---

## Privacy

Scheduled is **bring-your-own-key**: your OpenRouter API key is stored only in
your device's Keychain and is never sent anywhere except OpenRouter. The text of
each request is sent to OpenRouter to interpret it into an event/reminder — that
is the only data that leaves your device. Events and reminders are written to
your own Apple (EventKit/iCloud) account. No analytics, no accounts, no backend.
See [PRIVACY.md](PRIVACY.md).

## License

MIT © 2026 Malhar Falke
