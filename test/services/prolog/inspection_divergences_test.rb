require "minitest/autorun"
require "active_support/all"
require_relative "../../../app/services/prolog/inspections_client"
require_relative "../../../app/services/prolog/inspection_divergences"

class PrologInspectionDivergencesTest < Minitest::Test
  def record(id, date, depth, life: 1, tire: 10)
    { "id" => id, "submittedAt" => "2026-#{date}T12:00:00Z", "source" => "vehicles",
      "inspectionMeasures" => [{ "tireId" => tire, "tireLifeCycleAtInspection" => life,
        "measuredInnerTreadDepth" => depth }] }
  end

  def report(records)
    Prolog::InspectionDivergences.new(records, start_time: Time.utc(2026, 6, 24), end_time: Time.utc(2026, 9, 24))
  end

  def test_threshold_rounds_api_float_noise_and_keeps_small_increases
    result = report([record(1, "06-01", 4.5), record(2, "07-01", 5.0000001), record(3, "08-01", 5.51), record(4, "09-01", 5.52)])
    assert_equal [BigDecimal("0.51"), BigDecimal("0.50"), BigDecimal("0.01")], result.rows.map { |r| r[:delta] }
    assert_equal %w[medium low low], result.rows.map { |r| r[:severity] }
    assert_equal 3, result.inspection_count
    assert_equal 0, result.without_previous
  end

  def test_severity_boundaries_include_half_and_two_millimeters
    result = report([record(1, "06-01", 1), record(2, "07-01", 1.5), record(3, "08-01", 3.5), record(4, "09-01", 5.51)])
    assert_equal %w[high medium low], result.rows.map { |r| r[:severity] }
    assert_equal [BigDecimal("2.01"), BigDecimal("2.00"), BigDecimal("0.50")], result.rows.map { |r| r[:delta] }
  end

  def test_does_not_compare_across_retreads_or_tires
    result = report([record(1, "07-01", 2), record(2, "08-01", 12, life: 2), record(3, "09-01", 15, tire: 11)])
    assert_empty result.rows
    assert_equal 3, result.without_previous
  end

  def test_sorts_deduplicates_and_skips_missing_and_invalid_depths
    first = record(1, "06-01", 4.5)
    result = report([record(5, "09-01", 4.9), record(4, "08-01", -1), record(3, "07-20", "NaN"), record(2, "07-01", nil), first, first])
    assert_equal 1, result.rows.size
    assert_equal BigDecimal("0.4"), result.rows.first[:delta]
  end

  def test_decreases_and_equal_values_are_not_divergences
    assert_empty report([record(1, "07-01", 5), record(2, "08-01", 5), record(3, "09-01", 4)]).rows
  end

  def test_same_timestamp_does_not_create_artificial_increase
    assert_empty report([record(1, "07-01", 4), record(2, "07-01", 5), record(3, "08-01", 6)]).rows
  end
end
