#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks changelog.rb against docs/specs/release-train R6.

require 'minitest/autorun'
require_relative 'changelog'

class ChangelogTest < Minitest::Test
  TEXT = <<~CHANGELOG
    # Changelog

    ## [Unreleased]

    ### Added
    - Dice
    - Maps, which now
      fold in two

    ### Fixed
    - A crash

    ## [1.1.0] - 2026-01-01

    ### Fixed
    - Old

    [1.1.0]: https://example.invalid/v1.1.0
  CHANGELOG
  SHIPPED = "### Added\n- Dice\n\n### Fixed\n- A crash"
  LINK = 'https://example.invalid/v1.2.0'

  def released(text = TEXT, shipped = SHIPPED)
    Changelog.new(text).release(version: '1.2.0', date: '2026-02-03', shipped: shipped, link: LINK)
  end

  def test_reads_the_unreleased_section_without_its_heading
    unreleased = Changelog.new(TEXT).unreleased
    assert unreleased.start_with?("### Added\n- Dice")
    assert unreleased.end_with?('- A crash')
  end

  def test_no_section_reads_as_empty
    assert_equal '', Changelog.new("# Changelog\n\n## [1.1.0] - 2026-01-01\n").unreleased
  end

  def test_the_note_is_plain_text
    assert_equal "Added:\n- Dice", Changelog.new("## [Unreleased]\n\n### Added\n- Dice\n").note
  end

  def test_a_long_note_ends_on_a_whole_line_within_the_limit
    note = Changelog.new("## [Unreleased]\n\n- first line\n- second line\n").note(limit: 20)
    assert_equal '- first line', note
  end

  def test_shipped_entries_move_under_the_version
    section = released[/## \[1\.2\.0\].*?(?=## \[1\.1\.0\])/m]
    assert_equal "## [1.2.0] - 2026-02-03\n\n#{SHIPPED}\n\n[1.2.0]: #{LINK}\n\n", section
  end

  def test_entries_merged_since_stay_unreleased
    section = released[/## \[Unreleased\].*?(?=## \[1\.2\.0\])/m]
    assert_equal "## [Unreleased]\n\n### Added\n- Maps, which now\n  fold in two\n\n", section
  end

  def test_nothing_merged_since_leaves_the_section_empty
    text = released(TEXT, Changelog.new(TEXT).unreleased)
    assert_includes text, "## [Unreleased]\n\n## [1.2.0] - 2026-02-03\n"
  end

  def test_older_versions_and_the_ending_are_kept
    ending = "## [1.1.0] - 2026-01-01\n\n### Fixed\n- Old\n\n[1.1.0]: https://example.invalid/v1.1.0\n"
    assert released.end_with?(ending)
    assert released.start_with?("# Changelog\n\n## [Unreleased]\n")
  end

  def test_a_changelog_without_the_section_is_refused
    assert_raises(ChangelogError) { released("# Changelog\n") }
  end
end
