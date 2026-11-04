# Diana

A native macOS reminder app with an animated desktop companion, voice scheduling,
and optional local chat through Ollama.

## Build and run

Requires macOS 15 or later and Xcode 16 or later. There are no external Swift
package dependencies.

```sh
scripts/build.sh
open build/Diana.app
```

The build script creates a signed local app. To retain microphone and speech
permissions across rebuilds, set `DIANA_SIGN_IDENTITY` to an Apple Development
identity, or put the identity in `.Codex/signing-identity`. That local directory is
ignored by Git. Without an identity, the script uses ad-hoc signing. Public
distribution requires distribution signing and notarization.

## Reminders

Create, edit, pause, complete, or snooze reminders from Today and Schedule. Repeat
rules include daily, weekdays, weekly, and intervals within active hours. Lead
times range from zero to sixty minutes.

Diana appears when a reminder is due, runs across the desktop, and presents its
message. After completion, snooze, dismissal, or an automatic timeout, she blows
a kiss and leaves. A timeout leaves the task pending. Simultaneous reminders
share a visit.

Reminders at the same scheduled minute show a conflict warning. Choose a new
time or explicitly select **Save anyway**. This includes recurring occurrences
on the selected date, excludes paused and finished occurrences, and checks again
before saving. Meeting durations are not stored, so conflict detection compares
start times.

Closing the main window keeps the app running in the menu bar. Keep Diana running
for continuous scheduling. macOS banners require notification permission and
remain subject to Focus and sleep settings. Quiet hours suppress reminder nudges.

## Voice control

Enable **Settings → Listen for Hey Diana**, then allow microphone and speech
recognition access.

1. Say **“Hey Diana.”** Diana appears and asks, **“Yep, how can I help you?”**
2. Say **“Schedule a meeting with my client tomorrow at 5 PM.”**
3. Wait for the read-back, then say **“Yes, save it”**, **“Change it to 6 PM”**, or
   **“Cancel.”** If there is a conflict, say a different time or **“Save anyway.”**

A draft is saved only after explicit confirmation. Ambiguous times prompt a
clarification. An unclear response, cancellation, or listening timeout saves
nothing. Supported one-time requests include today, tomorrow, weekdays, AM/PM
times, and relative times such as “in twenty minutes.” An omitted day uses the
next future occurrence, which is read back before confirmation.

Say **“Bye”** or **“Bye Diana”** while she is listening to discard an unconfirmed
draft and dismiss the visit. Wake-word listening resumes afterward. Recognition
pauses while Diana speaks to avoid processing her own voice.

The microphone stays active while wake listening is enabled, so macOS shows its
orange microphone indicator. Turning off **Listen for Hey Diana** releases it.
You can still start a single conversation using **Talk to Diana** in Settings or
the menu bar, or **Command–Shift–T** while Diana is the active app. A listening
turn times out after 25 seconds without a reply. **End conversation** discards
an unconfirmed draft; wake listening resumes if enabled. English recognition
runs on-device when supported; otherwise Apple may process audio online. Audio
is not sent to Ollama. Voice requests create reminders in Diana, not calendar
invitations.

## Customization and local chat

Companion provides a 3D animation gallery, character name, size, opacity, motion
speed, entrance side, click-through behavior, and Spaces controls. Settings
provides appearance, accent colors, speech voice and speed, quiet hours, and
optional launch at login. Reduce Motion disables travel and gestures.

Enable **Companion → Use local AI with Ollama** to connect to the Ollama service
at `127.0.0.1:11434`. Choose an installed model; the app does not download models
or require an API key. Chat is held in memory for the current session and does
not change schedules. Optional personalized reminders send the title to the
local model without delaying the original reminder. Ollama can be stopped
without affecting scheduling.

Spoken output uses installed Mac voices, preferring enhanced or premium voices
when available. Generated replies and speech are stripped of emojis and common
stage directions. Additional voices can be downloaded through macOS Read & Speak
settings. Facial lip-sync is not implemented.

## Storage and privacy

Reminders and preferences are stored in
`~/Library/Application Support/Diana/reminders.json`. Writes are atomic. An
unreadable file is preserved. Settings provides backup export and reminder import;
imports merge new reminder IDs without replacing existing schedules.

Local data, signing identities, credentials, recordings, logs, agent files,
original Blender files, and build products are excluded from Git. The repository
contains the six USDZ assets needed to build the app.

## Development

```sh
swift test
scripts/build.sh debug
xcrun swift-format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift
```

- `Sources/DianaApp/`: SwiftUI views, desktop panel, rendering, speech, and notifications.
- `Sources/DianaCore/`: models, recurrence, persistence, conflict detection, voice parsing, and Ollama client.
- `Tests/DianaCoreTests/`: unit tests for scheduling, persistence, speech text, conflicts, and confirmation rules.
- `Tests/DianaAppTests/`: wake listening and microphone lifecycle tests using simulated input.
- `Config/`: application metadata and icon.
- `scripts/`: app packaging and icon generation.
- `Sources/DianaApp/Resources/Models/`: runtime character animations.

Use four-space indentation and the committed `.swift-format` configuration.
See [asset documentation](assets/diana/README.md) for clip details.

## Contributing

Contributions are welcome. Fork the repository, make your change, and open a pull request. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Diana is source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE). You may use, fork, modify, and share it for noncommercial purposes. Selling it, or using it or any derivative for commercial purposes, is not permitted. This is not an OSI-approved open-source license.
