require "test_helper"

class AiAssistantEmployeeDraftsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :hr, name: "Ana RH")
    @tools = AiAssistant::Tools.new(@user)
  end

  test "only active admins and HR accounts can advertise or directly prepare employee creation" do
    User.roles.keys.each do |role|
      User.sectors.keys.each do |sector|
        @user.update!(role: role, sector: sector)
        allowed = role != "mechanical" && (role == "admin" || sector == "hr")
        assert_equal allowed, @tools.declarations.any? { |entry| entry[:name] == "prepare_employee" }, "#{role}/#{sector}"
        result = @tools.call("prepare_employee", arguments)
        assert_equal allowed, result[:confirmation_required] == true, "#{role}/#{sector}: #{result.inspect}"
      end
    end
    @user.update!(role: :admin, active: false)
    refute @tools.declarations.any? { |entry| entry[:name] == "prepare_employee" }
    assert @tools.call("prepare_employee", arguments)[:error]
  end

  test "preview preserves identity and employment dates without writing any business records" do
    result = nil
    assert_no_difference ["Employee.count", "EmployeeRole.count", "Driver.count", "Operator.count", "EmployeeCareerEvent.count", "AiActionRequest.count", "User.count"] do
      result = @tools.call("prepare_employee", arguments.merge(
        cpf: "123.456.789-00", data_nascimento: "1990-01-02", registered_on: "2026-10-01",
        starts_on: "2026-10-10", promax: "00123"))
    end
    assert result[:confirmation_required], result.inspect
    refute result[:executed]
    draft = @tools.drafts.first
    assert_equal "create_employee", draft[:kind]
    assert_equal "001234", draft[:payload]["matricula"]
    assert_equal "00123", draft[:payload]["promax"]
    assert_equal "Confirmar cadastro", result[:preview]["confirmation_label"]
    values = result[:preview]["details"].map { |item| item["value"] }
    %w[001234 00123 01/10/2026 10/10/2026 02/01/1990 123.456.789-00 DU Motorista].each { |value| assert_includes values, value }
    refute_includes result.to_json, "confirmation_token"
    restored = AiAssistant::ActionDraft.restore(user: @user, kind: draft[:kind], payload: draft[:payload])
    assert_equal draft, restored.to_h
  end

  test "integration allows missing operational fields in both sectors and preserves shift A as zero" do
    { "du" => %w[ajudante van motorista], "az" => %w[ajudante operador] }.each do |sector, cargos|
      cargos.each do |cargo|
        draft = AiAssistant::ActionDraft.build(user: @user, kind: "create_employee", arguments: arguments.merge(sector: sector, cargo: cargo))
        assert_nil draft.payload["starts_on"]
        assert_includes draft.preview["notices"].join, "em integração"
      end
    end
    result = @tools.call("prepare_employee", arguments.merge(sector: "az", cargo: "operador", turno: 0, starts_on: "2026-10-10"))
    assert result[:confirmation_required], result.inspect
    assert_equal 0, @tools.drafts.last[:payload]["turno"]
    assert_includes result[:preview]["details"], { "label" => "Turno", "value" => "A" }
  end

  test "missing required data invalid dates and mismatched operational fields are refused" do
    invalid = [
      { nome: "" }, { matricula: "" }, { sector: "" }, { sector: "fleet" }, { cargo: "" },
      { cargo: "operador" }, { sector: "az", cargo: "motorista" },
      { starts_on: "amanhã" }, { starts_on: "2026-02-30" }, { starts_on: false },
      { registered_on: "2026-02-30" }, { data_nascimento: "invalid" },
      { registered_on: "2026-10-11", starts_on: "2026-10-10", promax: "NEW-CODE" },
      { starts_on: "2026-10-10" }, { sector: "az", cargo: "operador", starts_on: "2026-10-10" },
      { turno: 0 }, { sector: "az", cargo: "operador", promax: "DU-CODE" },
      { sector: "az", cargo: "operador", turno: 3 }, { sector: "az", cargo: "operador", turno: 0.5 },
      { active: false }, { historical_only: true }, { created_by_id: users(:two).id },
      { user_id: users(:two).id }, { legacy: true }, { pending_start: false }
    ]
    assert_no_difference ["Employee.count", "EmployeeRole.count", "EmployeeCareerEvent.count"] do
      invalid.each { |changes| assert @tools.call("prepare_employee", arguments.merge(changes))[:error], changes.inspect }
    end
    assert_empty @tools.drafts
  end

  test "existing registrations and overlapping DU codes do not produce a proposal" do
    employee = Employees::Registry.create!(attributes: { nome: "Existente", matricula: "EXIST-AI" },
      role: { sector: "du", cargo: "motorista", promax: "EXIST-CODE-AI", starts_on: "2026-10-01", reason: "Teste" }, user: @user)
    assert @tools.call("prepare_employee", arguments.merge(matricula: employee.matricula))[:error]
    assert @tools.call("prepare_employee", arguments.merge(promax: "EXIST-CODE-AI", starts_on: "2026-10-10"))[:error]
    assert_empty @tools.drafts
  end

  private

  def arguments
    { nome: "Novo Colaborador", matricula: "001234", sector: "du", cargo: "motorista" }
  end
end
