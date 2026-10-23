require "test_helper"

class FleetAvailabilities::MaintenanceSupplierCopyTest < ActiveSupport::TestCase
  setup do
    @source = fleet_availabilities(:two)
    @supplier = Supplier.create!(name: "Oficina de continuidade", cnpj: "12345678000193", supplier_type: "workshop")
    @item = fleet_availability_items(:two)
    @item.update!(status: :unavailable, reason: :maintenance, observation: "Na oficina", supplier: @supplier)
  end

  test "all creation paths preserve the supplier of unavailable vehicles" do
    [ { copy_from: @source }, { copy_previous_day: true }, {} ].each_with_index do |options, index|
      # Each new day becomes the source for the next one.
      availability = FleetAvailabilities::Creator.call(
        user: users(:one), date: @source.date + index + 1,
        agreed_quantity: index == 2 ? 1 : 2, **options
      )
      copy = availability.fleet_availability_items.find_by!(plate_id: @item.plate_id)
      assert_predicate copy, :unavailable?
      assert_equal @supplier.id, copy.supplier_id
      assert_equal "Na oficina", copy.observation
    end
  end
end
