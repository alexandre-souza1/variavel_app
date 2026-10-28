require "test_helper"

class Prolog::InspectionScheduleTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 10, 27, 12) }
  teardown { travel_back }

  test "uses thirty calendar days with inclusive due date and seven day warning" do
    plates = (1..7).map { |i| Plate.new(placa: "ABC1D2#{i}") }
    days_ago = [45, 31, 30, 29, 23, 22, 0]
    records = plates.zip(days_ago).map { |plate, days| inspection(plate.placa, (Time.current - days.days).iso8601) }
    report = Prolog::InspectionSchedule.new(plates, records)
    assert_equal %w[overdue overdue today soon soon ok ok], report.rows.map { |r| r[:status] }
    assert_equal [-15, -1, 0, 1, 7, 8, 30], report.rows.map { |r| r[:days_left] }
    assert_equal Date.current, report.rows[2][:due_date]
  end

  test "latest valid vehicle tread inspection wins across equivalent plates" do
    records = [inspection("ABC1323", "2026-10-01T12:00:00Z"),
      inspection(" abc-1d23 ", "2026-10-10T12:00:00Z"),
      inspection("ABC1D23", "2026-10-26T12:00:00Z", type: "PRESSURE"),
      inspection("ABC1D23", "2026-10-25T12:00:00Z").merge("source" => "individual-tire"),
      inspection("ABC1D23", "2026-10-28T12:00:00Z"), inspection("ABC1D23", "invalid"),
      inspection("ZZZ9Z99", "2026-10-27T12:00:00Z")]
    row = Prolog::InspectionSchedule.new([Plate.new(placa: "ABC1D23")], records.reverse).rows.first
    assert_equal Date.new(2026, 10, 10), row[:last_date]
    assert_equal Date.new(2026, 11, 9), row[:due_date]
    assert_equal "ok", row[:status]
  end

  test "uses Brasilia date at UTC midnight and does not treat missing history as compliant" do
    plates = [Plate.new(placa: "ABC1D23"), Plate.new(placa: "DEF4G56")]
    rows = Prolog::InspectionSchedule.new(plates, [inspection("ABC1D23", "2026-09-28T01:00:00Z")]).rows
    assert_equal "today", rows.first[:status]
    assert_equal Date.new(2026, 9, 27), rows.first[:last_date]
    assert_equal "missing", rows.last[:status]
    assert_nil rows.last[:due_date]
  end

  private

  def inspection(plate, date, type: "TREAD_DEPTH")
    { "submittedAt" => date, "typeMeasurementsCollected" => type, "source" => "vehicles", "vehicle" => { "licensePlate" => plate } }
  end
end
