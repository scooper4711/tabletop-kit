# frozen_string_literal: true

# Reads and splits the "Unreleased" section of an app's CHANGELOG.md, which is in the Keep a Changelog format.
# Specified in docs/specs/release-train (R6).

class ChangelogError < StandardError; end

# One CHANGELOG.md.
class Changelog
  UNRELEASED = '## [Unreleased]'
  NOTE_LIMIT = 4000

  def initialize(text)
    @lines = text.lines(chomp: true)
  end

  # The text under the Unreleased heading; empty when there is no such section.
  def unreleased
    section.join("\n").strip
  end

  # The Unreleased section as a What to Test note: plain text that ends on a whole line within TestFlight's limit.
  def note(limit: NOTE_LIMIT)
    plain = unreleased.gsub(/^### (.+)$/, '\1:')
    return plain if plain.length <= limit

    plain[0, limit].sub(/\n[^\n]*\z/, '')
  end

  # The changelog once a version is accepted. `shipped` is the Unreleased text of the accepted commit: it goes under
  # the version's own heading, and whatever merged after it stays under Unreleased.
  def release(version:, date:, shipped:, link:)
    first = heading_index || raise(ChangelogError, "CHANGELOG.md has no #{UNRELEASED} section")
    released = ["## [#{version}] - #{date}", '', shipped.strip, '', "[#{version}]: #{link}", '']
    rest = @lines[(first + 1 + section.length)..]
    "#{[*@lines[0...first], UNRELEASED, '', *left_after(shipped), *released, *rest].join("\n").rstrip}\n"
  end

  private

  def heading_index
    @lines.index { |line| line.strip == UNRELEASED }
  end

  # The lines between the Unreleased heading and the next version's heading.
  def section
    first = heading_index
    return [] unless first

    @lines[(first + 1)..].take_while { |line| !line.start_with?('## ') }
  end

  # The Unreleased lines that didn't ship, without the headings that have nothing left under them.
  def left_after(shipped)
    gone = entries(shipped.lines(chomp: true)).values.flatten
    kept = entries(section).transform_values { |list| list - gone }.reject { |_, list| list.empty? }
    kept.flat_map { |heading, list| [heading, *list].reject(&:empty?) + [''] }
  end

  # The entries under each "### " heading. An entry is a line and the indented lines that continue it.
  def entries(lines)
    groups = Hash.new { |hash, heading| hash[heading] = [] }
    heading = ''
    lines.reject { |line| line.strip.empty? }.each do |line|
      if line.start_with?('### ')
        heading = line
      elsif line.start_with?(' ', "\t") && groups[heading].any?
        groups[heading][-1] += "\n#{line}"
      else
        groups[heading] << line
      end
    end
    groups
  end
end
