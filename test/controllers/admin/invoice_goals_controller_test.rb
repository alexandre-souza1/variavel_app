require "test_helper"

class Admin::InvoiceGoalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 28, 12)
    @category = BudgetCategory.create!(name: "Manutenção vigente", sector: :frota)
    @goal = InvoiceGoal.create!(name: "Meta recorrente", sector: :frota,
      reference_month: "2026-08", target_amount: 1000, budget_categories: [@category])
  end

  teardown { travel_back }

  test "a new indicator repeats automatically and has no end configuration" do
    get new_admin_invoice_goal_path
    assert_response :success
    assert_select 'input[name="invoice_goal[ends_at]"]', count: 0
    assert_difference "InvoiceGoal.count" do
      post admin_invoice_goals_path, params: { invoice_goal: {
        name: "Meta sem término", sector: "frota", reference_month: "2026-09", ends_at: "2026-10",
        target_amount: 500, budget_category_ids: [@category.id]
      } }
    end
    assert_redirected_to admin_invoice_goals_path
    goal = InvoiceGoal.find_by!(name: "Meta sem término")
    assert_nil goal.ends_at
    assert_includes InvoiceGoal.effective_on(Date.new(2027, 1, 1)), goal
  end

  test "alter target only asks for value and start month with categories collapsed" do
    get edit_admin_invoice_goal_path(@goal)
    assert_response :success
    assert_select 'input[name="invoice_goal[name]"]', count: 0
    assert_select 'select[name="invoice_goal[sector]"]', count: 0
    assert_select 'input[name="invoice_goal[ends_at]"]', count: 0
    assert_select 'input[name="invoice_goal[reference_month]"][value="2026-10"]'
    assert_select 'input[name="invoice_goal[target_amount]"][value="1000.0"]'
    assert_select 'details.invoice-goal-categories:not([open])'
    assert_select "input[type=checkbox][value='#{@category.id}'][checked]"
  end

  test "saving a different month creates a change without modifying past targets or indicator identity" do
    assert_difference "InvoiceGoal.count" do
      patch admin_invoice_goal_path(@goal), params: { invoice_goal: {
        name: "Outra meta", sector: "financeiro", reference_month: "2026-10", target_amount: 2000
      } }
    end
    assert_redirected_to admin_invoice_goals_path
    assert_equal 1000, @goal.reload.target_amount
    assert_equal [@goal.id], InvoiceGoal.effective_on(Date.new(2026, 9, 1)).ids
    revised = InvoiceGoal.effective_on(Date.new(2026, 10, 1)).sole
    assert_equal 2000, revised.target_amount
    assert_equal @goal.name, revised.name
    assert_equal @goal.sector, revised.sector
    assert_equal @goal.budget_category_ids, revised.budget_category_ids
  end

  test "saving the same month twice changes its amount without duplicate entries" do
    2.times do |index|
      patch admin_invoice_goal_path(@goal), params: { invoice_goal: { reference_month: "2026-10", target_amount: 2000 + index } }
      assert_redirected_to admin_invoice_goals_path
    end
    assert_equal 1, InvoiceGoal.where(name: @goal.name, reference_month: "2026-10-01").count
    assert_equal [2001], InvoiceGoal.effective_on(Date.new(2026, 10, 1)).pluck(:target_amount)
    assert_equal 1000, @goal.reload.target_amount
  end

  test "invalid change stays in the simple form and does not change stored data" do
    patch admin_invoice_goal_path(@goal), params: { invoice_goal: { reference_month: "2026-13", target_amount: 2000 } }
    assert_response :unprocessable_entity
    assert_select '.invoice-goal-editor h1', text: "Alterar meta"
    assert_select '.alert-danger'
    assert_equal 1000, @goal.reload.target_amount
    assert_equal Date.new(2026, 8, 1), @goal.reference_month
  end

  test "creating the same indicator again points to alter instead of silently adding a version" do
    assert_no_difference "InvoiceGoal.count" do
      post admin_invoice_goals_path, params: { invoice_goal: {
        name: @goal.name, sector: @goal.sector, reference_month: "2026-10",
        target_amount: 500, budget_category_ids: [@category.id]
      } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Use Alterar meta"
  end

  test "index shows one indicator in the standard table and keeps history in its modal" do
    InvoiceGoal.create!(name: @goal.name, sector: :frota, reference_month: "2026-09",
      target_amount: 2000, budget_categories: [@category])
    scheduled = InvoiceGoal.create!(name: @goal.name, sector: :frota, reference_month: "2026-12",
      target_amount: 3000, budget_categories: [@category])
    get admin_invoice_goals_path
    assert_response :success
    assert_select '.invoice-indicator', count: 1
    assert_select '.invoice-indicator-amount strong', text: 'R$ 2.000,00'
    assert_select '.admin-catalog-table tbody tr.invoice-indicator', count: 1
    assert_select '.modal.app-modal.invoice-indicator-history[aria-hidden="true"]', count: 1
    assert_select '.invoice-indicator-history .invoice-goal-history-record', count: 3
    assert_select '.invoice-indicator-history details:not([open])', count: 1
    assert_select '.invoice-indicator-history table', count: 0
    assert_select '.invoice-indicator button[data-bs-toggle="modal"]', count: 1
    assert_select '.invoice-indicator-scheduled', text: /3\.000,00.*[Dd]ezembro/m
    assert_select ".invoice-indicator-scheduled a[href='#{edit_admin_invoice_goal_path(scheduled)}']"
    assert_select '.invoice-indicator-change[title="Alterar meta"]'
    refute_includes response.body, "Nova vigência"
  end

  test "expired and future indicators never present their old or scheduled amounts as current" do
    @goal.update!(ends_at: "2026-09")
    scheduled = InvoiceGoal.create!(name: "Indicador futuro", sector: :frota, reference_month: "2026-12",
      target_amount: 3000, budget_categories: [@category])
    get admin_invoice_goals_path
    assert_response :success
    assert_select '.invoice-indicator', count: 2
    assert_select '.invoice-indicator-unset', text: 'Sem meta definida', count: 2
    assert_select '.invoice-indicator-scheduled', count: 1
    get edit_admin_invoice_goal_path(scheduled)
    assert_select 'input[name="invoice_goal[reference_month]"][value="2026-12"]'
  end

  test "dashboard selects the latest validity only once and respects the end month" do
    revised = InvoiceGoal.create!(name: @goal.name, sector: :frota,
      reference_month: "2026-10", target_amount: 2000, budget_categories: [@category])
    get dashboard_invoices_path, params: { month: 9, year: 2026, sector: "frota" }
    assert_response :success
    assert_select '.invoice-goal-row', count: 1
    assert_select '.invoice-goal-values small', text: /1\.000,00/
    get dashboard_invoices_path, params: { month: 11, year: 2026, sector: "frota" }
    assert_response :success
    assert_select '.invoice-goal-row', count: 1
    assert_select '.invoice-goal-values small', text: /2\.000,00/
    revised.update!(ends_at: "2026-11")
    @goal.update!(ends_at: "2026-09")
    get dashboard_invoices_path, params: { month: 12, year: 2026, sector: "frota" }
    assert_response :success
    assert_select '.invoice-goal-row', count: 0
  end

  test "old revision links redirect to the simplified editor" do
    get new_admin_invoice_goal_path, params: { version_of: @goal.id }
    assert_redirected_to edit_admin_invoice_goal_path(@goal)
  end

  test "only admin and finance can manage targets" do
    user = users(:one)
    user.update!(role: :user, sector: :fleet)
    get edit_admin_invoice_goal_path(@goal)
    assert_redirected_to root_path
    assert_no_difference "InvoiceGoal.count" do
      patch admin_invoice_goal_path(@goal), params: { invoice_goal: { reference_month: "2026-10", target_amount: 2000 } }
    end
    assert_redirected_to root_path
    user.update!(sector: :finance)
    get edit_admin_invoice_goal_path(@goal)
    assert_response :success
  end
end
