# Testing Guide — Open Keyboard + LLM Gateway

## What You Can Test Right Now

### ✅ LLM Gateway (Backend)
The gateway is **complete and ready to test**.

---

## 1. Test LLM Gateway

### Start the Gateway

The gateway is an optional, separate checkout. Set `LLM_GATEWAY_ROOT` to its repository root on the current machine. If it is not installed, skip the gateway-only sections and use the OpenKeyboard mock/core test routes instead.

```bash
if [[ -z "${LLM_GATEWAY_ROOT:-}" || ! -d "$LLM_GATEWAY_ROOT" ]]; then
  echo "Set LLM_GATEWAY_ROOT to a valid LLM Gateway checkout before running gateway tests." >&2
  exit 1
fi
cd "$LLM_GATEWAY_ROOT"
npm start
```

Should see:
```
🚀 LLM Gateway running on http://localhost:8080
```

---

### Test 1: Health Check

```bash
curl http://localhost:8080/health
```

**Expected:**
```json
{
  "status": "ok",
  "timestamp": "2026-04-21T14:06:00.000Z"
}
```

---

### Test 2: Admin Login

```bash
curl -X POST http://localhost:8080/admin/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "your-password"}'
```

**Expected:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expiresIn": "24h"
}
```

Save the token — you'll need it for API key management.

---

### Test 3: Create API Key

```bash
# Replace YOUR_ADMIN_TOKEN with token from Test 2
curl -X POST http://localhost:8080/admin/keys \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test-keyboard",
    "rateLimit": {
      "requestsPerMinute": 10,
      "burstAllowance": 3
    },
    "features": {
      "completions": true,
      "customActions": true
    }
  }'
```

**Expected:**
```json
{
  "id": "key_abc123...",
  "key": "sk-test-abc123...",
  "name": "test-keyboard",
  "rateLimit": {
    "requestsPerMinute": 10,
    "burstAllowance": 3
  },
  "features": {
    "completions": true,
    "customActions": true
  },
  "createdAt": "2026-04-21T14:06:00.000Z"
}
```

**SAVE THE API KEY** — you can't retrieve it again!

---

### Test 4: Test Completions Endpoint

```bash
# Use the API key from Test 3
curl -X POST http://localhost:8080/v1/completions \
  -H "Authorization: Bearer sk-test-abc123..." \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "The quick brown fox",
    "max_tokens": 20,
    "temperature": 0.7
  }'
```

**Expected:**
```json
{
  "id": "cmpl-abc123",
  "choices": [
    {
      "text": " jumps over the lazy dog",
      "finish_reason": "stop"
    }
  ]
}
```

---

### Test 5: Test Rate Limiting

Run the same completion request **4 times quickly**:

```bash
for i in {1..4}; do
  curl -X POST http://localhost:8080/v1/completions \
    -H "Authorization: Bearer sk-test-abc123..." \
    -H "Content-Type: application/json" \
    -d '{"prompt": "test", "max_tokens": 5}'
  echo ""
