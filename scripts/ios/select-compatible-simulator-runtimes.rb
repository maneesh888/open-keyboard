#!/usr/bin/env ruby

require "json"

def numeric_version(raw)
  parts = raw.split(".", -1)
  raise ArgumentError, "invalid numeric version" if parts.empty? || parts.any? { |part| !part.match?(/\A\d+\z/) }

  parts.map { |part| Integer(part, 10) }
end

def version_at_most?(candidate, maximum)
  width = [candidate.length, maximum.length].max
  normalized_candidate = candidate + Array.new(width - candidate.length, 0)
  normalized_maximum = maximum + Array.new(width - maximum.length, 0)
  (normalized_candidate <=> normalized_maximum) <= 0
end

maximum_version = numeric_version(ARGV.fetch(0))
runtimes = JSON.parse($stdin.read).fetch("runtimes").map do |runtime|
  next unless runtime["isAvailable"]
  next unless runtime.fetch("identifier").include?(".SimRuntime.iOS-")

  version = numeric_version(runtime.fetch("version"))
  next unless version_at_most?(version, maximum_version)

  [version, runtime.fetch("identifier")]
end.compact

runtimes.sort_by(&:first).reverse_each { |(_version, identifier)| puts identifier }
