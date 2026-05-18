# AI Keyboard Project - TODO List

**Last Updated:** 2026-04-20 18:51 UTC

---

## ✅ **COMPLETED**

### Phase 1: Gateway (100%)
- [x] Admin Authentication (bcrypt + JWT)
- [x] API Key CRUD operations
- [x] Per-Client Configuration
- [x] Token Bucket Rate Limiting
- [x] Comprehensive Unit Tests (59/59 passing)
- [x] Security Enhancements
- [x] Documentation
- [x] **Admin Web UI** (just completed!)

### Infrastructure
- [x] SSH Remote Execution (Docker → Mac)
- [x] Restricted command whitelist
- [x] Test execution from container
- [x] Gateway runs at http://localhost:8080

---

## 📋 **TODO - Phase 2: iOS Main App**

### Project Setup
- [ ] Decide project name
- [ ] Check bundle identifier availability on App Store
- [ ] Choose license (Apache 2.0, MIT, GPL?)
- [ ] Create Xcode project structure
  - [ ] Main app target
  - [ ] Keyboard extension target
  - [ ] Configure App Groups
  - [ ] Set up signing & capabilities

### Main App UI
- [ ] Settings screen
  - [ ] API key input field (secure text entry)
  - [ ] Save to App Group storage
  - [ ] Test connection button
  - [ ] Server status indicator
- [ ] Onboarding flow
  - [ ] Welcome screen
  - [ ] Step-by-step keyboard setup instructions
  - [ ] Screenshots for "Enable Full Access"
  - [ ] Completion checklist
- [ ] "Open Keyboard Settings" button with deep link
- [ ] App icon design

### Code
- [ ] Create ContentView.swift (main UI)
- [ ] Create SettingsView.swift
- [ ] Create OnboardingView.swift
- [ ] Implement App Group data sharing
- [ ] Network manager for testing gateway connection
- [ ] UserDefaults wrapper for API key storage

### Testing
- [ ] Unit tests for settings logic
- [ ] UI tests for onboarding flow
- [ ] Integration with local-ci.sh
- [ ] Manual testing on Simulator
- [ ] Manual testing on physical device

### Documentation
- [ ] README.md for iOS project
- [ ] Setup instructions
- [ ] Screenshots
- [ ] Troubleshooting guide

**Estimated Time:** 1-2 days

---

## 📋 **TODO - Phase 3: Keyboard Extension - Core**

### Project Structure
- [ ] Create keyboard extension target
- [ ] KeyboardViewController.swift (UIKit)
- [ ] SwiftUI views for keyboard UI
- [ ] ViewModel (ObservableObject)
- [ ] Repository pattern for data

