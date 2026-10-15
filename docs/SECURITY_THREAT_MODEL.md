# OpenKeyboard security review context

This is an initial, source-bound threat model for review and baseline scan setup, not a completed
scan or a claim that the boundaries are secure. Validate assumptions against the exact scanned
revision and record unresolved coverage privately. It contains no private endpoints or credentials.

## Assets, actors, and boundaries

| Asset / boundary | Review starting points | Questions to validate |
| --- | --- | --- |
| User text: host field to keyboard extension to provider | OpenKeyboardExtension/KeyboardViewModel.swift; KeyboardAIService.swift | Can stale responses apply to a changed field? Are cancellation, selection, and Full Access checked at the appropriate lifecycle boundary? |
| Credentials and provider profile shared between app/extension | OpenKeyboard/Models/AppConfig.swift; OpenKeyboardCore/Sources/OpenKeyboardCore/GatewayConfigStore.swift | Do Keychain failures and interrupted migration/clearing fail closed? Can stale App Group state resurrect a cleared profile? |
| Consent and diagnostic text on disk/export | OpenKeyboard/Services/AIOperationDiagnostics.swift | Can late responses survive revoke/delete/expiry? Are metadata/text retention, export filtering, redaction, and explicit review preserved? |
| Remote endpoints and untrusted model output | OpenKeyboard/Services/NetworkManager.swift; UniversalAIConnectorAdapter.swift; OpenKeyboardCore/Sources/OpenKeyboardCore/GatewayClient.swift | Can endpoint changes leak credentials? Are provider/model binding, malformed responses, cancellation, and transport errors handled without exposing text or secrets? |
| Dependency and prompt-contract boundary | .gitmodules; Vendor gitlinks; scripts/bootstrap-universal-ai-connector.sh | Are pinned commits validated, generated adapters derived from the canonical contract, and build/command inputs constrained? |
| Contributor-controlled code vs trusted CI and signing | .github/workflows; .githooks; scripts/check.sh; live/PR validators | Can candidate code select its own trusted validator, expose protected secrets, widen permissions, or bypass exact-head checks? Are signing/release actions separately authorized? |

Threat actors include a compromised endpoint/provider, malicious or malformed model responses,
untrusted text supplied by another app, a compromised dependency, and an untrusted PR contributor.
The operating system enforces app sandbox, extension privileges, and entitlement access; Full Access
is an OS permission boundary and its UI hint is not independent proof of authorization. Do not assume
that local storage, logs, model output, or configuration become trustworthy merely because they are
inside the app. Simulator proof is not physical-device proof.

## Baseline scan route

1. Confirm ownership, a clean isolated checkout, exact head, and pinned submodules. Inspect current
   account/plugin capabilities and usage; no plugin install, paid purchase, Cloud configuration, or
   public disclosure is authorized by this document.
2. When local Codex Security is available, choose Codebase with Deep scan off for an initial baseline.
   Supply this threat model as additional context. Start with the app/extension credential, privacy,
   and network surfaces above, and separately include scripts/workflows. A scoped scan must list
   omitted surfaces; do not call it a whole-repository baseline. Vendor source belongs to pinned
   dependencies and separate owner reviews, with integration boundaries still assessed here.
3. Require read-only source inspection. Exclude ignored live seeds, credentials, signing material,
   real typed text, build output, and private runtime artifacts from scan inputs. Use synthetic data
   for any authorized local validation. Do not contact live providers, deploy, or operate physical
   devices as a side effect of a baseline scan.
4. Inspect the actual report, coverage, deferred surfaces, and revision/manifest artifacts returned
   by the installed version. Retain the complete report directory privately outside the worktree.
   Record completion/failure and independent dispositions using the advisory workflow. Do not invent
   scan counts, severity, timing, or coverage. Missing/deferred coverage remains explicit.
5. Use scoped Changes scans for later security-sensitive PRs. Repeat baseline analysis when trust
   boundaries materially change or an owner requests it, not automatically on every PR. Cloud
   baseline/monitoring is a separately authorized alternative requiring confirmed access and usage.

This prepares a baseline route only. Report actual scan execution and activation separately in the
implementation handoff; no baseline scan is claimed by the presence of this file.
