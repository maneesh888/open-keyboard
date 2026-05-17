# Open Keyboard

Open Keyboard is an open-source iOS keyboard with private AI assistance, designed to work with a self-hosted LLM Gateway instead of sending typed text to third-party keyboard services.

> Status: early development. The product vision is defined, but the Xcode project and keyboard extension are still being built.

## What it will do

Open Keyboard aims to provide a normal iOS typing experience plus optional AI tools:

- Custom iOS keyboard extension for everyday typing.
- AI suggestion bar for context-aware completions.
- Rewrite actions for grammar, tone, clarity, and short/long variants.
- Configurable LLM Gateway URL and API key.
- Self-hosted/local model support through LLM Gateway and Ollama-compatible backends.
- Privacy-first defaults: no hardcoded keys, no bundled secrets, and user-controlled infrastructure.

## Why this exists

Most AI keyboards route private typing data through someone else's cloud. Open Keyboard is for people who want AI writing help while keeping control of their gateway, keys, logs, and model backend.

## Architecture

```text
iOS Host App
  - onboarding
  - settings
  - gateway URL + API key configuration
  - connection testing

Keyboard Extension
  - custom keyboard UI
  - text insertion/deletion
  - AI suggestion/actions UI
  - reads shared config from App Group

LLM Gateway
  - authenticates API keys
  - rate limits clients
  - proxies requests to Ollama/LLM backend

Ollama / LLM Backend
  - local or hosted models
```

## Current implementation status

Current repository contents are a partial SwiftUI app scaffold and planning docs. The project is not yet buildable as an iOS keyboard because the Xcode project and keyboard extension target still need to be created.

Implemented/skeleton files include:

- `OpenKeyboard/OpenKeyboardApp.swift`
- `OpenKeyboard/Views/ContentView.swift`
- `OpenKeyboard/Views/SettingsView.swift`
- `OpenKeyboard/Views/OnboardingView.swift`
- `OpenKeyboard/ViewModels/SettingsViewModel.swift`
- `OpenKeyboard/Models/AppConfig.swift`
- `OpenKeyboard/Services/NetworkManager.swift`
- `docs/AI_KEYBOARD_TODO.md`
- `docs/AI_KEYBOARD_TEST_PLAN.md`

## Roadmap

### Milestone 1 — Buildable shell

- Create `OpenKeyboard.xcodeproj`.
- Add main iOS app target.
- Add keyboard extension target.
- Configure shared App Group.
- Build and run the host app in Simulator.
- Install and enable the keyboard extension.
- Provide a minimal keyboard that can insert letters, space, return, and delete.

### Milestone 2 — Functional keyboard

- Complete QWERTY layout.
- Add shift, symbols, numbers, globe key, dark mode, and haptics.
- Improve key press animations and native iOS feel.

### Milestone 3 — Gateway configuration

- Store gateway URL and API key locally.
- Test API key against LLM Gateway.
- Share config safely between host app and keyboard extension.

### Milestone 4 — AI assistance

- Add AI suggestion bar.
- Add rewrite/fix-tone/grammar actions.
- Handle loading, rate limits, invalid keys, offline gateway, and Full Access permission states.

### Milestone 5 — Release polish

- App icon and screenshots.
- Onboarding instructions for enabling the keyboard.
- TestFlight-ready signing and build pipeline.
- Privacy documentation.

## Privacy and security notes

- API keys must never be committed.
- Production config should stay local to the user/device.
- iOS keyboard extensions require **Full Access** for network calls. Open Keyboard should explain this clearly during onboarding.
- App Group storage is planned for sharing config between the host app and keyboard extension.
- Stronger key storage options should be evaluated before production release.

## Development

Build instructions are coming once the Xcode project is created.

Planned local verification:

```bash
xcodebuild -list -project OpenKeyboard.xcodeproj
xcodebuild build \
  -project OpenKeyboard.xcodeproj \
  -scheme OpenKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Related project

Open Keyboard is designed to work with [LLM Gateway](../llm-gateway), a lightweight authenticated gateway for Ollama-compatible LLM backends.

## License

This project is released under the Unlicense. See [LICENSE](LICENSE).
