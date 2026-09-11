#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/OpenKeyboard/OpenKeyboardApp.swift"
HARNESS="$ROOT/OpenKeyboard/Views/LiveAITestHarnessView.swift"
APP_CONFIG="$ROOT/OpenKeyboard/Models/AppConfig.swift"
DEBUG_POLICY="$ROOT/OpenKeyboardExtension/KeyboardDebugStatePolicy.swift"
PROJECT="$ROOT/OpenKeyboard.xcodeproj/project.pbxproj"

ruby - "$APP" "$HARNESS" "$APP_CONFIG" "$DEBUG_POLICY" "$PROJECT" <<'RUBY'
app_path, harness_path, app_config_path, debug_policy_path, project_path = ARGV
app = File.read(app_path)
harness = File.read(harness_path)
app_config = File.read(app_config_path)
debug_policy = File.read(debug_policy_path)
project = File.read(project_path)
simulator_guard = "#if DEBUG && targetEnvironment(simulator)"

def fail_policy(message)
  warn "Simulator credential bootstrap policy failure: #{message}"
  exit 1
end

def require_text(source, text, message)
  fail_policy(message) unless source.include?(text)
end

def ordered_positions(source, entries, message)
  offset = 0
  entries.each do |entry|
    position = source.index(entry, offset)
    fail_policy(message) unless position
    offset = position + entry.length
  end
end

def section(source, start_text, end_text)
  start_index = source.index(start_text)
  fail_policy("missing #{start_text.inspect}") unless start_index
  end_index = source.index(end_text, start_index + start_text.length)
  fail_policy("missing boundary #{end_text.inspect}") unless end_index
  source[start_index...end_index]
end

