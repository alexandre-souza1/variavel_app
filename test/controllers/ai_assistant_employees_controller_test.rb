require "test_helper"
require "minitest/mock"

class AiAssistantEmployeesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :hr)
    @conversation = AiConversation.create!(user: @user)
  end

  test "HR confirms the previewed DU employee once with career history adapter and source audit" do
    action = proposal(starts_on: "2026-10-10", promax: "000765", registered_on: "2026-10-01")
    assert_difference({ "Employee.count" => 1, "EmployeeRole.count" => 1, "Driver.count" => 1, "User.count" => 0 }) do
      post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token,
        payload: { nome: "Forjado", sector: "az" }, user_id: users(:two).id }, as: :json
      assert_response :success
    end
    employee = Employee.find(action.reload.result.fetch("id"))
    assert_equal "Novo Colaborador", employee.nome
    assert_equal "001234", employee.matricula
    assert_equal "du", employee.initial_role.sector
    assert_equal "000765", employee.drivers.first.promax
    assert_equal Date.new(2026, 10, 10), employee.initial_role.starts_on
    assert_equal Date.new(2026, 10, 1), employee.registered_on
    assert_equal @user, employee.initial_role.created_by
    assert_equal employee_path(employee), action.result["path"]
    audit = employee.employee_career_events.find_by!("details ->> 'source' = ?", "ai_assistant")
    assert_equal @user, audit.user
    assert_equal action.id, audit.details["ai_action_request_id"]
    assert_equal "executed", response.parsed_body["messages"].last["actions"].first["status"]
    assert_no_difference ["Employee.count", "EmployeeRole.count", "Driver.count", "EmployeeCareerEvent.count"] do
      confirm(action)
      assert_response :success
    end
  end

  test "admins outside HR can create AZ employees with the initial shift" do
    @user.update!(role: :admin, sector: :fleet)
    action = proposal(sector: "az", cargo: "operador", starts_on: "2026-10-10", turno: 0)
    assert_difference({ "Employee.count" => 1, "EmployeeRole.count" => 1, "Operator.count" => 1 }) do
      confirm(action)
      assert_response :success
    end
    employee = Employee.find(action.reload.result["id"])
    assert_equal 0, employee.initial_role.turno
    assert_equal 0, employee.operators.first.turno
    refute employee.initial_role.pending_start?
  end

  test "integration creates an initial pending role without releasing operational eligibility" do
    action = proposal
    confirm(action)
    assert_response :success
    employee = Employee.find(action.reload.result["id"])
    assert employee.initial_role.pending_start?
    assert_nil employee.initial_role.starts_on
    assert_nil employee.initial_role.promax
    refute employee.eligible_for?(:time_off)
    refute employee.eligible_for?(:pcd)
  end

  test "confirmation rechecks HR permissions and active status" do
    action = proposal
    [[:user, :fleet, true], [:supervisor, :du, true], [:mechanical, :hr, true], [:admin, :hr, false]].each do |role, sector, active|
      @user.update!(role: role, sector: sector, active: active)
      assert_no_difference ["Employee.count", "EmployeeRole.count"] do
        confirm(action)
        assert_includes [401, 403], response.status
      end
      assert_equal "pending", action.reload.status
    end
  end

  test "another account cannot confirm or cancel the employee proposal" do
    action = proposal
    users(:two).update!(role: :admin)
    sign_in users(:two)
    assert_no_difference "Employee.count" do
      confirm(action)
      assert_response :not_found
      post cancel_ai_assistant_action_path(action), as: :json
      assert_response :not_found
    end
  end

  test "token cancellation and expiry protect employee creation" do
    action = proposal
    assert_no_difference ["Employee.count", "EmployeeRole.count"] do
      post confirm_ai_assistant_action_path(action), params: { confirmation_token: "incorrect" }, as: :json
      assert_response :unprocessable_entity
      travel 31.minutes do
        confirm(action)
        assert_response :conflict
      end
      post cancel_ai_assistant_action_path(action), as: :json
      assert_response :success
      confirm(action)
      assert_response :conflict
    end
  end

  test "a registration taken since preview prevents a duplicate" do
    action = proposal
    Employee.create!(nome: "Cadastrado pela tela", matricula: "001234")
    assert_no_difference ["Employee.count", "EmployeeRole.count", "Driver.count"] do
      confirm(action)
      assert_response :unprocessable_entity
    end
    assert_equal "pending", action.reload.status
  end

  test "failure after registry creation rolls back employee adapters career audit and proposal execution" do
    action = proposal(starts_on: "2026-10-10", promax: "ROLLBACK-AI")
    original = Employees::Registry.method(:create!)
    failure = lambda do |**attributes|
      original.call(**attributes)
      raise EmployeeRole::HistoryError, "Falha no cadastro"
    end
    assert_no_difference ["Employee.count", "EmployeeRole.count", "Driver.count", "EmployeeCareerEvent.count"] do
      Employees::Registry.stub(:create!, failure) { confirm(action) }
      assert_response :unprocessable_entity
    end
    assert_equal "pending", action.reload.status
    assert_empty action.result
  end

  private

  def proposal(**attributes)
    draft = AiAssistant::ActionDraft.build(user: @user, kind: "create_employee", arguments: {
      nome: "Novo Colaborador", matricula: "001234", sector: "du", cargo: "motorista"
    }.merge(attributes))
    @conversation.update!(request_token: "ready", requested_at: Time.current)
    @conversation.finish!("ready", answer: { content: "Confira o cadastro.", sources: [], actions: [draft.to_h] })
    @conversation.ai_action_requests.order(:id).last
  end

  def confirm(action)
    post confirm_ai_assistant_action_path(action), params: { confirmation_token: action.confirmation_token }, as: :json
  end
end
