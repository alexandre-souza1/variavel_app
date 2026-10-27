require "test_helper"
require "minitest/mock"

class FleetMaintenanceSuppliersTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 7, 20, 7)
    @availability = fleet_availabilities(:one)
    @item = fleet_availability_items(:one)
    @item.update!(position: 0, reason: nil)
    @item.plate.update!(placa: "ABC1D23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    @workshop = Supplier.create!(name: "Oficina Central", cnpj: "12345678000190", supplier_type: "workshop")
    @tire_shop = Supplier.create!(name: "Borracharia Central", cnpj: "12345678000191", supplier_type: "tire_shop")
    @store = Supplier.create!(name: "Loja Central", cnpj: "12345678000192", supplier_type: "store")
  end

  teardown { travel_back }

  test "assigns and changes maintenance supplier with history and preserves it when editing observation" do
    change_item(supplier_id: @workshop.id)
    assert_response :success
    assert_equal @workshop.id, @item.reload.supplier_id
    assert_equal @workshop.name, response.parsed_body["supplier_name"]
    assert_equal @workshop.id, @item.fleet_availability_changes.order(:id).last.supplier_id

    change_item(observation: "Aguardando peça")
    assert_response :success
    assert_equal @workshop.id, @item.reload.supplier_id

    assert_difference "FleetAvailabilityChange.count", 1 do
      change_item(supplier_id: @tire_shop.id)
    end
    assert_response :success
    assert_equal @tire_shop.id, @item.reload.supplier_id
    assert_equal @tire_shop.id, @item.fleet_availability_changes.order(:id).last.supplier_id
  end

  test "rejects stores and unknown suppliers without changing the vehicle or history" do
    [@store.id, Supplier.maximum(:id) + 1].each do |supplier_id|
      assert_no_difference "FleetAvailabilityChange.count" do
        change_item(supplier_id: supplier_id)
      end
      assert_response :unprocessable_entity
      assert_predicate @item.reload, :exchange?
      assert_nil @item.supplier_id
    end
  end

  test "supplier is optional and can be removed or cleared when the vehicle returns" do
    change_item
    assert_response :success
    assert_nil @item.reload.supplier_id

    change_item(supplier_id: @workshop.id)
    change_item(supplier_id: "")
    assert_response :success
    assert_nil @item.reload.supplier_id

    change_item(supplier_id: @workshop.id)
    change_item(status: "available", reason: nil)
    assert_response :success
    assert_predicate @item.reload, :available?
    assert_nil @item.supplier_id
  end

  test "changing supplier type preserves existing assignment but prevents new maintenance assignments" do
    change_item(supplier_id: @workshop.id)
    @workshop.update!(supplier_type: "contractor")
    change_item(observation: "Manter oficina já informada")
    assert_response :success
    assert_equal @workshop.id, @item.reload.supplier_id
    get_availability
    assert_select "[data-supplier-label]", text: /Oficina Central/

    change_item(supplier_id: "")
    change_item(supplier_id: @workshop.id)
    assert_response :unprocessable_entity
  end

  test "only workshops and tire shops are offered and supplier appears on read only cards and PDF" do
    @tire_shop.update!(fantasy_name: "Borracharia São João")
    change_item(supplier_id: @tire_shop.id)
    get_availability
    assert_select "#unavailableSupplier option[value='#{@workshop.id}']", count: 1
    assert_select "#unavailableSupplier option[value='#{@tire_shop.id}']", count: 1
    assert_select "#unavailableSupplier option[value='#{@store.id}']", count: 0
    assert_select "#unavailableSupplier option[value='#{@tire_shop.id}']", text: /Borracharia São João/
    assert_select "[data-supplier-label]", text: "Borracharia São João"
    assert_select "[data-unavailable-edit]", count: 1

    @availability.lock_availability!(users(:one))
    get_availability
    assert_select "[data-supplier-label]", text: "Borracharia São João"
    assert_select "[data-unavailable-edit]", count: 0
    assert_select "#unavailableSupplier", count: 0

    pdf = FleetAvailabilityPdf.new(@availability)
    pdf_text = pdf.state.pages.map { |page| page.content.stream.filtered_stream }
                  .join.scan(/<([0-9a-f]+)>/i).flatten.map { |hex| [hex].pack("H*") }.join
                  .force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
    assert_includes pdf_text.gsub(/\s+/, ""), "BorrachariaSãoJoão"

    change_item(supplier_id: @workshop.id)
    assert_response :forbidden
    assert_equal @tire_shop.id, @item.reload.supplier_id
  end

  test "fleet API prefers fantasy name and falls back to legal name for empty fantasy names" do
    [nil, "", "  "].each do |fantasy_name|
      @workshop.update!(fantasy_name: fantasy_name)
      change_item(supplier_id: @workshop.id)
      assert_response :success
      assert_equal @workshop.name, response.parsed_body["supplier_name"]
    end

    @workshop.update!(fantasy_name: "  Oficina do Centro  ")
    change_item(supplier_id: @workshop.id)
    assert_response :success
    assert_equal "Oficina do Centro", response.parsed_body["supplier_name"]
  end

  test "CNPJ lookup returns the fantasy name provided by ReceitaWS" do
    api_response = Struct.new(:code, :body).new(200, {
      nome: "Oficina Central LTDA", fantasia: "Oficina do Centro", cnpj: "12.345.678/0001-90"
    }.to_json)
    HTTParty.stub(:get, api_response) do
      get "/suppliers/search_cnpj", params: { cnpj: "12345678000190" }
    end
    assert_response :success
    assert_equal "Oficina Central LTDA", response.parsed_body["name"]
    assert_equal "Oficina do Centro", response.parsed_body["fantasy_name"]
  end

  test "supplier types are saved and displayed and linked suppliers cannot be deleted" do
    Supplier::TYPES.each do |type, label|
      patch supplier_path(@store), params: { supplier: { supplier_type: type } }
      assert_redirected_to suppliers_path
      assert_equal type, @store.reload.supplier_type
      get edit_supplier_path(@store)
      assert_response :success
      assert_select "select[name='supplier[supplier_type]'] option[selected][value='#{type}']", text: label
    end

    get suppliers_path
    assert_response :success
    assert_select "th", text: "Tipo"
    change_item(supplier_id: @workshop.id)
    change_item(status: "exchange")
    assert_no_difference "Supplier.count" do
      delete supplier_path(@workshop)
    end
    assert_redirected_to suppliers_path
    assert_match /não pode ser excluído/, flash[:alert]
  end

  private

  def change_item(**attributes)
    patch fleet_availability_fleet_availability_item_path(@availability, @item),
          params: { fleet_availability_item: { status: "unavailable", position: 0, reason: "maintenance" }.merge(attributes) },
          as: :json
  end

  def get_availability
    client = Struct.new(:tire_summary_by_plate, :error).new({}, nil)
    Prolog::TiresClient.stub(:new, client) { get fleet_availability_path(@availability) }
    assert_response :success
  end
end
