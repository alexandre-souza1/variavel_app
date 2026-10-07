require "test_helper"
require "minitest/mock"

class NavigationJourneysTest < ActionDispatch::IntegrationTest
  test "home links bypass sector redirects on desktop and mobile" do
    %i[fleet du warehouse].each do |sector|
      users(:one).update!(role: :user, sector: sector)
      get variaveis_path
      assert_response :success
      assert_select "a.navbar-brand[href=?][aria-label=?]", variaveis_path, "Workstation — Início"
      assert_select "a.user-name[href=?]", root_path
    end
  end

  test "checklist history returns to checklists and no longer offers a misleading report link" do
    get checklists_path
    assert_response :success
    assert_select "a[href=?]", historic_checklists_path, text: "Histórico de Checklists", count: 1
    assert_select "a", text: "Relatório de Checklists", count: 0
    get historic_checklists_path
    assert_response :success
    assert_select "a[href=?]", checklists_path, text: "Voltar para checklists"
  end

  test "editing a plan returns to that plan" do
    get edit_action_plan_path(action_plans(:one))
    assert_response :success
    assert_select "a[href=?]", action_plan_path(action_plans(:one)), text: "Cancelar"
    assert_select "a[href=?]", action_plan_path(action_plans(:one)), text: /Voltar ao plano/
  end

  test "invoice detail and edit preserve list filters through save" do
    invoice = create_invoice
    destination = invoices_path(supplier_name: "Fornecedor de navegação", page: 2, per_page: 15, sector: "FROTA")
    get invoice_path(invoice), params: { return_to: destination }
    assert_response :success
    assert_select "a.az-report-back-link[href=?]", destination
    assert_select "a[href=?]", edit_invoice_path(invoice, return_to: destination)

    get edit_invoice_path(invoice), params: { return_to: destination }
    assert_response :success
    assert_select "input[name=return_to][value=?]", destination
    assert_select "a[href=?]", invoice_path(invoice, return_to: destination), text: "Cancelar"

    patch invoice_path(invoice), params: { return_to: destination, invoice: { code: "NF-ALTERADA" } }
    assert_response :see_other
    assert_redirected_to invoice_path(invoice, return_to: destination)
    follow_redirect!
    assert_select "a.az-report-back-link[href=?]", destination
  end

  test "invoice links from the list carry the current filters" do
    invoice = create_invoice
    destination = invoices_path(supplier_name: invoice.supplier.name, per_page: 15)
    get destination
    assert_response :success
    assert_select "a[href=?]", invoice_path(invoice, return_to: destination), minimum: 1
    assert_select "a[href=?]", edit_invoice_path(invoice, return_to: destination)
    assert_select "a[href=?]", new_invoice_path(return_to: destination)
  end

  test "new invoice validation keeps the return destination and creation works without attachments" do
    invoice = create_invoice
    destination = invoices_path(page: 2)
    get new_invoice_path, params: { return_to: destination }
    assert_select "a[href=?]", destination, text: "Cancelar"
    post invoices_path, params: { return_to: destination, invoice: { code: "" } }
    assert_response :unprocessable_entity
    assert_select "input[name=return_to][value=?]", destination

    attributes = invoice.attributes.slice("supplier_id", "purchaser_id", "budget_category_id", "date_issued", "due_date")
    post invoices_path, params: { return_to: destination, invoice: attributes.merge(code: "NF-NOVA") }
    assert_response :see_other
    assert_redirected_to invoice_path(Invoice.find_by!(code: "NF-NOVA"), return_to: destination)
  end

  test "invoice deletion returns to the filtered list" do
    invoice = create_invoice
    destination = invoices_path(page: 2, sector: "FROTA")
    delete invoice_path(invoice), params: { return_to: destination }
    assert_response :see_other
    assert_redirected_to destination
  end

  test "invoice dashboard return keeps the selected period" do
    invoice = create_invoice
    destination = dashboard_invoices_path(month: 7, year: 2026, sector: "FROTA")
    get invoice_path(invoice), params: { return_to: destination }
    assert_select "a.az-report-back-link[href=?]", destination, text: /Voltar ao dashboard/
  end

  test "invoice return rejects external URLs and unrelated or malformed routes" do
    invoice = create_invoice
    ["https://example.com", "//example.com/invoices", "/\\example.com", "/invoices/%ZZ",
      invoice_path(invoice), "/users/sign_out", { url: invoices_path }].each do |destination|
      get invoice_path(invoice), params: { return_to: destination }
      assert_response :success
      assert_select "a.az-report-back-link[href=?]", invoices_path
    end
  end

  test "fleet detail returns to the record period even when opened directly" do
    period = create_fleet_period
    client = Struct.new(:tread_depth_by_plate).new({})
    Prolog::TiresClient.stub(:new, client) do
      get fleet_availability_path(fleet_availabilities(:one))
    end
    assert_response :success
    assert_select "a[href=?]", fleet_availabilities_path(dimensioning_id: period.id), minimum: 2
  end

  test "fleet list links and settings save retain the chosen period" do
    period = create_fleet_period
    get fleet_availabilities_path(dimensioning_id: period.id)
    assert_response :success
    assert_select "a[href=?]", fleet_availability_path(fleet_availabilities(:one), dimensioning_id: period.id)
    assert_select "input[name=dimensioning_id][value=?]", period.id.to_s
    patch fleet_availability_setting_path, params: {
      dimensioning_id: period.id, fleet_availability_setting: { auto_open_time: "06:00" }
    }
    assert_response :see_other
    assert_redirected_to fleet_availabilities_path(dimensioning_id: period.id)
  end

  test "fleet deletion retains the selected period" do
    period = create_fleet_period
    delete fleet_availability_path(fleet_availabilities(:one)), params: { dimensioning_id: period.id }
    assert_response :see_other
    assert_redirected_to fleet_availabilities_path(dimensioning_id: period.id)
  end

  test "fleet direct deletion and unlock use the record period as fallback" do
    period = create_fleet_period
    availability = fleet_availabilities(:one)
    availability.lock_availability!(users(:one))
    patch unlock_fleet_availability_path(availability)
    assert_response :see_other
    assert_redirected_to fleet_availability_path(availability, dimensioning_id: period.id)
    delete fleet_availability_path(availability)
    assert_response :see_other
    assert_redirected_to fleet_availabilities_path(dimensioning_id: period.id)
  end

  test "unified consultation carries its origin when redirected to AZ" do
    employee = Employee.create!(nome: "Consulta navegação", matricula: "NAV-AZ")
    employee.employee_roles.create!(sector: :az, cargo: :operador, turno: 0,
      starts_on: Date.new(2026, 1, 1), reason: "Cadastro")
    destination = variaveis_path
    get consulta_path, params: { matricula: employee.matricula, periodo_mes: 9,
      periodo_ano: 2026, return_to: destination }
    assert_redirected_to az_consulta_path(matricula: employee.matricula, periodo_mes: 9,
      periodo_ano: 2026, return_to: destination)
    follow_redirect!
    assert_response :success
    assert_select "a.az-report-back-link[href=?]", destination
  end

  test "consultation rejects external origins" do
    get az_consulta_path, params: { matricula: operators(:one).matricula,
      periodo_mes: 9, periodo_ano: 2026, return_to: "https://example.com" }
    assert_response :success
    assert_select "a.az-report-back-link[href=?]", az_consultas_new_path
  end

  test "AZ report retains its dashboard origin when changing period" do
    destination = dashboard_az_path(mes: 9, ano: 2026, turno: 0)
    [operators(:one), az_ajudantes(:one)].each do |person|
      get az_consulta_path, params: { matricula: person.matricula, periodo_mes: 9, periodo_ano: 2026, return_to: destination }
      assert_response :success
      assert_select "a.az-report-back-link[href=?]", destination
      assert_select "input[name=return_to][value=?]", destination
    end
  end

  private

  def create_invoice
    supplier = Supplier.create!(name: "Fornecedor de navegação", cnpj: "12345678000190")
    category = BudgetCategory.create!(name: "Categoria de navegação", sector: :frota)
    Invoice.create!(code: "NF-NAVEGACAO", supplier: supplier, budget_category: category,
      purchaser: users(:one), date_issued: Date.new(2026, 7, 1), due_date: Date.new(2026, 7, 10))
  end

  def create_fleet_period
    FleetDimensioning.create!(label: "Julho navegação", start_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 7, 31), route_quantity: 1)
  end
end
