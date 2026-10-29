require 'test_helper'

class TimeOffMembershipTest < ActiveSupport::TestCase
  setup do
    @schedule = TimeOffSchedule.create!(name: 'AS com ajudante', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
  end

  test 'AS and Vespertina accept both fixed drivers and helpers with Saturday off' do
    %w[as vespertina].each do |operation|
      [{ driver: drivers(:one) }, { ajudante: ajudantes(:one) }].each do |person|
        member = @schedule.time_off_memberships.create!(attributes.merge(person, standard_operation: operation))
        assert_equal operation, member.reload.standard_operation
        assert_equal 'working', @schedule.base_status(member, Date.new(2026, 10, 2))
        assert_equal 'off', @schedule.base_status(member, Date.new(2026, 10, 3))
        assert_equal 'dsr', @schedule.base_status(member, Date.new(2026, 10, 4))
        member.destroy!
      end
    end
  end

  test 'fixed operations still require the fixed group and Saturday off' do
    [{ group_code: 'A' }, { fixed_weekday: 2 }, { fixed_weekday: nil }, { standard_operation: 'invalid' }].each do |invalid|
      member = @schedule.time_off_memberships.new(attributes.merge(ajudante: ajudantes(:one)).merge(invalid))
      refute member.valid?, invalid.inspect
      assert member.errors[:standard_operation].any?
      refute_includes member.errors.full_messages.join, 'exige motorista'
    end
  end

  test 'database accepts fixed AS helpers while rejecting invalid operation group and weekday' do
    member = @schedule.time_off_memberships.create!(attributes.merge(ajudante: ajudantes(:one)))
    [{ group_code: 'A' }, { fixed_weekday: 2 }, { standard_operation: 'invalid' }].each do |invalid|
      assert_raises(ActiveRecord::StatementInvalid) do
        TimeOffMembership.transaction(requires_new: true) { member.update_columns(invalid) }
      end
      assert_equal 'as', member.reload.standard_operation
      assert_equal 'FIXO', member.group_code
      assert_equal 6, member.fixed_weekday
    end
  end

  private

  def attributes
    { group_code: 'FIXO', fixed_weekday: 6, standard_operation: 'as', starts_on: '2026-10-01' }
  end
end
