# Privacy Policy — Scheduled

_Last updated: 2026-07-21_

Scheduled turns natural-language text into Apple Calendar events and Reminders.
It is designed to collect as little as possible.

## What the app sends, and where

- **Your request text** (e.g. "gym everyday at 6am") is sent to **OpenRouter**
  (`https://openrouter.ai`) so a language model can interpret it into a
  structured event/reminder. This is the only data that leaves your device, and
  it is sent only when you submit a request. Your use is subject to
  [OpenRouter's privacy policy](https://openrouter.ai/privacy).
- **Your OpenRouter API key** is stored **only in your device's Keychain** and is
  sent only to OpenRouter, as the credential for your own requests. It is never
  transmitted to the developer or any third party.

## What the app writes

- Events and Reminders are created, edited, or deleted **in your own Apple
  account** via EventKit. They sync through **your** iCloud to your other Apple
  devices. The developer has no access to them.

## What the app does NOT do

- No analytics, telemetry, tracking, or advertising identifiers.
- No developer-operated servers or backend — the app talks directly to OpenRouter
  and to Apple's on-device EventKit store.
- No account creation, and no collection of your name, email, contacts, or
  location.

## Permissions

- **Calendar** and **Reminders** access is requested so the app can create and
  manage the items you ask for. You can revoke these anytime in
  Settings → Privacy & Security.

## Data retention & deletion

- The app itself stores only your API key (Keychain) and your optional routine
  template (locally). Deleting the app removes both. Request text is not retained
  by the app after processing; any retention on OpenRouter's side is governed by
  their policy.

## Contact

Questions: open an issue at <https://github.com/malharc373/Scheduled>.
