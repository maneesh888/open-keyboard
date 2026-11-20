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
runtime_records = JSON.parse($stdin.read).fetch("runtimes")
raise TypeError, "runtimes must be an array" unless runtime_records.is_a?(Array)

runtimes = runtime_records.map do |runtime|
  raise TypeError, "runtime must be an object" unless runtime.is_a?(Hash)

  available = runtime.fetch("isAvailable")
  raise TypeError, "isAvailable must be boolean" unless available == true || available == false
  next unless available

  identifier = runtime.fetch("identifier")
  raise TypeError, "identifier must be a string" unless identifier.is_a?(String)
  next unless identifier.include?(".SimRuntime.iOS-")

  raw_version = runtime.fetch("version")
  raise TypeError, "version must be a string" unless raw_version.is_a?(String)

  version = numeric_version(raw_version)
  next unless version_at_most?(version, maximum_version)

  [version, identifier]
end.compact

runtimes.sort_by(&:first).reverse_each { |(_version, identifier)| puts identifier }
