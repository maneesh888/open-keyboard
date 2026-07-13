# AI Keyboard - Test Plan

**Version:** 1.0  
**Date:** 2026-04-20  
**Approach:** Test-Driven Development (TDD)  

---

## 🎯 Testing Philosophy

**TDD is MANDATORY** for all code:
1. **RED** - Write failing test first
2. **GREEN** - Write minimal code to pass
3. **REFACTOR** - Clean up

**Coverage Target:** 80%+ for core logic  
**Manual Testing:** Required for UI/UX flows  

---

## 📱 iOS Testing Strategy

### 1. Unit Tests (Phase 3-6)

#### KeyboardViewModel Tests
```swift
// Tests/KeyboardViewModelTests.swift

testInit_SetsDefaultState()
testKeyTap_InsertsCharacter()
testDeleteKey_RemovesCharacter()
testShiftKey_TogglesCapitalization()
testAPIKeyLoaded_FromAppGroup()
testAPIKeyMissing_ShowsError()
```

#### NetworkManager Tests
```swift
// Tests/NetworkManagerTests.swift

testFetchSuggestions_ValidAPIKey_ReturnsResults()
testFetchSuggestions_InvalidAPIKey_Returns401()
testFetchSuggestions_RateLimited_Returns429()
testFetchSuggestions_NoNetwork_ReturnsError()
testStreamingResponse_ParsesSSECorrectly()
testCancelRequest_StopsInFlightCall()
```

#### KeyboardRepository Tests
```swift
// Tests/KeyboardRepositoryTests.swift

testGetSuggestions_CallsNetworkManager()
testGetSuggestions_CachesResults()
testGetSuggestions_CacheExpiry_RefetchesAfter30Seconds()
testExecuteAction_SendsCorrectPrompt()
testExecuteAction_ReplacesText()
```

#### TextProxyManager Tests
```swift
// Tests/TextProxyManagerTests.swift

testInsertText_AppendsToProxy()
testDeleteText_RemovesFromProxy()
testGetContextBeforeCursor_ReturnsCorrectText()
testGetContextAfterCursor_ReturnsCorrectText()
testReplaceAllText_ClearsAndInsertsNew()
```

**Test Tools:**
- XCTest framework
- Mock URLSession for network tests
- Mock UITextDocumentProxy for text manipulation

**Run Command:**
```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
./scripts/ios/test.sh core
./scripts/ios/test.sh ui
```

---

### 2. Integration Tests (Phase 4-6)

#### Full Flow Tests
```swift
// Tests/Integration/KeyboardFlowTests.swift

testTypingFlow_CharactersAppear()
testAISuggestionFlow_FetchAndDisplay()
testAIActionFlow_ExecuteAndReplaceText()
testModeSwitch_TypingToAI_PreservesState()
testFullAccessDisabled_ShowsPermissionPrompt()
```

#### App Group Sharing Tests
```swift
// Tests/Integration/AppGroupTests.swift

testAPIKeySavedInMainApp_AvailableInExtension()
testUsageStatsSavedInExtension_AvailableInMainApp()
testConfigChangedInMainApp_ReflectsInExtension()
```

**Run Command:**
```bash
./ios/test-integration.sh
```

---

### 3. UI Tests (Phase 6)

#### Manual Test Scenarios

**Onboarding Flow:**
- [ ] App launches, shows welcome screen
- [ ] Enter API key, tap "Save"
- [ ] Tap "Open Keyboard Settings"
- [ ] iOS Settings opens to Keyboard page
- [ ] Enable AlLoRa keyboard
- [ ] Enable "Allow Full Access"
- [ ] Return to app, see success checkmark

**Typing Mode:**
- [ ] Open Notes app
- [ ] Switch to AlLoRa keyboard (globe icon)
- [ ] Type "hello world"
- [ ] Characters appear correctly
- [ ] Shift key capitalizes letters
- [ ] Delete key removes characters
- [ ] Return key adds newline
- [ ] Space bar adds space

**AI Suggestion Bar:**
- [ ] Type "The weather is"
- [ ] Wait 500ms, see suggestions appear
- [ ] Tap suggestion chip
- [ ] Suggestion inserts into text
- [ ] Type more, suggestions update

**AI Interaction Mode:**
- [ ] Type "Please help me write an email"
- [ ] Tap ✨ sparkle button
- [ ] AI action list appears
- [ ] Tap "Continue Writing"
- [ ] Loading indicator shows
- [ ] AI response streams in
- [ ] Text replaces input
- [ ] Tap Back button
- [ ] Returns to typing mode

