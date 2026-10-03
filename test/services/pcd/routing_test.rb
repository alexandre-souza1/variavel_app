require 'test_helper'

class PcdRoutingTest < ActiveSupport::TestCase
  setup do
    @date = Date.new(2026, 10, 2)
    @schedule = TimeOffSchedule.create!(name: 'PCD', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    @dimensioning = FleetDimensioning.create!(label: 'PCD Outubro', start_date: '2026-10-01', end_date: '2026-10-31', route_quantity: 18, vespertina_quantity: 1, as_quantity: 1, van_quantity: 1)
    drivers(:one).update_columns(nome: 'ADAIR DE ALMEIDA', promax: '2')
    @member = @schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', starts_on: @date)
    @resting = @schedule.time_off_memberships.create!(driver: drivers(:two), group_code: 'E', starts_on: @date)
    @helper = @schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'A', starts_on: @date)
  end

  test 'report includes all freight and own routes with maps cities region and load data' do
    assert_no_difference(['PcdPlan.count', 'PcdImport.count', 'PcdChange.count', 'Plate.count', 'TimeOffOverride.count']) do
      preview = preview()
      assert_equal 23, preview[:source]['rows'].size
      assert_equal 6, preview[:source]['rows'].count { |r| r['freight'] }
      first = preview[:source]['rows'].first
      assert_equal '179795', first['maps'].first['number']
      assert_equal 'FORMOSA DO OESTE (1)', first['maps'].first['cities']
      assert_equal '[FOR]: CENTRO (1)', first['maps'].first['region']
      assert_equal '103,18', first['maps'].first['boxes']
      assert_equal 23, preview[:cars].count { |c| c['maps'].any? }
      adair = preview[:cars].find { |c| c['plate'] == 'QJU2428' }
      assert_equal "driver:#{drivers(:one).id}", adair['driver']
      assert_equal 'room1', adair['room']
      assert_equal '07:00', adair['departure_time']
      assert preview[:cars].select { |c| c['freight'] }.all? { |c| c['room'] == 'spot' && c['departure_time'] == '06:00' }
    end
  end

  test 'save archives every import preserves manual changes and never changes employee days off' do
    preview = preview()
    cars = preview[:cars]
    truck = cars.find { |c| c['plate'] == 'QJU2428' }
    replacement = Plate.create!(placa: 'AAA1B23', setor: 'ROTA', tipo: 'Caminhão')
    truck.merge!('plate' => replacement.placa, 'room' => 'room2', 'departure_time' => '09:15', 'helper_count' => 2, 'helper1' => "helper:#{ajudantes(:one).id}", 'notes' => 'Ajuste do supervisor')
    cars.each { |c| c['helper1'] = nil if c != truck }
    cancelled = cars.find { |c| c['maps'].any? { |m| m['number'] == '179819' } }
    cancelled['scheduled'] = false
    Pcd::Board::ROLES.each { |role| cancelled[role] = nil }
    assert_no_difference(['TimeOffDailyPlan.count', 'TimeOffOverride.count', 'TimeOffChange.count', 'Plate.count']) do
      assert_difference(['PcdPlan.count', 'PcdImport.count', 'PcdChange.count'], 1) { save(cars, preview[:token]) }
    end
    plan = PcdPlan.find_by!(date: @date)
    assert_equal 6, plan.pcd_imports.first.details['freight']
    fresh = preview()
    preserved = fresh[:cars].find { |c| c['maps'].any? { |m| m['number'] == '179810' } }
    assert_equal replacement.placa, preserved['plate']
    assert_equal '09:15', preserved['departure_time']
    assert_equal 2, preserved['helper_count']
    refute fresh[:cars].find { |c| c['key'] == cancelled['key'] }['scheduled']
    assert_difference(['PcdImport.count', 'PcdChange.count'], 1) { save(fresh[:cars], fresh[:token]) }
    assert_equal 1, PcdPlan.where(date: @date).count
    assert_equal 23, PcdPlan.find_by!(date: @date).details['cars'].count { |c| c['maps'].any? }
    assert_equal 18, @dimensioning.reload.route_quantity
    assert_nil Pcd::Board.new(date: @date + 3).plan
    assert_equal 21, Pcd::Board.new(date: @date + 3).metrics[:own]
  end

  test 'expired forged wrong date tokens and stale edits fail atomically' do
    result = preview
    assert_no_difference(['PcdPlan.count', 'PcdImport.count', 'PcdChange.count']) do
      assert_raises(TimeOff::UpdateDay::InvalidChange) { save(result[:cars], 'forjado') }
      assert_raises(TimeOff::UpdateDay::InvalidChange) { Pcd::RoutingCsv.verify(result[:token], date: @date + 1) }
      travel 5.hours do
        assert_raises(TimeOff::UpdateDay::InvalidChange) { save(result[:cars], result[:token]) }
      end
    end
    save(result[:cars], result[:token])
    assert_no_difference('PcdChange.count') do
      assert_raises(TimeOff::UpdateDay::Conflict) { save(result[:cars], result[:token], revision: -1) }
    end
  end

  test 'off vacation inactive and duplicated employees and plates cannot be assigned' do
    result = preview
    cars = result[:cars]
    routes = cars.select { |c| c['scheduled'] && !c['freight'] }
    routes[0]['driver'] = "driver:#{drivers(:two).id}"
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, result[:token]) }
    routes[0]['driver'] = nil
    routes[0]['helper1'] = "driver:#{drivers(:one).id}"
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, result[:token]) }
    routes[0]['helper1'] = nil
    routes[0]['plate'] = routes[1]['plate']
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(cars, result[:token]) }
    result = preview
    drivers(:one).update!(active: false)
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(result[:cars], result[:token]) }
    drivers(:one).update!(active: true)
    TimeOff::UpdateVacation.create(schedule: @schedule, membership_id: @member.id, starts_on: @date, ends_on: @date + 1, reason: 'Férias', user: users(:one))
    assert_raises(TimeOff::UpdateDay::InvalidChange) { save(result[:cars], result[:token]) }
  end

  test 'wrong day and conflicting repeated maps reject preview without writes' do
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview(date: @date + 1) }
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview(file: upload('')) }
    header = "Data Entrega;Nro do Mapa;AS / Rota;Placa;Carga;Cidades +Entregas;Região +Entregas\n"
    a = "02/10/2026;123;AS;AAA1B23;Freteiro;FOZ;CENTRO\n"
    assert_equal 1, preview(file: upload(header + a + a))[:source]['duplicates']
    assert_raises(TimeOff::UpdateDay::InvalidChange) { preview(file: upload(header + a + a.sub('CENTRO', 'PORTES'))) }
    multi = preview(file: upload(header + a + a.sub(';123;', ';124;')))
    assert_equal 1, multi[:source]['rows'].size
    assert_equal 2, multi[:source]['rows'].first['maps'].size
  end

  test 'PCD works without pilot setup and does not create or change RH records' do
    TimeOffMembership.where(time_off_schedule: @schedule).delete_all
    @schedule.reload.destroy!
    assert_no_difference(['TimeOffSchedule.count', 'TimeOffMembership.count', 'Driver.count', 'Ajudante.count']) do
      result = preview
      assert_equal 23, result[:source]['rows'].size
      save(result[:cars], result[:token])
    end
  end

  private

  def upload(text)
    Struct.new(:original_filename, :io) { def read(length) = io.read(length) }.new('rotas.csv', StringIO.new(text))
  end
  def preview(file: nil, date: @date)
    file ||= Rack::Test::UploadedFile.new(Rails.root.join('test/fixtures/files/pcd_routing.csv'), 'text/csv')
    Pcd::RoutingCsv.new(file: file, board: Pcd::Board.new(date: date)).preview
  end
  def save(cars, token = nil, revision: nil)
    revision = PcdPlan.find_by(date: @date)&.lock_version || -1 if revision.nil?
    Pcd::Save.call(date: @date, user: users(:one), attributes: { reason: 'Conferência da roteirização', expected_revision: revision, routing_token: token, cars: cars })
  end
end
