---
name: write-openkeyboard-product-copy
description: Write and review user-facing OpenKeyboard product copy across individual screens and end-to-end flows, balancing interface clarity, truthful marketing, accessibility, and consistent terminology. Use for visible app or keyboard-extension text; do not use for semantic model prompts or generated user content.
---

# Write OpenKeyboard Product Copy

Choose words that make the product's value, current state, consequences, and next action clear.
Treat every target screen as one step in a journey, even when the requested deliverable covers only
that screen.

## Establish scope and truth

1. Read `AGENTS.md` completely and apply its authority ledger. A copy audit or recommendation is
   read-only unless the user clearly requests implementation. When implementation is already
   requested, use this skill within `$develop-openkeyboard` without adding a new approval gate.
2. Select the working mode:
   - **Shipping-copy audit:** judge visible claims and actions against current production behavior.
   - **Proposed-surface writing:** draft against authorized requirements, prototypes, or designs;
     label behavior assumptions and future intent instead of presenting them as shipping facts.
   - **Implementation:** choose the copy first, then make only the authorized repository edits.
3. Identify the audience, user job, target surface, business or product goal, and requested final
   form. Preserve any requested voice; do not invent a persona or conversion goal.
4. Inspect the visible source, its state-producing ViewModel or service, relevant tests, and current
   product documentation. Trace production routing and call sites: a string found by search may be
   unused, debug-only, test-only, or model-generated. Classify static UI copy, dynamic configuration,
   user text, and generated output before proposing a change.
5. Inspect an available screenshot, design, preview, or normally running screen when visual
   hierarchy, competition, continuity, or fit affects the decision. If none is available, qualify
   layout and truncation conclusions instead of claiming visual acceptance from source alone.
6. Use shipping behavior for what the product actually does and current authoritative docs for
   intended positioning. Flag conflicts instead of writing around them. Treat old research and
   completed plans as context, not evidence of a current capability. Never market planned, hidden,
   test-only, or unverified behavior as available.
7. Keep semantic operation identifiers, model instructions, prompt wording, response schemas, and
   generated response content in the pinned `Vendor/semantic-prompt-contract`. This skill owns
   product-interface language, not model prompts or the user's generated writing.

For positioning, start with the current `README.md` sections that explain what the product does,
why it exists, and its privacy model. Use `docs/RELEASE_HARDENING.md` for Full Access and data-use
copy direction. Confirm feature-readiness claims against production code, tests, and the current
status in `docs/AI_KEYBOARD_TODO.md` rather than relying on an old plan.

Before making a privacy or control claim, re-verify the current implementation and docs. The
present product truth is narrower than “text never leaves the device”: basic typing mechanics stay
local, while networked AI behavior can send needed text or bounded context to the user's configured
gateway. Verify whether each trigger is manual or automatic and disclose that the gateway or a
downstream model provider's logging policy may apply. Explain `Allow Full Access` calmly and use
Apple's exact permission name. Never broaden these facts into an absolute claim about privacy,
security, locality, or control.

## Map the journey before drafting

For an individual screen, inspect enough surrounding context to understand:

- the entry action or preceding screen;
- the target screen's purpose, current state, and primary decision;
- the immediate destination, completion state, or exit;
- alternate first-run, returning-user, permission, and recovery paths that reach the same screen;
- other surfaces that name the same feature, object, status, or action.

For a multi-screen request, order the work by the user's journey rather than by source-file order.
Build a small working vocabulary of product name, feature names, system permissions, object names,
action verbs, and state terms. Search all visible occurrences before introducing a synonym. Use
“Open Keyboard” for the visible product name unless current authoritative sources deliberately
change it; reserve `OpenKeyboard` for code identifiers.

Do not expand an isolated-screen deliverable into an unsolicited redesign. Use adjacent screens to
protect continuity and report only material issues outside the requested surface.

## Apply three lenses

Evaluate every proposed string through all applicable lenses:

### Interface clarity

- A user should understand where they are, what changed, and what to do next without decoding
  internal terms.
- Titles orient or state an outcome. Supporting text adds new information instead of repeating the
  title. A primary action names its immediate effect or destination.
- Controls must describe actual behavior. Do not use a marketing promise as a button label or make
  a status look actionable. Trace every call to action to the function and state transition it
  triggers; copy must not promise to save, retry, replace, or navigate when the control does
  something else.
- Error copy says what happened in user terms, what remained safe or unchanged when relevant, and
  the available recovery. Keep raw payloads, credentials, identifiers, and implementation details
  out of visible copy.
- Prefer plain, compact, concrete language. Account for Dynamic Type, narrow keyboard surfaces,
  variable values, and likely localization expansion; do not shorten away necessary meaning.

### Product and marketing value

- Lead with the user outcome at discovery and decision moments, then support it with a specific,
  verifiable reason to believe.
- Express OpenKeyboard's meaningful differentiation—user choice and control over the keyboard,
  gateway, API keys, model backend, and routing—only to the extent current behavior supports it.