**Error Scenarios:**
- [ ] Disable network, try AI action → Shows "No connection" error
- [ ] Use invalid API key → Shows "Invalid key" error
- [ ] Exceed rate limit → Shows "Rate limit exceeded, retry in 60s"
- [ ] Disable Full Access → Shows permission prompt

**Performance:**
- [ ] Type rapidly → No lag, all characters appear
- [ ] Request AI suggestion → Response in <2 seconds
- [ ] Switch modes → Instant transition

**Accessibility:**
- [ ] VoiceOver reads key labels correctly
- [ ] Dynamic Type increases text size
- [ ] High Contrast mode works

---

### 4. Performance Tests (Phase 6)

```swift
// Tests/Performance/KeyboardPerformanceTests.swift

testKeyTapLatency_Under50ms()
testAISuggestionLatency_Under2000ms()
testModeSwitchLatency_Under100ms()
testMemoryUsage_UnderAppleLimit50MB()
```

**Profiling:**
- Use Instruments (Time Profiler, Allocations)
- Monitor extension memory usage (Apple limit: 50MB)
- Measure network request latency

---

## 🖥️ Server/Gateway Testing

### 1. Unit Tests (Phase 1)

#### Auth Middleware Tests
```typescript
// tests/auth.test.ts

test('valid API key authenticates')
test('invalid API key returns 401')
test('missing Authorization header returns 401')
test('disabled API key returns 403')
```

#### Rate Limiter Tests
```typescript
// tests/rateLimit.test.ts

test('under limit allows requests')
test('over limit returns 429')
test('burst allowance works correctly')
test('window resets after time period')
test('different clients have separate limits')
```

#### Key Manager Tests
```typescript
// tests/keyManager.test.ts

test('creates new API key')
test('lists all keys')
test('updates key configuration')
test('revokes key')
test('hot-reloads on file change')
```

#### Proxy Tests
```typescript
// tests/proxy.test.ts

test('forwards request to Ollama')
test('streams response back to client')
test('handles Ollama errors gracefully')
test('adds custom headers')
```

**Test Framework:** Vitest (already configured)

**Run Command:**
```bash
if [[ -z "${LLM_GATEWAY_ROOT:-}" || ! -d "$LLM_GATEWAY_ROOT" ]]; then
  echo "Set LLM_GATEWAY_ROOT to a valid LLM Gateway checkout, or skip backend-only tests." >&2
  exit 1
fi
cd "$LLM_GATEWAY_ROOT"
npm test
```

---

### 2. Integration Tests (Phase 1)

```typescript
// tests/integration/api.test.ts

test('full auth flow: create key → authenticate → make request')
test('rate limit flow: exceed limit → wait → retry succeeds')
test('admin flow: login → create key → update config')
test('streaming flow: request completion → receive SSE stream')
```

**Run Command:**
```bash
npm run test:integration
```

---

### 3. Load Tests (Phase 6)

#### Goals:
- 100 concurrent clients
- Sustained 1000 requests/minute
- <2 second p95 latency
- <5% error rate

**Tool:** Apache Bench or k6

```bash
# Simple load test with Apache Bench
ab -n 1000 -c 10 -H "Authorization: Bearer sk-test-xxx" \
   -p request.json -T application/json \
   http://localhost:8080/v1/completions

# Advanced load test with k6
k6 run tests/load/completion-load-test.js
```

**k6 Script:**
```javascript
// tests/load/completion-load-test.js

import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10, // 10 virtual users
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<2000'], // 95% under 2s
  },
};

export default function () {
  const payload = JSON.stringify({
    model: 'gemma4:latest',
    prompt: 'Say hello',
    max_tokens: 50,
    stream: false,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer sk-test-xxx',
    },
  };

  const res = http.post('http://localhost:8080/v1/completions', payload, params);
  
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 2s': (r) => r.timings.duration < 2000,
  });

  sleep(1);
}
```

---

### 4. Security Tests (Phase 6)

#### Penetration Testing Checklist:
- [ ] SQL Injection (N/A - no SQL database)
- [ ] XSS (N/A - no HTML rendering)
- [ ] CSRF (N/A - API only)
- [ ] Rate limit bypass attempts
- [ ] Authorization bypass attempts
- [ ] API key enumeration resistance
- [ ] DDoS resilience