### QWERTY Keyboard Layout
- [ ] Letter keys (a-z, A-Z)
- [ ] Number row (0-9)
- [ ] Symbol keys (!, @, #, etc.)
- [ ] Special keys:
  - [ ] Shift key (capitalization)
  - [ ] Delete/backspace
  - [ ] Return/enter
  - [ ] Space bar
  - [ ] Globe (keyboard switcher)
  - [ ] Emoji picker
- [ ] Key rendering (iOS-style rounded rectangles)
- [ ] Touch handling & gestures
- [ ] Haptic feedback
- [ ] Dark mode support
- [ ] Auto-capitalization
- [ ] Key press animations

### Text Input Integration
- [ ] Connect to textDocumentProxy
- [ ] Insert characters
- [ ] Delete characters
- [ ] Handle return key
- [ ] Handle special keys
- [ ] Cursor movement (if possible)

### Testing
- [ ] Unit tests for keyboard logic
- [ ] UI tests for key presses
- [ ] Test on different text fields
- [ ] Test in different apps (Notes, Messages, etc.)

**Estimated Time:** 3-4 days

---

## 📋 **TODO - Phase 4: AI Suggestion Bar**

### UI Components
- [ ] Top suggestion bar above keyboard
- [ ] Horizontal scroll for suggestions
- [ ] Suggestion chips/buttons
- [ ] Tap to insert suggestion
- [ ] Loading indicator

### AI Integration
- [ ] NetworkManager for gateway API calls
- [ ] Load API key from App Group
- [ ] POST to /v1/completions endpoint
- [ ] Handle streaming responses (SSE)
- [ ] Debouncing (wait 500ms after typing)
- [ ] Cancel in-flight requests

### Features
- [ ] Real-time suggestions as user types
- [ ] Context-aware completions
- [ ] Show 3-5 suggestions at a time
- [ ] Smooth animations

### Error Handling
- [ ] No internet connection UI
- [ ] Invalid API key message
- [ ] Rate limit exceeded (with retry timer)
- [ ] Server down fallback
- [ ] Full Access permission check

### Testing
- [ ] Unit tests for network layer
- [ ] Mock API responses
- [ ] Test with real gateway
- [ ] Performance testing (response time)

**Estimated Time:** 2-3 days

---

## 📋 **TODO - Phase 5: AI Interaction Mode**

### UI
- [ ] ✨ Sparkle button in toolbar
- [ ] Toggle to AI mode view
- [ ] Back button to return to typing mode
- [ ] Vertical list of AI actions
- [ ] Icons for each action
- [ ] Loading states during AI processing

### AI Actions
- [ ] Continue Writing
- [ ] Rewrite
- [ ] Fix Grammar & Spelling
- [ ] Summarize
- [ ] Translate
- [ ] Custom actions (from server config)

### Functionality
- [ ] Read current text from textDocumentProxy
- [ ] Send text + action to gateway
- [ ] Stream response
- [ ] Replace text or append to cursor
- [ ] Show progress indicator
- [ ] Cancel ongoing requests

### Server Integration
- [ ] Fetch custom actions from gateway (per API key)
- [ ] Dynamic action list based on client config
- [ ] Handle different prompt templates

### Testing
- [ ] Test each AI action
- [ ] Test with different text lengths
- [ ] Test cancellation
- [ ] Test error scenarios

**Estimated Time:** 2-3 days

---

## 📋 **TODO - Phase 6: Polish & Optimization**

### Performance
- [ ] Optimize keyboard rendering
- [ ] Reduce API payload size
- [ ] Cache suggestions (30 seconds)
- [ ] Measure response times
- [ ] Memory usage optimization (Apple's 50MB limit)
- [ ] Reduce app size

### UX Improvements
- [ ] Keyboard sound effects (optional)
- [ ] Better animations
- [ ] Smooth transitions between modes
- [ ] Keyboard height adjustments
- [ ] Landscape mode support
- [ ] iPad support

### Accessibility
- [ ] VoiceOver support
- [ ] Dynamic Type (text size)
- [ ] High Contrast mode
- [ ] Reduce Motion support

### Error Handling
- [ ] Comprehensive error messages
- [ ] Retry mechanisms
- [ ] Offline mode (graceful degradation)
- [ ] Logging for debugging

### Testing
- [ ] Full regression suite
- [ ] Performance profiling (Instruments)
- [ ] Battery usage testing
- [ ] Network efficiency
- [ ] Test on iOS 16, 17, 18

**Estimated Time:** 2-3 days

---

## 📋 **TODO - Phase 7: Documentation & Release Prep**

### Documentation
- [ ] Complete README.md
- [ ] Architecture documentation
- [ ] API integration guide
- [ ] Gateway setup guide
- [ ] iOS build instructions
- [ ] Deployment guide
- [ ] Contributing guidelines
- [ ] Code of conduct
- [ ] License file

### Media
- [ ] App screenshots
- [ ] Demo video/GIF
- [ ] App Store screenshots (if publishing)
- [ ] Marketing materials

### Open Source Prep
- [ ] Clean up code comments
- [ ] Remove hardcoded secrets
- [ ] Example configurations
- [ ] GitHub repository setup
- [ ] Issue templates
- [ ] PR templates
- [ ] CI/CD workflows (GitHub Actions)

### Testing
- [ ] Final QA pass
- [ ] Test on multiple devices
- [ ] Beta testing (TestFlight if applicable)
- [ ] Security audit
- [ ] Privacy review

**Estimated Time:** 1-2 days

---

## 📋 **TODO - Future Enhancements (Optional)**

### Gateway
- [ ] Usage analytics dashboard
- [ ] API key rotation
- [ ] Webhooks for events
- [ ] Multiple LLM provider support (OpenAI, Anthropic, etc.)
- [ ] Caching layer (Redis)
- [ ] Rate limit tiers (free/pro)

### iOS Keyboard
- [ ] Swipe typing
- [ ] Word predictions
- [ ] Autocorrect
- [ ] Custom themes
- [ ] Multilingual support
- [ ] Voice input
- [ ] GIF/sticker support
- [ ] Cloud sync for settings

### Infrastructure
- [ ] Android keyboard (separate project)
- [ ] Desktop extension (Chrome/Firefox)
- [ ] Subscription/monetization (if applicable)

---

## 🎯 **Current Priority: Phase 2 (iOS Main App)**

**Next Steps:**
1. Decide project name & bundle ID
2. Create Xcode project
3. Build settings screen
4. Implement onboarding
5. Test on Simulator

---

## 📊 **Overall Progress**

- **Phase 1 (Gateway):** ✅ 100% Complete
- **Phase 2 (iOS Main App):** ⏳ 0% (Not Started)
- **Phase 3 (Keyboard Core):** ⏳ 0% (Not Started)
- **Phase 4 (AI Suggestions):** ⏳ 0% (Not Started)
- **Phase 5 (AI Mode):** ⏳ 0% (Not Started)
- **Phase 6 (Polish):** ⏳ 0% (Not Started)
- **Phase 7 (Docs):** ⏳ 0% (Not Started)

**Total Project:** ~15-20% Complete

---

## 🔥 **Tonight's Work Plan**

**Option A:** Start Phase 2 (iOS project setup + main app)
**Option B:** Add more gateway features (analytics, etc.)
**Option C:** Prepare documentation for what's completed

**Decision needed from Maneesh!**

---

**Last Updated:** 2026-04-20 18:51 UTC by Coder Bot

---

## Product/Architecture Decisions Added 2026-05-18

### Product Target
- [ ] Target a Grammarly-level or better AI writing assistant, not just a basic AI keyboard.
- [ ] Pair Open Keyboard with LLM Gateway as the required backend for auth, rate limits, model routing, and LLM access.
- [ ] Keep the public positioning privacy-first: user-owned gateway, keys, logs, and model backend.

### Backend Pairing UX
- [ ] Configure backend in the main Open Keyboard app, not inside the keyboard UI.
- [ ] Settings/onboarding should collect:
  - [ ] LLM Gateway URL
  - [ ] API key
  - [ ] Connection status
  - [ ] Full Access/network permission guidance
- [ ] Add a "Test Connection" flow:
  - [ ] Check gateway health.
  - [ ] Validate API key with an authenticated lightweight request or chat/completion test.
  - [ ] Show safe errors: invalid key, gateway offline, rate limited, Full Access required.
- [ ] Store gateway URL/API key in shared App Group config so the keyboard extension can read it.
- [ ] Keyboard extension should consume saved pairing and call:
  - [ ] `POST {gatewayURL}/v1/chat/completions`
  - [ ] `Authorization: Bearer {apiKey}`

### UI/Implementation Constraints
- [ ] Use SwiftUI for Open Keyboard UI.
- [ ] Use SwiftUI for keyboard views/components.
- [ ] Avoid UIKit UI implementation.
- [ ] If iOS requires `UIInputViewController` for the keyboard extension lifecycle, keep it as a minimal hosting bridge only; product UI should remain SwiftUI.
- [ ] Reference Allora Keyboard only for behavioral/UX inspiration where useful; do not copy code blindly and do not treat it as our project.

### Grammarly-Class Feature Roadmap
- [ ] Grammar and spelling fixes.
- [ ] Clarity improvements.
- [ ] Tone transforms: professional, friendly, concise, assertive, polished.
- [ ] Rewrite variants: shorter, longer, simpler, more formal.
- [ ] Smart replies for messages/email.
- [ ] Summarize selected/recent text where iOS context allows.
- [ ] Context-aware autocomplete/suggestion bar.
- [ ] Preview before replacing long text; avoid destructive auto-replace.
- [ ] Fast, cancellable LLM calls with graceful fallback UI.

### Keyboard UI Reference: Grammarly Keyboard
- [ ] Use Grammarly keyboard screenshot as UX reference for first visual target.
- [ ] Dark keyboard surface with rounded top container.
- [ ] Top assistant/suggestion row:
  - [ ] Left brand/logo button.
  - [ ] 3 predictive suggestions separated by vertical dividers.
  - [ ] Right AI assistant/action button.
- [ ] QWERTY layout with large rounded dark-gray keys and white labels.
- [ ] Rows:
  - [ ] QWERTY row.
  - [ ] ASDF row with horizontal inset.
  - [ ] Shift + ZXCV row + backspace.
  - [ ] 123 + emoji + wide space + return.
  - [ ] Bottom utility row with globe/next keyboard and microphone.
- [ ] Support dark mode first; add light mode later.
- [ ] Keep UI SwiftUI-first; any `UIInputViewController` should only host SwiftUI.
- [ ] Avoid exact Grammarly branding/copying; use it as layout/quality benchmark only.
- [ ] Suggestion row must support inline correction cards, not only plain word predictions:
  - [ ] Correction card shows action label such as "Correct spelling".
  - [ ] Correction card shows replacement text with accent color.
  - [ ] Logo badge can indicate number of issues/actions available.
  - [ ] Remaining row slots can still show predictive words/quoted replacements.
  - [ ] Tapping correction card should preview/apply fix safely depending on text length.
- [ ] Use standard iOS keyboard colors/materials for light/dark mode instead of hardcoding Grammarly screenshot colors.
- [ ] Top-left icon opens an in-keyboard AI/issues UI panel.
- [ ] Top-right assistant icon opens the main AI interaction UI inside the keyboard.
- [ ] Treat these icon-triggered panels as primary AI interaction surfaces; Maneesh will provide more UI references after basic setup is complete.
- [ ] Basic setup milestone should prioritize project/buildability and shell keyboard first; detailed AI panels come after.

---

## POC Architecture Decisions Added 2026-05-18

### Profiles and Gateway Configuration
- [ ] Treat Open Keyboard profiles as user-friendly saved connections to LLM Gateway API keys.
- [ ] Backend/Gateway key configuration owns AI behavior:
  - [ ] model routing: Private local vs Ollama Cloud
  - [ ] temperature
  - [ ] max tokens
  - [ ] rate limits
  - [ ] enabled features/actions
  - [ ] base system behavior/prompt
  - [ ] key enabled/disabled state
- [ ] Open Keyboard client owns UX intent only:
  - [ ] selected profile/key
  - [ ] action type such as fix grammar, rewrite, shorten, reply
  - [ ] selected/current text and nearby context
  - [ ] optional user tone/intention when explicitly chosen
  - [ ] preview vs replace behavior
- [ ] Do not fully configure model/temp/system prompts client-side for POC.
- [ ] POC should start with one default profile in the UI, but storage should support multiple profiles.
- [ ] Later add profile switching in the keyboard UI.

### Server-Driven Configuration, Native UI
- [ ] Use server-driven configuration/capabilities, not server-driven layout.
- [ ] Gateway should eventually expose a safe metadata endpoint, e.g. `GET /v1/profile` or `GET /v1/capabilities`, authenticated by API key.
- [ ] Endpoint should return safe profile metadata only, such as:
  - [ ] profile name/label
  - [ ] model label: Private or Ollama Cloud
  - [ ] enabled actions
  - [ ] default tone
  - [ ] capabilities such as rewrite/suggestions/streaming
  - [ ] limits useful for UX
- [ ] Open Keyboard should render all UI with native SwiftUI components.
- [ ] Gateway decides what is available; Open Keyboard decides how it looks.

### POC Request Flow
- [ ] User pairs Open Keyboard with Gateway URL + API key.
- [ ] App stores profile in App Group storage.
- [ ] Keyboard extension reads selected profile.
- [ ] Keyboard sends action + text/context to Gateway using the selected profile key.
- [ ] Gateway applies key-level model/temp/system behavior.
- [ ] Gateway returns improved text/suggestions.
- [ ] Keyboard previews result before replacing longer text.