- Replace generic hype and repeated slogans with useful proof. Never invent speed, quality,
  security, privacy, compatibility, or feature claims.
- Keep transactional, permission, loading, and error surfaces focused on comprehension and trust.
  Marketing may support those moments, but must not obscure consequences or recovery.

### Trust and accessibility

- Put material data use, permission, cost, destructive effect, and limitation information before
  commitment, close to the relevant action.
- Avoid coercive urgency, confirm-shaming, false scarcity, or language that blames the user.
- Keep visible labels and VoiceOver labels aligned. Icon-only controls need action-specific labels;
  hints should add consequences or context rather than repeat the label.
- Avoid idioms, directional-only instructions, sentence fragments assembled at runtime, and
  unnecessary jargon. Preserve platform terms that users must find in iOS Settings.

When the lenses conflict on a transactional, permission, privacy, or error surface, behavioral and
trust clarity wins. State the marketing tradeoff instead of hiding it.

## Complete the screen pass

For each applicable state—default, disabled, empty, loading, stale, success, partial or limited,
permission needed, offline, authentication failure, timeout, cancellation, destructive
confirmation, and recovery—check the following:

1. **Orientation:** Does the headline name the task, state, or outcome?
2. **Value:** Does the supporting message answer why this matters here?
3. **Action:** Is there one obvious next step whose label matches its immediate result?
4. **Expectation:** Does the copy explain a meaningful wait, prerequisite, consequence, or
   limitation before it surprises the user?
5. **Recovery:** Does failure preserve agency and provide a real next action?
6. **Fit:** Will the important text remain understandable on compact and accessibility layouts?
7. **Access:** Do visible and assistive labels communicate the same intent?

Review only states that exist or are in the authorized scope. If a needed state or recovery path is
missing, record a product or interaction gap; copy cannot repair absent behavior.

## Run the continuity pass

Read the journey from predecessor to target to successor and verify:

- the same thing keeps the same name; do not vary terminology merely for style;
- the previous call to action accurately predicts the next screen or state;
- each screen advances the explanation instead of restarting it or repeating a slogan;
- a promise made during onboarding is visibly fulfilled in setup, home status, and the keyboard;
- setup, connection, model-capability, permission, and error states describe the same underlying
  reality across the host app and extension;
- readiness terms form an evidence-backed progression such as configured, connected, checked,
  enabled, and available instead of using “ready” for several different conditions;
- action verbs remain semantically stable—for example, preview, apply, accept, reject, copy, retry,
  and reset are not interchangeable;
- success closes the loop, while partial success and failure point to the correct recovery path;
- tone, person, tense, capitalization, punctuation, and accessibility naming remain coherent.

Use repetition when it reinforces a critical trust fact in a new decision context. Tailor the
detail to that context rather than copying the same paragraph everywhere.

## Recommend decisively

- Give one recommended version. Offer one alternate only when it represents a real product or tone
  tradeoff, and name that tradeoff.
- Prefer the shortest version that retains the necessary meaning, proof, and consequence—not the
  shortest version in isolation.
- Separate copy findings from product, interaction, legal, localization, and technical gaps.
- Mark material claims as `shipping fact`, `verified limitation`, or `future intent`. Reject
  unsupported claims from shipping UI. In a proposed-surface deck, keep `future intent` visibly
  tied to its authorized requirement so it cannot be mistaken for current marketing copy.
- Never approve high-consequence words such as “ready,” “done,” “connected,” “private,” “saved,” or
  “try again” until the implementation supports that exact promise.
- Keep uncertain facts explicit. Do not silently resolve contradictory sources or make legal and
  App Store compliance claims from copy quality alone.

## Deliver the copy deck

Return only the detail the task needs, using this structure when a formal review is useful:

```text
Goal and audience:
Journey: <entry> -> <target> -> <next or exit>
Message priority:
Working vocabulary:

Recommended copy:
| Screen / state | Element | Current copy | Recommended copy | Purpose and continuity |

Claim audit:
| Claim | Classification | Evidence or conflict | Decision |

Continuity findings:
Non-copy gaps:
Assumptions or open decisions:
```

Omit `Current copy` for a new surface. Group multi-screen decks in journey order. Keep rationale
short and decision-oriented; do not bury the recommendation in an option list. For an existing
surface, cite the production source for each screen or state and include changed accessibility copy
where applicable.

## Implement only when authorized

When the user requests the copy change, continue through `$develop-openkeyboard`:

1. Search for every affected visible string and state producer, then change only the approved
   surface. Review adjacent surfaces for continuity, but report them without editing unless the
   user included them in scope or an already in-scope shared string necessarily affects them.
2. Update accessibility labels and focused tests when their intent or asserted visible contract
   changes. Do not rewrite behavior, layouts, canonical prompts, or unrelated prose under cover of
   a copy edit.
3. Inspect compact and accessibility layouts. User-visible copy changes are UI changes, so follow
   `AGENTS.md` for automated regression evidence and normal simulator runtime proof before push.
4. For skill- or workflow-only edits with no product UI change, use the workflow-policy hygiene
   route; do not claim runtime acceptance.
