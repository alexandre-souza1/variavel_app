require 'test_helper'

class TimeOffCoverageTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'Cobertura', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @dimensioning = FleetDimensioning.create!(label: 'Outubro', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 18, vespertina_quantity: 1, as_quantity: 1, van_quantity: 1)
    @drivers = [drivers(:one), drivers(:two)].map { |p| @schedule.time_off_memberships.create!(driver: p, group_code: 'A', starts_on: @schedule.starts_on) }
    @helpers = [ajudantes(:one), ajudantes(:two)].map { |p| @schedule.time_off_memberships.create!(ajudante: p, group_code: 'A', starts_on: @schedule.starts_on) }
    @van = fixed('Ademar', 'van')
    @vespertina_driver = fixed('André', 'motorista', 'vespertina')
    @vespertina_helper = fixed('Alberto', 'ajudante', 'vespertina')
    @as_driver = fixed('Keberson', 'motorista', 'as')
  end

  test 'dimensioning supplies all own operations and fixed people do not inflate route availability' do
    coverage = report
    assert_equal({ 'route' => 18, 'vespertina' => 1, 'as' => 1, 'van' => 1 }, coverage.quantities)
    assert_equal 21, coverage.rows.sum { |r| r[:demand] }
    assert_equal 2, row('route')[:drivers]
    assert_equal 2, row('route')[:helpers]
    assert_equal 18, row('route')[:helper_need]
    %w[vespertina as van].each { |op| assert_equal 1, row(op)[:drivers] }
    assert_equal 1, row('vespertina')[:helpers]
    assert_equal 0, row('as')[:helper_need]
    assert_equal 0, row('van')[:helper_need]
    assert_equal [@van.id], coverage.assignments['van']['driver'].map(&:id)
  end

  test 'Saturday only counts standard routes and Sunday is DSR' do
    saturday = report(Date.new(2026, 10, 3))
    assert_equal 18, saturday.rows.sum { |r| r[:demand] }
    assert_equal 0, saturday.rows.reject { |r| r[:operation] == 'route' }.sum { |r| r[:drivers] + r[:helper_need] }
    sunday = report(Date.new(2026, 10, 4))
    assert_equal 0, sunday.rows.sum { |r| r[:demand] }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save({}, date: Date.new(2026, 10, 4)) }
  end

  test 'missing dimensioning is unknown and a later period uses its own quantities' do
    assert_nil report(Date.new(2026, 11, 2)).dimensioning
    assert_not report(Date.new(2026, 11, 2)).editable?
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save({}, date: Date.new(2026, 11, 2)) }
    FleetDimensioning.create!(label: 'Novembro', start_date: '2026-11-01', end_date: '2026-11-30', route_quantity: 12, vespertina_quantity: 2, as_quantity: 0, van_quantity: 1)
    assert_equal 15, report(Date.new(2026, 11, 2)).rows.sum { |r| r[:demand] }
  end

  test 'solo and double helper departures are valid and acting driver is counted only as helper' do
    assert_difference('TimeOffChange.count', 1) do
      save('solo_routes' => 2, 'double_helper_routes' => 3, 'helper_driver_ids' => [@drivers.first.id])
    end
    assert_equal 19, row('route')[:helper_need]
    assert_equal 3, row('route')[:helpers]
    assert_equal 1, row('route')[:drivers]
    change = @schedule.time_off_changes.last
    assert_nil change.time_off_membership
    assert_equal users(:one), change.user
    assert_includes change.details['summary'], 'Ademar'
    assert_equal 'Composição autorizada pelo gestor', change.details['reason']
  end

  test 'composition cannot exceed number of departures and rejected edits leave no record' do
    assert_no_difference(['TimeOffDailyPlan.count', 'TimeOffChange.count']) do
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save('solo_routes' => 17, 'double_helper_routes' => 2) }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save('solo_routes' => -1) }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save('solo_routes' => '1.5') }
    end
  end

  test 'van eligibility uses dated career and other drivers cannot cover it' do
    assert_raises(TimeOff::UpdateDay::InvalidChange) do
      save('special_assignments' => { 'van' => { 'driver' => [@drivers.first.id] } })
    end
    @van.driver.employee.change_role!({ cargo: 'motorista', promax: @van.driver.promax, starts_on: '2026-10-16', reason: 'Progressão de cargo' }, user: users(:one))
    assert_equal 1, row('van')[:drivers]
    assert_equal 0, row('van', date: Date.new(2026, 10, 16))[:drivers]
    assert_equal 'van', @van.reload.cargo_on(@date)
  end

  test 'fixed absence opens its operation and replacement is reserved from standard routes' do
    mark(@vespertina_driver, 'unavailable')
    assert_equal 1, row('vespertina')[:driver_gap]
    assert_equal 2, row('route')[:drivers]
    assert report.warnings.any? { |message| message.include?('André') }
    save('special_assignments' => { 'vespertina' => { 'driver' => [@drivers.first.id], 'helper' => [@vespertina_helper.id] } })
    assert_equal 0, row('vespertina')[:driver_gap]
    assert_equal 1, row('route')[:drivers]
  end

  test 'absence after saving exceptional helper keeps alert without counting unavailable person' do
    save('helper_driver_ids' => [@drivers.first.id])
    mark(@drivers.first, 'unavailable')
    assert_equal 2, row('route')[:helpers]
    assert_equal 1, row('route')[:drivers]
    assert report.warnings.any? { |message| message.include?('atuação como ajudante') }
  end

  test 'rejects repeated people in fixed positions and exceptional helper selections' do
    assert_no_difference('TimeOffDailyPlan.count') do
      assert_raises(TimeOff::UpdateDay::InvalidChange) do
        save('special_assignments' => { 'as' => { 'driver' => [@vespertina_driver.id] } })
      end
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save('helper_driver_ids' => [@as_driver.id]) }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save('helper_driver_ids' => [@drivers.first.id, @drivers.first.id]) }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save('helper_driver_ids' => [@helpers.first.id]) }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save('helper_driver_ids' => [999999]) }
    end
  end

  test 'old revision and changed dimensioning cannot overwrite coverage' do
    plan = save('solo_routes' => 1)
    assert_raises(TimeOff::UpdateDay::Conflict) { save({ 'solo_routes' => 2 }, revision: -1) }
    signature = report.signature
    @dimensioning.update!(route_quantity: 16)
    assert report.stale?
    assert_raises(TimeOff::UpdateDay::Conflict) { save({ 'solo_routes' => 2, 'dimensioning_signature' => signature }) }
    assert_equal 1, plan.reload.details['solo_routes']
    save('solo_routes' => 2)
    assert_not report.stale?
  end

  test 'future daily choice survives a dated group transfer and old dates retain old operation' do
    date = Date.new(2026, 10, 9)
    save({ 'helper_driver_ids' => [@drivers.first.id] }, date: date)
    next_member = TimeOff::AssignGroup.call(schedule: @schedule, person: @drivers.first.person, group_code: 'B', starts_on: Date.new(2026, 10, 5), user: users(:one))
    assert_equal [next_member.id], report(date).helper_drivers.map(&:id)
    assert_equal 1, row('route', date: date)[:drivers]
    updated = TimeOff::AssignGroup.call(schedule: @schedule, person: @as_driver.person, group_code: 'FIXO', fixed_weekday: 6, standard_operation: 'vespertina', starts_on: Date.new(2026, 10, 5), user: users(:one))
    assert_equal 'as', @as_driver.reload.standard_operation
    assert_equal 'vespertina', updated.standard_operation
    assert_equal [@as_driver.id], report.assignments['as']['driver'].map(&:id)
    assert_nil report(date).assignments['as']['driver'].first
  end

  test 'same employee cannot be enrolled twice through driver and helper records' do
    helper_record = Ajudante.create!(employee: @as_driver.person.employee, nome: 'Cadastro legado', matricula: 'legado', promax: 'legado')
    duplicate = @schedule.time_off_memberships.new(ajudante: helper_record, group_code: 'A', starts_on: @schedule.starts_on)
    assert_not duplicate.valid?
    assert_includes duplicate.errors.full_messages.join, 'já pertence a um grupo'
  end

  private

  def report(date = @date)
    TimeOff::Coverage.new(schedule: @schedule, date: date)
  end

  def row(operation, date: @date)
    report(date).rows.find { |r| r[:operation] == operation }
  end

  def save(overrides = {}, date: @date, revision: nil, **options)
    overrides = overrides.merge(options)
    coverage = report(date)
    TimeOff::UpdateCoverage.call(schedule: @schedule, date: date, user: users(:one), attributes: {
      'solo_routes' => 0, 'double_helper_routes' => 0, 'helper_driver_ids' => [],
      'special_assignments' => {}, 'reason' => 'Composição autorizada pelo gestor',
      'expected_revision' => revision || coverage.plan&.lock_version || -1,
      'dimensioning_signature' => coverage.signature
    }.merge(overrides))
  end

  def fixed(name, cargo, operation = nil)
    employee = Employee.create!(nome: name, matricula: "coverage-#{name}")
    employee.employee_roles.create!(cargo: cargo, promax: "coverage-#{name}", starts_on: '2026-10-01', reason: 'Cadastro de teste')
    klass = cargo == 'ajudante' ? Ajudante : Driver
    person = klass.create!(employee: employee, nome: name, matricula: employee.matricula, promax: "coverage-#{name}")
    @schedule.time_off_memberships.create!(person.is_a?(Driver) ? { driver: person, group_code: 'FIXO', fixed_weekday: 6, standard_operation: operation, starts_on: @schedule.starts_on } : { ajudante: person, group_code: 'FIXO', fixed_weekday: 6, standard_operation: operation, starts_on: @schedule.starts_on })
  end

  def mark(member, status)
    TimeOff::UpdateDay.call(schedule: @schedule, membership_id: member.id, date: @date, status: status, reason: 'Atestado', expected_revision: -1, user: users(:one))
  end
end
