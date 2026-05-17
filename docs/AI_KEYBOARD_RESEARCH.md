# AI Keyboard Project - Research & Execution Plan

**Date:** 2026-04-20  
**Status:** Pre-Development Research Phase  
**Goal:** Build production-ready AI-powered iOS keyboard with authenticated gateway

---

## 📚 Research Summary

### iOS Keyboard Extension Architecture (Feb 2026)

**Source:** [Building an iOS AI Keyboard with SwiftUI](https://medium.com/@jonathanaraney/building-an-ios-ai-keyboard-with-swiftui-my-experience-so-far-308a67e536a7)

**Key Learnings:**

1. **Two-Target Structure Required**
   - Main container app (must provide standalone value or Apple rejects)
   - Keyboard extension (separate process, separate memory)
   - Extensions subclass `UIInputViewController`

2. **SwiftUI Integration Pattern**
   ```swift
   // In KeyboardViewController (UIKit)
   let hostingController = UIHostingController(rootView: KeyboardView())
   addChild(hostingController)
   view.addSubview(hostingController.view)
   
   // Pass textDocumentProxy via ObservableObject ViewModel
   class KeyboardViewModel: ObservableObject {
       let textProxy: UITextDocumentProxy
   }
   ```

3. **Full Access Permission - CRITICAL**
   - Default: No network, no clipboard, heavily sandboxed
   - Requires user to manually enable "Allow Full Access" in Settings
   - **Solution:** Aggressive onboarding with step-by-step screenshots
   - Check `hasFullAccess` on every interaction, prompt if disabled

4. **Data Sharing Between App & Extension**
   - UserDefaults are **NOT** shared by default
   - **Solution:** App Groups
   ```swift
   // Create App Group: group.com.yourname.aikeyboard
   let shared = UserDefaults(suiteName: "group.com.yourname.aikeyboard")
   shared?.set(apiKey, forKey: "apiKey")
   ```

5. **Performance Matters**
   - Users expect instant responses (<500ms)
   - Every 100ms you shave off improves perceived native feel
   - Optimize: Fast LLM models, concise prompts, regional deployment

6. **Text Access Limitations**
   - `textDocumentProxy` only shows text before/after cursor
   - **Cannot** see entire document
   - Plan AI features around this constraint

---

### Server-Side: Multi-Tenant API Gateway Patterns

**Sources:**
- [Building API Gateway in Node.js: Rate Limiting](https://medium.com/@dmytro.misik/building-api-gateway-in-node-js-part-iii-rate-limiting-5d94f3f498ec)
- [Multi-Tenant SaaS Rate Limiting](https://zuplo.com/learning-center/api-gateway-for-multi-tenant-saas)

**Key Learnings:**

1. **Rate Limiting Strategies**
   - **Per-Client:** Fair usage, different limits per API key
   - **Overall System:** Protect backend from total overload
   - **Per-Endpoint:** Strict limits on expensive operations (AI generation)
   - **Recommendation:** Combine per-client + overall + per-endpoint

2. **Rate Limit Algorithms**
   - **Token Bucket:** Best for burst traffic (preferred for keyboards)
   - **Sliding Window:** More accurate, slightly more complex
   - **Fixed Window:** Simpler but can allow burst at window edges
   - **Recommendation:** Start with Token Bucket for simplicity

3. **Multi-Tenant Configuration**
   ```json
   {
     "apiKey": "sk-client-xxx",
     "rateLimit": {
       "requestsPerMinute": 30,
       "burstAllowance": 10
     },
     "features": {
       "suggestions": true,
       "customActions": [...]
     },
     "modelConfig": {
       "model": "gemma4:latest",
       "maxTokens": 100
     }
   }
   ```

4. **Storage for Rate Limiting**
   - **In-Memory:** Fast, simple (fine for single-server)
   - **Redis:** Distributed, persistent (needed for multi-server)
   - **Recommendation:** Start in-memory, prepare for Redis migration

5. **HTTP 429 Response Patterns**
   ```javascript
   res.status(429).json({
     error: "Rate limit exceeded",
     retryAfter: 60, // seconds
     limit: 30,
     remaining: 0,
     resetAt: "2026-04-20T01:00:00Z"
   })
   ```

6. **Admin Auth Patterns**
   - JWT tokens for session management
   - Separate admin API for key CRUD operations
   - Don't expose admin endpoints publicly

---

## 🎯 Priority-Based Execution Plan

### Phase 0: Project Setup (Day 1)
**Priority: P0 (Must Have)**

- [ ] Create project structure
- [ ] Initialize Git repository
- [ ] Create documentation framework (CLAUDE.md, ARCHITECTURE.md, etc.)
- [ ] Set up Xcode project with 2 targets (App + Extension)
- [ ] Configure App Groups for data sharing
- [ ] Set up bundle identifiers

**Deliverable:** Empty but properly structured project ready for development

---

### Phase 1: Gateway Enhancement (Day 1-2)
**Priority: P0 (Must Have)**

#### 1.1 Admin Authentication System
- [ ] Add JWT-based admin auth
- [ ] Create `/admin/login` endpoint
- [ ] Protect admin routes with auth middleware

#### 1.2 API Key CRUD Operations
- [ ] `POST /admin/keys` - Create new API key
- [ ] `GET /admin/keys` - List all keys
- [ ] `PATCH /admin/keys/:id` - Update key config
- [ ] `DELETE /admin/keys/:id` - Revoke key
- [ ] Hot-reload key changes (already implemented)

#### 1.3 Per-Client Configuration
```typescript
interface ClientConfig {
  apiKey: string;
  name: string;
  enabled: boolean;
  rateLimit: {
    requestsPerMinute: number;
    burstAllowance: number;
  };
  features: {
    suggestions: boolean;
    customActions: CustomAction[];
  };
  modelConfig: {
    model: string;
    maxTokens: number;
    temperature: number;
  };
}
```

#### 1.4 Enhanced Rate Limiting
- [ ] Implement Token Bucket algorithm
- [ ] Add per-endpoint limits (stricter for AI generation)
- [ ] Return proper 429 responses with retry headers

**Deliverable:** Fully functional multi-tenant gateway with admin panel

---

### Phase 2: iOS Main App (Day 3)
**Priority: P0 (Must Have)**

#### 2.1 Settings Screen
- [ ] API Key input field (secure text entry)
- [ ] "Test Connection" button
- [ ] Server status indicator (green/red)
- [ ] Save key to App Group shared storage

#### 2.2 Onboarding Flow
- [ ] Welcome screen
- [ ] API key entry
- [ ] "Open Keyboard Settings" button
- [ ] Step-by-step screenshots for enabling Full Access
- [ ] Completion checklist

#### 2.3 Configuration UI
- [ ] View current plan/limits (from server)
- [ ] Usage statistics (requests used today)
- [ ] Model selection (if server allows)

**Deliverable:** Container app that passes App Store review guidelines

---

### Phase 3: Keyboard Extension - Core Layout (Day 4-5)
**Priority: P0 (Must Have)**

#### 3.1 Basic QWERTY Layout
- [ ] UIInputViewController + UIHostingController setup
- [ ] SwiftUI keyboard view
- [ ] Letter keys (a-z, A-Z with shift)
- [ ] Number keys (0-9)
- [ ] Symbol keys (!, @, #, etc.)
- [ ] Special keys: shift, delete, return, space

#### 3.2 Key Rendering
- [ ] iOS-style rounded rectangles
- [ ] Dark mode support
- [ ] Proper spacing & sizing
- [ ] Touch feedback (visual + haptic)

#### 3.3 Text Input Integration
- [ ] Connect keys to textDocumentProxy
- [ ] Insert characters on tap
- [ ] Delete characters
- [ ] Auto-capitalization
- [ ] Return key behavior

**Deliverable:** Fully functional typing keyboard (no AI yet)

---

### Phase 4: AI Integration - Suggestion Bar (Day 6)
**Priority: P1 (High Priority)

#### 4.1 Top Suggestion Bar
```
┌─────────────────────────────────┐
│ [Logo] continue | rewrite | fix │ [✨]
└─────────────────────────────────┘
```

- [ ] Horizontal scroll view for suggestions
- [ ] Tap to insert suggestion
- [ ] Real-time suggestions as user types
- [ ] Debouncing (wait 500ms after last keystroke)

#### 4.2 API Integration
- [ ] Create NetworkManager (with API key from App Group)
- [ ] POST to `/v1/completions` with streaming
- [ ] Handle 401 (invalid key), 429 (rate limit)
- [ ] Display errors gracefully

#### 4.3 Streaming Response Handling
- [ ] Parse SSE (Server-Sent Events) stream
- [ ] Update suggestion chips in real-time
- [ ] Cancel in-flight requests when user types

**Deliverable:** Live AI suggestions while typing

---

### Phase 5: AI Interaction Mode (Day 7-8)
**Priority: P1 (High Priority)

#### 5.1 Toggle to AI Mode
- [ ] ✨ button switches keyboard to AI view
- [ ] Back button returns to typing mode
- [ ] Preserve state when switching

#### 5.2 AI Action List UI
```
┌─────────────────────────────────┐
│  [←Back]  AI Assistant           │
├─────────────────────────────────┤
│  📝 Continue Writing            │
│  ✍️  Rewrite                     │
│  ✅ Fix Grammar                  │
│  📋 Summarize                    │
│  🔄 Translate                    │
│  ⚡ Custom Action 1             │
└─────────────────────────────────┘
```

- [ ] Vertical list of actions
- [ ] Icons + labels
- [ ] Fetch custom actions from server (per API key)
- [ ] Loading states

#### 5.3 Action Execution
- [ ] Read current text from textDocumentProxy
- [ ] Send to server with selected action
- [ ] Stream response
- [ ] Replace text or append to cursor

**Deliverable:** Full Grammarly-like AI interaction mode

---

### Phase 6: Polish & Testing (Day 9-10)
**Priority: P2 (Nice to Have)

#### 6.1 Error Handling
- [ ] No internet connection UI
- [ ] Invalid API key message
- [ ] Rate limit exceeded message (with retry timer)
- [ ] Server down fallback

#### 6.2 Performance Optimization
- [ ] Reduce API payload size
- [ ] Cache suggestions for 30 seconds
- [ ] Optimize keyboard layout rendering
- [ ] Measure & log response times

#### 6.3 Testing
- [ ] Unit tests for ViewModel logic
- [ ] Integration tests for API calls
- [ ] Manual testing on physical device
- [ ] Full Access enabled/disabled scenarios

**Deliverable:** Production-ready, polished keyboard

---

### Phase 7: Documentation & Open Source Prep (Day 11)
**Priority: P2 (Nice to Have)

- [ ] Complete CLAUDE.md
- [ ] Write comprehensive README
- [ ] Document server setup (gateway)
- [ ] Document iOS build process
- [ ] Create deployment guide
- [ ] Add screenshots/GIFs
- [ ] License file (Apache 2.0 or MIT?)

**Deliverable:** Fully documented open-source project

---

## 🏗️ Architecture Decisions

### iOS Architecture
**Pattern:** MVVM + Repository Pattern

```
KeyboardView (SwiftUI)
    ↓
KeyboardViewModel (ObservableObject)
    ↓
KeyboardRepository (API calls)
    ↓
NetworkManager (URLSession wrapper)
```

**Rationale:**
- MVVM: Natural fit for SwiftUI's reactive paradigm
- Repository: Abstracts data source (API), testable
- Single source of truth via `@Published` properties

### Server Architecture
**Pattern:** Layered Architecture with Middleware Chain

```
Client Request
    ↓
CORS Middleware
    ↓
Auth Middleware (validate API key)
    ↓
Rate Limit Middleware (token bucket)
    ↓
Logging Middleware
    ↓
Proxy Handler (forward to Ollama)
    ↓
Ollama LLM
```

**Rationale:**
- Middleware chain: Easy to add/remove features
- Separation of concerns: Each layer has one job
- Already implemented in llm-gateway (just enhance)

---

## 📋 Open Questions

1. **Project Name?**
   - Options: AIKeyboard, SmartKeys, TypeAI, FlowType, etc.
   - Bundle ID: `com.maneesh.[projectname]`

2. **Gateway Admin UI?**
   - Web-based dashboard for managing keys?
   - Or just API + Postman/curl?

3. **Subscription/Monetization?**
   - Free tier: 10 requests/day?
   - Pro tier: Unlimited?
   - Or keep it fully open-source?

4. **License?**
   - Apache 2.0 (like Allora)?
   - MIT?
   - GPL?

---

## 🚀 Ready to Start?

**Estimated Timeline:** 11 days (aggressive)  
**Realistic Timeline:** 2-3 weeks with testing  

**Next Steps:**
1. Answer open questions (name, bundle ID)
2. Create project structure
3. Start Phase 1 (Gateway enhancement)

**Token Management:**
- This research document: Load once at project start
- CLAUDE.md: Always loaded (minimal)
- Other docs: Load only when working on specific phase