def assert_target_debug_release_conditions(configurations, bundle_identifier, target_name)
  target_configurations = configurations.select do |match|
    match[0].include?("PRODUCT_BUNDLE_IDENTIFIER = #{bundle_identifier};")
  end
  fail_policy("expected one Debug and one Release #{target_name} configuration") unless target_configurations.length == 2

  debug_configuration = target_configurations.find { |match| match[1] == "Debug" }
  release_configuration = target_configurations.find { |match| match[1] == "Release" }
  fail_policy("the #{target_name} Debug configuration must define DEBUG") unless debug_configuration&.[](0)&.include?("SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
  fail_policy("the #{target_name} Release configuration must exclude DEBUG") if release_configuration&.[](0)&.include?("SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
end

def assert_exact_simulator_guards(path, source, sensitive_pattern, simulator_guard)
  active_conditions = []

  source.each_line.with_index(1) do |line, line_number|
    stripped = line.strip
    case stripped
    when /^#if\s+(.+)$/
      active_conditions << Regexp.last_match(1)
    when /^#elseif\s+(.+)$/
      fail_policy("unbalanced #elseif in #{path}:#{line_number}") if active_conditions.empty?
      active_conditions[-1] = Regexp.last_match(1)
    when "#else"
      fail_policy("unbalanced #else in #{path}:#{line_number}") if active_conditions.empty?
      active_conditions[-1] = "else"
    when "#endif"
      fail_policy("unbalanced #endif in #{path}:#{line_number}") if active_conditions.empty?
      active_conditions.pop
      next
    end

    next unless line.match?(sensitive_pattern)
    next if active_conditions.include?(simulator_guard.delete_prefix("#if "))

    fail_policy("sensitive bootstrap source escaped the exact simulator guard at #{path}:#{line_number}")
  end

  fail_policy("unbalanced conditional compilation in #{path}") unless active_conditions.empty?
end

fail_policy("the live harness must be entirely simulator-only") unless harness.lines.first&.strip == simulator_guard
fail_policy("the live harness must close its simulator-only guard") unless harness.lines.reverse.find { |line| !line.strip.empty? }&.strip == "#endif"

[app, harness, app_config, debug_policy].each do |source|
  fail_policy("bare DEBUG compilation guard is forbidden") if source.match?(/^\s*#if DEBUG\s*$/)
end

sensitive_pattern = /OPEN_KEYBOARD_(?:TEST|LIVE|REPLACE_EXISTING_CONFIG)|unsetenv\(|SimulatorLiveAIConfiguration/
assert_exact_simulator_guards(app_path, app, sensitive_pattern, simulator_guard)
assert_exact_simulator_guards(harness_path, harness, sensitive_pattern, simulator_guard)

config_seed_pattern = /KeyboardUITestConfigProcessAuthorization|keyboardUITestConfigAuthorization|saveTestSeed|saveLegacyValuesForUITest|hasExistingRealConfig|hasFreshKeyboardExtensionUITest|keyboardUITestConfigFingerprint|consumeKeyboardExtensionUITestConfigSeed|resetKeyboardUITestConfigProcessAuthorizationForTesting/
assert_exact_simulator_guards(app_config_path, app_config, config_seed_pattern, simulator_guard)
require_text(
  debug_policy,
  simulator_guard,
  "keyboard debug-state persistence must be simulator-only"
)

require_text(
  app,
  "self.simulatorLiveAIConfiguration = SimulatorLiveAIConfiguration.capture(arguments: arguments)",
  "live credential capture must occur during OpenKeyboardApp initialization"
)
require_text(
  app,
  "let gatewayEnvironment = Self.captureUITestGatewayEnvironment(arguments: arguments)",
  "UI-test gateway credential capture must occur during OpenKeyboardApp initialization"
)
require_text(
  app,
  "LiveAITestHarnessView(configuration: simulatorLiveAIConfiguration)",
  "the eagerly captured live configuration must be injected into the harness"
)
fail_policy("the harness must not lazily capture credentials in a static property") if harness.include?("static let configuration")
require_text(
  harness,
  "init(configuration: SimulatorLiveAIConfiguration?)",
  "the harness must receive its launch-captured configuration"
)

app_init = section(app, "    init() {", "    private var launchArguments")
ordered_positions(
  app_init,
  [
    "let arguments = ProcessInfo.processInfo.arguments",
    "SimulatorLiveAIConfiguration.capture(arguments: arguments)",
    "Self.captureUITestGatewayEnvironment(arguments: arguments)",
    "Self.clearStaleUITestKeyboardStateAtLaunchIfNeeded()"
  ],
  "credential capture and scrubbing must be the first launch bootstrap work"
)

app_capture = section(
  app,
  "    private static func captureUITestGatewayEnvironment(",
  "    private static func clearUITestConfigAtLaunchIfNeeded("
)
app_clear = section(
  app,
  "    private static func clearUITestConfigAtLaunchIfNeeded(",
  "    private static func isUITestConfigReplacementRequested("
)
harness_capture = section(
  harness,
  "    static func capture(arguments: [String]) -> SimulatorLiveAIConfiguration? {",
  "private enum LiveAITestHarnessError"
)

require_text(app_capture, "arguments.contains(\"--uitesting\")", "UI-test credential capture requires --uitesting")
require_text(app_capture, "arguments.contains(\"--seed-gateway-config\")", "UI-test credential capture requires a seed flag")
require_text(app_capture, "arguments.contains(\"--seed-functional-gateway-config\")", "functional seed capture requires its explicit flag")
require_text(app_clear, "!arguments.contains(\"--seed-gateway-config\")", "seeded launches must not pre-clear a complete profile")
require_text(app_clear, "!arguments.contains(\"--seed-functional-gateway-config\")", "functional seeded launches must not pre-clear a complete profile")
require_text(harness_capture, "arguments.contains(\"--uitesting\")", "live credential capture requires --uitesting")
require_text(harness_capture, "arguments.contains(\"--live-ai-test-harness\")", "live credential capture requires the harness flag")

[
  [app_capture, "return captured", "UI-test"],
  [harness_capture, "guard let captured", "live harness"]
].each do |capture, validation_boundary, label|
  ordered_positions(
    capture,
    [
      "let isAuthorized",
      "if isAuthorized",
      "ProcessInfo.processInfo.environment",
      "} else {",
      "captured = nil",
      "unsetenv($0)",
      validation_boundary
    ],
    "#{label} credentials must be read only after authorization and scrubbed before validation or return"
  )

  before_scrub = capture.split("unsetenv($0)", 2).first
  fail_policy("#{label} capture may not return before scrubbing") if before_scrub.match?(/\breturn\b/)
end

expected_keys = {
  app => %w[
    OPEN_KEYBOARD_TEST_API_KEY
    OPEN_KEYBOARD_TEST_GATEWAY_URL
    OPEN_KEYBOARD_TEST_MODEL
    OPEN_KEYBOARD_REPLACE_EXISTING_CONFIG
  ],
  harness => %w[
    OPEN_KEYBOARD_LIVE_GATEWAY_URL
    OPEN_KEYBOARD_LIVE_API_KEY
    OPEN_KEYBOARD_LIVE_MODEL
  ]
}
expected_keys.each do |source, keys|
  keys.each do |key|
    count = source.scan(%Q{"#{key}"}).length
    fail_policy("#{key} must appear exactly once in the scrub list and once at capture") unless count == 2
  end
  fail_policy("credential environment access must stay centralized in one capture function") unless source.scan("ProcessInfo.processInfo.environment").length == 1
end

configurations = project.to_enum(
  :scan,
  /[A-Z0-9]+ \/\* (Debug|Release) \*\/ = \{.*?\n\t\t\};/m
).map { Regexp.last_match }
assert_target_debug_release_conditions(
  configurations,
  "com.maneesh.openkeyboard",
  "app"
)
assert_target_debug_release_conditions(
  configurations,
  "com.maneesh.openkeyboard.keyboard",
  "keyboard extension"
)

puts "Simulator credential bootstrap policy tests passed."
RUBY