**Manual Tests:**
```bash
# Try requests without API key
curl http://localhost:8080/v1/completions

# Try invalid API key
curl -H "Authorization: Bearer invalid" \
     http://localhost:8080/v1/completions

# Try brute force rate limit
for i in {1..100}; do
  curl -H "Authorization: Bearer sk-test-xxx" \
       http://localhost:8080/v1/completions &
done
```

---

## 🔄 End-to-End Tests (Phase 6)

### Scenario 1: New User Flow
1. Download app from App Store
2. Open app, see onboarding
3. Enter API key from gateway admin
4. Enable keyboard in iOS Settings
5. Enable Full Access
6. Open Messages app
7. Type message using keyboard
8. Use AI to rewrite message
9. Send message

**Expected:** Smooth flow, no errors, AI works

### Scenario 2: Rate Limit Flow
1. Make 30 requests in 1 minute (at limit)
2. Make 31st request
3. Receive 429 error
4. See "Rate limit exceeded" UI
5. Wait 60 seconds
6. Try again
7. Request succeeds

**Expected:** Clear error messaging, automatic retry works

### Scenario 3: Network Error Recovery
1. Enable Airplane Mode
2. Try to use AI feature
3. See "No connection" error
4. Disable Airplane Mode
5. Retry
6. Request succeeds

**Expected:** Graceful degradation, clear error, automatic retry

---

## 🎭 Regression Test Suite (Ongoing)

**Run Before Every Release:**

### iOS:
```bash
./ios/run-all-tests.sh
# Runs: unit + integration + manual checklist
```

### Server:
```bash
./server/run-all-tests.sh
# Runs: unit + integration + load (light)
```

### E2E:
- Manual test critical user flows
- Check on physical device (not just Simulator)
- Test on iOS 16, 17, 18 (current support matrix)

---

## 📊 Test Metrics & Reporting

### Daily Metrics:
- Test pass rate (target: 100%)
- Code coverage (target: 80%+)
- Average test runtime (keep under 5 minutes)

### Weekly Metrics:
- New bugs introduced vs. fixed
- Performance regression checks
- Load test results (throughput, latency)

### Tools:
- **Coverage:** Xcode Code Coverage, Istanbul (Node.js)
- **Reporting:** Test results published to GitHub Actions
- **Dashboard:** Keep the Markdown status report in `docs/TDD_STATUS.md`

---

## 🐛 Bug Tracking

**Location:** track active issues in `docs/WORK_QUEUE.md`; use a concise, reproducible issue template.

**Format:**
```markdown
## 🐛 Known Issues

### P0 (Critical - Blocks Release)
- None

### P1 (High - Should Fix Before Release)
- [ ] #12: Keyboard crashes on iOS 16.4 with long text
- [ ] #15: Rate limit not enforced for streaming requests

### P2 (Medium - Fix Soon)
- [ ] #23: Suggestion bar doesn't scroll smoothly
- [ ] #28: Dark mode colors slightly off

### P3 (Low - Nice to Have)
- [ ] #45: Add haptic feedback for delete key
```

---

## ✅ Test Execution Schedule

### During Development (TDD):
- Write test BEFORE feature code
- Run tests after every change
- Commit only when tests pass

### Pre-Commit Hook:
```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Running tests..."
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT" || exit 1
./scripts/local-ci.sh --quick || exit 1
echo "✅ All tests passed"
```

### Before Merge to Main:
- All unit tests pass
- All integration tests pass
- Manual smoke test complete
- Code coverage >80%

### Before Release:
- Full regression suite
- Manual E2E flows
- Performance profiling
- Security audit
- Test on physical device

---

## 🚀 CI/CD Integration (Phase 7)

The repository workflow is `.github/workflows/openkeyboard-ci.yml`; keep OpenKeyboard CI commands rooted in this repository. LLM Gateway is a separate checkout and must run its own backend CI. If GitHub Actions or macOS runners are unavailable, use `./scripts/local-ci.sh --quick` locally and report which simulator-only checks could not run.

---

## 📋 Test Checklist Summary

**Before starting development:**
- [x] Test plan created
- [ ] Test frameworks configured
- [ ] Mock data prepared
- [ ] CI pipeline designed

**During each phase:**
- [ ] Unit tests written (TDD)
- [ ] Integration tests pass
- [ ] Manual testing done
- [ ] Performance acceptable

**Before release:**
- [ ] All tests pass (100%)
- [ ] Coverage >80%
- [ ] E2E flows tested
- [ ] Known issues documented
- [ ] Performance benchmarks met
- [ ] Security audit complete

---

**Next:** Set up test infrastructure before writing production code! 🧪