done
```

**Expected:**
- First 3 requests: ✅ Success (burst allowance)
- 4th request: ❌ `429 Too Many Requests`

```json
{
  "error": "Rate limit exceeded. Try again in 6 seconds."
}
```

---

### Test 6: Admin Web UI

Open in browser:
```
http://localhost:8080/admin/
```

**Features:**
- Login page
- Dashboard (API keys list)
- Create new API key
- View usage stats
- Delete keys

---

## 2. Test iOS Keyboard (Not Ready Yet)

### Current Status
❌ **Cannot test yet** — No Xcode project exists.

### What's Missing:
1. Xcode project file (`.xcodeproj`)
2. Compiled app binary
3. Code implementation (just scaffolded Swift files exist)

---

## 3. Create Xcode Project (To Enable Testing)

### Option A: Manual Creation

1. **Open Xcode** on your Mac
2. **New Project** → iOS → App
3. **Product Name:** OpenKeyboard
4. **Bundle Identifier:** `com.maneesh.openkeyboard`
5. **Save to:** the repository root (the directory containing this guide and `README.md`)

6. **Add Keyboard Extension:**
   - File → New → Target
   - iOS → Keyboard Extension
   - Name: `OpenKeyboardExtension`
   - Enable "Allow Full Access"

7. **Configure App Groups:**
   - Select OpenKeyboard target
   - Signing & Capabilities → + Capability → App Groups
   - Add: `group.com.maneesh.openkeyboard`
   - Repeat for OpenKeyboardExtension target

8. **Build:**
   - Select iPhone Simulator
   - Press ⌘+R to build and run

---

### Option B: Use Existing Scaffolded Code

The Swift files already exist at this repository-relative path:
```
OpenKeyboard/
├── OpenKeyboardApp.swift
├── Views/
│   ├── ContentView.swift
│   ├── SettingsView.swift
│   └── OnboardingView.swift
├── ViewModels/
│   └── SettingsViewModel.swift
├── Models/
│   └── AppConfig.swift
└── Services/
    └── NetworkManager.swift
```

But they need to be **imported into an Xcode project** to build.

---

## 4. Integration Testing (Once iOS App Exists)

### Test Flow:

1. **Launch OpenKeyboard app** (on Simulator or device)
2. **Enter API key** from Test 3
3. **Test connection** → should hit `http://localhost:8080/health`
4. **Enable keyboard:**
   - Settings → General → Keyboard → Keyboards
   - Add "OpenKeyboard"
   - Enable "Allow Full Access"
5. **Open Notes app**
6. **Switch to OpenKeyboard** (globe key)
7. **Type something** → AI suggestions should appear
8. **Tap AI button** → AI actions menu
9. **Select "Fix Grammar"** → should call gateway `/v1/completions`

---

## 5. Testing Checklist

### Gateway Tests
- [x] Health check responds
- [x] Admin login works
- [x] Create API key
- [x] List API keys
- [x] Delete API key
- [x] Completions endpoint works
- [x] Rate limiting enforced
- [x] Admin UI loads

### iOS App Tests (Once Created)
- [ ] App launches
- [ ] Settings screen loads
- [ ] Can save API key
- [ ] Test connection button works
- [ ] Onboarding flow completes
- [ ] Deep link to keyboard settings works

### Keyboard Extension Tests (Once Created)
- [ ] Keyboard appears in apps
- [ ] Can type letters
- [ ] Can type numbers/symbols
- [ ] Shift key works
- [ ] Delete key works
- [ ] Return key works
- [ ] AI suggestions appear
- [ ] Can tap suggestions to insert
- [ ] AI actions menu works
- [ ] "Fix Grammar" works
- [ ] Network errors handled gracefully

---

## 6. Next Steps to Enable iOS Testing

**You need to:**
1. **Create Xcode project** (5 minutes)
2. **Copy Swift files** into project (5 minutes)
3. **Configure signing** (2 minutes)
4. **Build** (first build: ~1 minute)

**Then I can help with:**
- Implementing NetworkManager (connect to gateway)
- Building keyboard UI
- Handling API responses
- Error handling

---

## 7. Quick Start Command (Gateway Only)

```bash
# Terminal 1 - Start gateway
if [[ -z "${LLM_GATEWAY_ROOT:-}" || ! -d "$LLM_GATEWAY_ROOT" ]]; then
  echo "Set LLM_GATEWAY_ROOT to a valid LLM Gateway checkout before running gateway tests." >&2
  exit 1
fi
cd "$LLM_GATEWAY_ROOT"
npm start

# Terminal 2 - Test it
curl http://localhost:8080/health
```

If you see `{"status":"ok"}` → Gateway is working! ✅

---

## Questions?

- **Gateway not starting?** Check if port 8080 is in use: `lsof -i :8080`
- **Need admin credentials or want to reset API keys?** Follow the documentation in the configured LLM Gateway checkout; its storage layout is not assumed here.

---

**Ready to test the gateway now, or want to create the iOS project first?**
