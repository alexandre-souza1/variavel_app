require "minitest/autorun"
require "active_support/all"
require_relative "../../../app/services/prolog/inspections_client"
require_relative "../../../app/services/prolog/pressure_history"

class PrologPressureHistoryTest < Minitest::Test
  def reading(id, pressure, recommended: 115, life: 1, date: nil)
    { "id" => id, "source" => "vehicles", "submittedAt" => date || "2026-07-#{id.to_s.rjust(2, '0')}T12:00:00Z",
      "inspectionMeasures" => [{ "tireId" => 1, "tireLifeCycleAtInspection" => life, "measuredPressure" => pressure, "recommendedPressure" => recommended }] }
  end

  def report(records)
    Prolog::PressureHistory.new(records, start_time: Time.utc(2026, 7, 1), end_time: Time.utc(2026, 8, 1), reference_date: Date.new(2026, 9, 24))
  end

  def test_tracks_recurrence_normalization_and_pending_without_assuming_continuous_low_pressure
    rows = report([reading(1, 80), reading(2, 90), reading(3, 100), reading(4, 70)]).rows.reverse
    assert_equal %w[persisted normalized pending], rows.map { |r| r[:status] }
    assert_equal [1, 2, 1], rows.map { |r| r[:streak] }
  end

  def test_compares_each_measurement_with_its_own_recommendation
    rows = report([reading(1, 80), reading(2, 90, recommended: 90)]).rows
    assert_equal "normalized", rows.first[:status]
  end

  def test_missing_invalid_and_zero_recommendations_do_not_confirm_persistence
    [nil, -1, "NaN"].each do |pressure|
      result = report([reading(1, 80), reading(2, pressure)])
      assert_equal "unknown", result.rows.first[:status]
      assert_equal 1, result.unusable_count
    end
    assert_empty report([reading(1, 0, recommended: 0)]).rows
  end

  def test_retread_and_end_of_period_do_not_create_false_followups
    assert_equal "pending", report([reading(1, 80), reading(2, 80, life: 2)]).rows.last[:status]
    assert_equal "pending", report([reading(1, 80), reading(2, 100, date: "2026-08-02T12:00:00Z")]).rows.first[:status]
  end

  def test_exact_reference_limit_is_acceptable_but_below_it_is_low
    rows = report([reading(1, 99.99), reading(2, 100), reading(3, 110)]).rows
    assert_equal 1, rows.size
    assert_equal "normalized", rows.first[:status]
    assert_equal BigDecimal("100"), rows.first[:current][:minimum]
  end

  def test_threshold_scales_with_recommendation_without_rounding_the_ratio
    rows = report([reading(1, 89, recommended: 103.5), reading(2, 90, recommended: 103.5)]).rows
    assert_equal 1, rows.size
    assert_equal "normalized", rows.first[:status]
    assert_equal BigDecimal("90"), rows.first[:current][:minimum]
  end

  def test_latest_low_reading_distinguishes_current_month_from_previous_month
    previous_month = reading(1, 80, date: "2026-08-20T12:00:00Z")
    this_month = reading(2, 80, date: "2026-09-10T12:00:00Z")
    options = { start_time: Time.utc(2026, 7, 1), end_time: Time.utc(2026, 9, 24), reference_date: Date.new(2026, 9, 24) }
    assert_equal "awaiting_month", Prolog::PressureHistory.new([previous_month], **options).rows.first[:status]
    assert_equal "current_low", Prolog::PressureHistory.new([previous_month, this_month], **options).rows.first[:status]
    assert_equal "persisted", Prolog::PressureHistory.new([previous_month, this_month], **options).rows.last[:status]
  end

  def test_historical_range_does_not_claim_a_missing_current_month_inspection
    assert_equal "pending", report([reading(1, 80)]).rows.first[:status]
  end

  def test_baseline_and_deduplication
    prior = reading(1, 80, date: "2026-06-01T12:00:00Z")
    rows = report([reading(2, 90), prior, prior]).rows
    assert_equal 1, rows.size
    assert_equal 2, rows.first[:streak]
  end
end
