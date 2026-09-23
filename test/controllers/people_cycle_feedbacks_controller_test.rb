require "test_helper"
require "caxlsx"

class PeopleCycleFeedbacksControllerTest < ActionDispatch::IntegrationTest
  test "requires login for reading and importing" do
    sign_out users(:one)
    get people_cycle_feedbacks_path
    assert_redirected_to new_user_session_path
    post people_cycle_feedbacks_path
    assert_redirected_to new_user_session_path
  end

  test "logged in users can view and import annual feedback without duplicates" do
    users(:one).update!(role: :user)
    person = drivers(:one)
    person.update!(nome: "Pessoa Unica Teste RH", active: true)
    with_sheet([[person.nome, "FeedBack", "Bom trabalho"]]) do |file|
      assert_difference("PeopleCycleFeedback.count", 1) { post people_cycle_feedbacks_path, params: { file: file } }
      assert_redirected_to people_cycle_feedbacks_path(cycle: Date.current.year)
      feedback = PeopleCycleFeedback.last
      assert_equal Date.current.year.to_s, feedback.cycle
      assert_equal "motorista", feedback.profile
      assert_equal person.id, feedback.employee_id
      assert_no_difference("PeopleCycleFeedback.count") { post people_cycle_feedbacks_path, params: { file: file } }
      get people_cycle_feedbacks_path
      assert_response :success
      assert_select "td", text: "Bom trabalho"
      identity = PublicVariableIdentity.new("motorista", person)
      assert_equal [feedback.id], PeopleCycleFeedback.for_identity(identity).pluck(:id)
      assert_empty PeopleCycleFeedback.for_identity(PublicVariableIdentity.new("ajudante", ajudantes(:one)))
    end
  end

  test "ambiguous and missing names are not linked to the chat" do
    drivers(:one).update!(nome: "Nome Repetido RH", active: true)
    ajudantes(:one).update!(nome: "Nome Repetido RH", active: true)
    with_sheet([["Nome Repetido RH", "FeedBack", "Texto"], ["Sem cadastro RH", "FeedBack", "Outro"]]) do |file|
      post people_cycle_feedbacks_path, params: { file: file, cycle: "2026" }
      assert_equal 2, PeopleCycleFeedback.where(employee_id: nil).count
      assert_empty PeopleCycleFeedback.for_identity(PublicVariableIdentity.new("motorista", drivers(:one)))
    end
  end

  test "links all four profiles by normalized name and updates reimported answers" do
    records = { "motorista" => drivers(:one), "operador" => operators(:one), "ajudante" => ajudantes(:one), "az_ajudante" => az_ajudantes(:one) }
    records.each_with_index do |(profile, person), index|
      person.update!(nome: "José Pessoa RH #{index}", active: true)
      with_sheet([["  JOSE   PESSOA RH #{index}  ", "FeedBack", "Resposta #{index}"]]) do |file|
        post people_cycle_feedbacks_path, params: { file: file, cycle: "2026" }
        assert_redirected_to people_cycle_feedbacks_path(cycle: "2026")
      end
      identity = PublicVariableIdentity.new(profile, person)
      assert_equal ["Resposta #{index}"], PeopleCycleFeedback.for_identity(identity).pluck(:response)
      with_sheet([[person.nome, "FeedBack", "Atualizada"]]) do |file|
        assert_no_difference("PeopleCycleFeedback.count") { post people_cycle_feedbacks_path, params: { file: file, cycle: "2026" } }
      end
      assert_equal ["Atualizada"], PeopleCycleFeedback.for_identity(identity).pluck(:response)
    end
  end

  test "invalid later row rolls back the whole file" do
    with_sheet([["Pessoa", "FeedBack", "Texto"], ["Outra", "FeedBack", nil]]) do |file|
      assert_no_difference("PeopleCycleFeedback.count") { post people_cycle_feedbacks_path, params: { file: file, cycle: "2026" } }
      assert_response :unprocessable_entity
      assert_match "Linha 3", response.body
    end
  end

  test "missing file and invalid year show validation errors" do
    post people_cycle_feedbacks_path, params: { cycle: "2026" }
    assert_response :unprocessable_entity
    post people_cycle_feedbacks_path, params: { cycle: "semestre" }
    assert_response :unprocessable_entity
  end

  private

  def with_sheet(rows)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Dados") do |sheet|
      sheet.add_row ["Colaborador", "ETAPA CICLO DE GENTE ", "Resposta"]
      rows.each { |row| sheet.add_row row }
    end
    Tempfile.create(["people-cycle", ".xlsx"]) do |file|
      package.serialize(file.path)
      yield Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
    end
  end
end
